import XCTest
@testable import NecarambaCore
final class WordBufferTests: XCTestCase {
    func event(_ text: String?, epoch: UInt64 = 1, origin: EventOrigin = .physical, code: UInt16 = 0, modifiers: Set<Modifier> = []) -> InputEvent {
        .init(kind: .down, keyCode: code, modifiers: modifiers, timestampNanos: 1, layout: .init(rawValue: "US"), context: .init(pid: 42, bundleID: "test.editor", focusEpoch: epoch, layoutEpoch: 1), origin: origin, text: text, isRepeat: false)
    }
    func testBoundsAndOverflowWaitsForBoundary() {
        var b = WordBuffer(maxGraphemes: 128, maxUTF16: 512)
        for _ in 0..<128 { XCTAssertNil(b.consume(event("a"))) }
        XCTAssertEqual(b.consume(event(" "))?.text.count, 128)
        for _ in 0..<129 { _ = b.consume(event("a")) }
        _ = b.consume(event("b"))
        XCTAssertNil(b.consume(event(" ")))
        _ = b.consume(event("x"))
        XCTAssertEqual(b.consume(event(" "))?.text, "x")
    }
    func testUTF16Bound() {
        var b = WordBuffer(maxGraphemes: 128, maxUTF16: 4)
        _ = b.consume(event("a\u{301}\u{302}\u{303}\u{304}"))
        XCTAssertNil(b.consume(event(" ")))
    }
    func testFocusSyntheticAndNavigationInvalidate() {
        for interruption in [event(" ", epoch: 2), event("b", origin: .foreignSynthetic), event(nil, code: 123), event("v", modifiers: [.command])] {
            var b = WordBuffer()
            _ = b.consume(event("a")); _ = b.consume(interruption)
            XCTAssertNil(b.consume(event(" ")))
        }
    }
    func testOursIgnoredAndDelimiterExactlyOnce() {
        var b = WordBuffer()
        _ = b.consume(event("a")); _ = b.consume(event("b", origin: .ours))
        let word = b.consume(event(" "))
        XCTAssertEqual(word?.text, "a"); XCTAssertEqual(word?.delimiter, " ")
        XCTAssertNil(b.consume(event(" ")))
    }
    func testUnconfirmedBackspaceAndPasteDiscard() {
        var b = WordBuffer()
        _ = b.consume(event("a")); _ = b.consume(event(nil, code: 51))
        XCTAssertNil(b.consume(event(" ")))
        _ = b.consume(event("pasted")); XCTAssertNil(b.consume(event(" ")))
    }
}
