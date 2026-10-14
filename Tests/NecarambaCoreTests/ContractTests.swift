import XCTest
import NecarambaCore

final class ContractTests: XCTestCase {
    func testDefaultsAndSnapshotRoundTrip() throws {
        let preferences = PreferencesSnapshot.defaults
        XCTAssertTrue(preferences.autoEnabled)
        XCTAssertTrue(preferences.typoEnabled)
        XCTAssertTrue(preferences.yoEnabled)
        XCTAssertTrue(preferences.singleShiftEnabled)
        XCTAssertTrue(preferences.plainPasteEnabled)
        XCTAssertTrue(preferences.soundEnabled)
        XCTAssertFalse(preferences.optionEnabled)
        XCTAssertFalse(preferences.splitShiftEnabled)
        XCTAssertEqual(try roundTrip(preferences), preferences)
        XCTAssertEqual(try roundTrip(RuleSnapshot(modelVersion: 7)), RuleSnapshot(modelVersion: 7))
        XCTAssertNotEqual(LayoutID(rawValue: "com.apple.keylayout.Russian"), LayoutID(rawValue: "com.apple.keylayout.RussianWin"))
    }

    func testPopulatedRuleSnapshotPreservesUnicodeAndFields() throws {
        let us = LayoutID(rawValue: "US")
        let ru = LayoutID(rawValue: "RU")
        let snapshot = RuleSnapshot(modelVersion: 42,
            lexicon: [Lexeme(word: "ёлка", language: .russian, frequencyBand: 5)],
            typos: [ReplacementRule(source: "teh", target: "the", caseSensitive: false)],
            yoRules: [ReplacementRule(source: "елка", target: "ёлка", caseSensitive: true)],
            protectedTokens: ["API", "🙂"],
            mappings: [LayoutMapping(source: us, target: ru, pairs: ["g": "п"])])
        XCTAssertEqual(try roundTrip(snapshot), snapshot)
    }

    func testExplicitPreferencesPreserveEveryFlag() throws {
        let preferences = PreferencesSnapshot(autoEnabled: false, typoEnabled: false,
            yoEnabled: false, singleShiftEnabled: false, optionEnabled: true,
            splitShiftEnabled: true, plainPasteEnabled: false, soundEnabled: false)
        XCTAssertEqual(try roundTrip(preferences), preferences)
        XCTAssertNotEqual(preferences, .defaults)
    }

    func testInputEventPreservesContextAndPhysicalMetadata() throws {
        let context = ContextToken(pid: 42, bundleID: "test.editor", focusEpoch: 9, layoutEpoch: 3)
        let event = InputEvent(kind: .down, keyCode: 12, modifiers: [.shift, .option],
            timestampNanos: 123, layout: LayoutID(rawValue: "US"), context: context,
            origin: .physical, text: "Q", isRepeat: true)
        XCTAssertEqual(try roundTrip(context), context)
        XCTAssertEqual(event.context, context)
        XCTAssertEqual(event.keyCode, 12)
        XCTAssertEqual(event.modifiers, [.shift, .option])
        XCTAssertEqual(event.timestampNanos, 123)
        XCTAssertEqual(event.layout.rawValue, "US")
        XCTAssertEqual(event.kind, .down)
        XCTAssertEqual(event.origin, .physical)
        XCTAssertEqual(event.text, "Q")
        XCTAssertTrue(event.isRepeat)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}
