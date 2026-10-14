import Foundation
import XCTest
@testable import NecarambaCore

final class LayoutShortcutPreferencesTests: XCTestCase {
    func testNewShortcutSurvivesRoundTripWithLegacyProjection() throws {
        let data = Data(#"{"autoEnabled":true,"typoEnabled":true,"yoEnabled":true,"singleShiftEnabled":false,"optionEnabled":true,"splitShiftEnabled":false,"plainPasteEnabled":true,"soundEnabled":true,"layoutSwitchShortcut":"altShift"}"#.utf8)
        let preferences = try JSONDecoder().decode(PreferencesSnapshot.self, from: data)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertEqual(encoded["layoutSwitchShortcut"] as? String, "altShift")
        XCTAssertEqual(encoded["singleShiftEnabled"] as? Bool, false)
    }

    func testLegacyPreferencesKeepSingleShiftChoice() throws {
        for (enabled, expected) in [(true, "singleShift"), (false, "disabled")] {
            let legacy = PreferencesSnapshot(singleShiftEnabled: enabled)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            object.removeValue(forKey: "layoutSwitchShortcut")
            let migrated = try JSONDecoder().decode(PreferencesSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any])
            XCTAssertEqual(encoded["layoutSwitchShortcut"] as? String, expected)
        }
    }

    func testUnknownAndContradictoryShortcutsAreRejected() throws {
        for shortcut in ["unknown", "altShift", "disabled"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PreferencesSnapshot.defaults)) as? [String: Any])
            object["layoutSwitchShortcut"] = shortcut
            XCTAssertThrowsError(try JSONDecoder().decode(PreferencesSnapshot.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }
}

final class LayoutShortcutGestureTests: XCTestCase {
    private func event(_ key: UInt16, _ modifiers: Set<Modifier>, _ time: UInt64,
                       origin: EventOrigin = .physical, epoch: UInt64 = 1) -> InputEvent {
        .init(kind: .flagsChanged, keyCode: key, modifiers: modifiers, timestampNanos: time,
              layout: .init(rawValue: "US"),
              context: .init(pid: 42, bundleID: "test", focusEpoch: epoch, layoutEpoch: 1),
              origin: origin, text: nil, isRepeat: false)
    }
    private func recognizer(_ shortcut: LayoutSwitchShortcut) -> GestureRecognizer {
        .init(configuration: .init(singleShift: false, option: true, splitShift: true,
                                   layoutSwitchShortcut: shortcut))
    }

    func testChordsSwitchOnceAfterBothReleasedInEitherOrderAndSide() {
        for (shortcut, modifier, keys) in [
            (LayoutSwitchShortcut.altShift, Modifier.option, [UInt16(58), 61]),
            (.controlShift, .control, [UInt16(59), 62])
        ] {
            for shift: UInt16 in [56, 60] {
                for partner in keys {
                    for shiftFirst in [true, false] {
                        for releaseShiftFirst in [true, false] {
                            var r = recognizer(shortcut)
                            XCTAssertEqual(r.consume(event(shiftFirst ? shift : partner, shiftFirst ? [.shift] : [modifier], 1)), [])
                            XCTAssertEqual(r.consume(event(shiftFirst ? partner : shift, [.shift, modifier], 2)), [])
                            XCTAssertEqual(r.consume(event(releaseShiftFirst ? shift : partner, releaseShiftFirst ? [modifier] : [.shift], 3)), [])
                            XCTAssertEqual(r.consume(event(releaseShiftFirst ? partner : shift, [], 4)), [.switchLayout])
                            XCTAssertEqual(r.advance(to: 900_000_000), [])
                        }
                    }
                }
            }
        }
    }

    func testTypingExtraModifiersForeignEventsAndContextCancelChord() {
        for shortcut in [LayoutSwitchShortcut.altShift, .controlShift] {
            let key: UInt16 = shortcut == .altShift ? 58 : 59
            let modifier: Modifier = shortcut == .altShift ? .option : .control
            for interruption in [
                event(0, [.shift, modifier], 3),
                event(55, [.shift, modifier, .command], 3),
                event(0, [.shift, modifier], 3, origin: .foreignSynthetic),
                event(0, [.shift, modifier], 3, epoch: 2),
                event(60, [.shift, modifier], 3)
            ] {
                var r = recognizer(shortcut)
                _ = r.consume(event(56, [.shift], 1))
                _ = r.consume(event(key, [.shift, modifier], 2))
                XCTAssertEqual(r.consume(interruption), [])
                XCTAssertEqual(r.consume(event(56, [modifier], 4)), [])
                XCTAssertEqual(r.consume(event(key, [], 5)), [])
                XCTAssertEqual(r.advance(to: 900_000_000), [])
            }
        }
    }

    func testDoubleShiftAndSplitRemainAvailableWithEveryShortcut() {
        for shortcut in LayoutSwitchShortcut.allCases {
            var r = recognizer(shortcut)
            _ = r.consume(event(56, [.shift], 1))
            _ = r.consume(event(56, [], 2))
            _ = r.consume(event(60, [.shift], 30_000_000))
            XCTAssertEqual(r.consume(event(60, [], 40_000_000)), [.manualCorrection])
            XCTAssertEqual(r.advance(to: 900_000_000), [])
            r = recognizer(shortcut)
            _ = r.consume(event(56, [.shift], 1))
            XCTAssertEqual(r.consume(event(60, [.shift], 2)), [.toggleAuto])
            XCTAssertEqual(r.consume(event(56, [.shift], 3)), [])
            XCTAssertEqual(r.consume(event(60, [], 4)), [])
        }
    }

    func testUnobservedHeldModifierCannotTriggerManualOrSplitGesture() {
        var r = recognizer(.altShift)
        _ = r.consume(event(58, [.option, .shift], 1))
        XCTAssertEqual(r.consume(event(58, [.shift], 2)), [])
        r = recognizer(.altShift)
        _ = r.consume(event(56, [.shift, .option], 1))
        XCTAssertEqual(r.consume(event(60, [.shift, .option], 2)), [])
    }

    func testOnlySelectedChordSwitchesAndOptionAloneRemainsManual() {
        for shortcut in LayoutSwitchShortcut.allCases {
            for (key, modifier, selected) in [(UInt16(58), Modifier.option, LayoutSwitchShortcut.altShift),
                                               (UInt16(59), .control, .controlShift)] {
                var r = recognizer(shortcut)
                _ = r.consume(event(key, [modifier], 1))
                _ = r.consume(event(56, [.shift, modifier], 2))
                _ = r.consume(event(key, [.shift], 3))
                XCTAssertEqual(r.consume(event(56, [], 4)), shortcut == selected ? [.switchLayout] : [])
                XCTAssertEqual(r.advance(to: 900_000_000), [])
            }
            var r = recognizer(shortcut)
            _ = r.consume(event(58, [.option], 1))
            XCTAssertEqual(r.consume(event(58, [], 2)), [.manualCorrection])
        }
    }
}
