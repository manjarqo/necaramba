import XCTest
@testable import NecarambaCore
final class GestureRecognizerTests: XCTestCase {
    func event(_ key: UInt16, _ down: Bool, _ ms: UInt64, modifiers: Set<Modifier>? = nil, repeatKey: Bool = false, epoch: UInt64 = 1) -> InputEvent {
        .init(kind: .flagsChanged, keyCode: key, modifiers: modifiers ?? (down ? [key == 58 || key == 61 ? .option : .shift] : []), timestampNanos: ms * 1_000_000, layout: .init(rawValue: "US"), context: .init(pid: 42, bundleID: "test", focusEpoch: epoch, layoutEpoch: 1), origin: .physical, text: nil, isRepeat: repeatKey)
    }
    func recognizer(split: Bool = false, option: Bool = false, single: Bool = true) -> GestureRecognizer { .init(configuration: .init(singleShift: single, option: option, splitShift: split)) }
    func testDelayedSingleAndMixedSideDouble() {
        var r = recognizer(); XCTAssertEqual(r.consume(event(56, true, 0)), [])
        XCTAssertEqual(r.consume(event(56, false, 20)), [])
        XCTAssertEqual(r.advance(to: 319_000_000), [])
        XCTAssertEqual(r.advance(to: 320_000_000), [.switchLayout])
        r = recognizer(); _ = r.consume(event(56, true, 0)); _ = r.consume(event(56, false, 20))
        _ = r.consume(event(60, true, 180)); XCTAssertEqual(r.consume(event(60, false, 200)), [.manualCorrection])
        XCTAssertEqual(r.advance(to: 600_000_000), [])
    }
    func testSplitOverlapOnceAndNeverSingle() {
        var r = recognizer(split: true)
        _ = r.consume(event(56, true, 0))
        XCTAssertEqual(r.consume(event(60, true, 10)), [.toggleAuto])
        XCTAssertEqual(r.consume(event(60, false, 20, modifiers: [.shift])), [])
        XCTAssertEqual(r.consume(event(56, false, 30)), [])
        XCTAssertEqual(r.advance(to: 600_000_000), [])
    }
    func testChordsRepeatInvalidationAndContext() {
        for interruption in [event(0, true, 10), event(56, true, 10, modifiers: [.shift, .command]), event(56, false, 20, epoch: 2)] {
            var r = recognizer(); _ = r.consume(event(56, true, 0)); _ = r.consume(interruption)
            _ = r.consume(event(56, false, 30)); XCTAssertEqual(r.advance(to: 600_000_000), [])
        }
        var r = recognizer(); _ = r.consume(event(56, true, 0)); _ = r.consume(event(56, true, 10, repeatKey: true)); _ = r.consume(event(56, false, 20)); r.invalidate()
        XCTAssertEqual(r.advance(to: 600_000_000), [])
    }
    func testOptionAndDoubleWithoutSingle() {
        var r = recognizer(option: true); _ = r.consume(event(58, true, 0))
        XCTAssertEqual(r.consume(event(58, false, 20)), [.manualCorrection])
        r = recognizer(); _ = r.consume(event(58, true, 0)); XCTAssertEqual(r.consume(event(58, false, 20)), [])
        r = recognizer(single: false); _ = r.consume(event(56, true, 0)); _ = r.consume(event(56, false, 20)); _ = r.consume(event(56, true, 100))
        XCTAssertEqual(r.consume(event(56, false, 120)), [.manualCorrection])
    }
    func testMillionEventReplayBoundedState() {
        var r = recognizer()
        for n in 0..<1_000_000 { XCTAssertEqual(r.consume(event(0, true, UInt64(n))), []) }
        XCTAssertEqual(r.advance(to: 2_000_000_000_000), [])
    }
}
