import CoreGraphics
import NecarambaCore
import XCTest
@testable import NecarambaMac

final class MissingInputCaptureTests: XCTestCase {
  func testLostKeyInGestureOnlyFocusCannotTurnRecoveredTailIntoWholeWord() throws {
    try assertGapSafety(gestureContextAvailable: true)
  }
  func testLostKeyWithoutAnyContextCannotTurnRecoveredTailIntoWholeWord() throws {
    try assertGapSafety(gestureContextAvailable: false)
  }
  func testCommandTabWithoutContextDoesNotBlockFirstWordInNewApplication() throws {
    try assertFreshWordInOtherApplication(missingOrdinaryKey: false)
  }
  func testKnownApplicationGapDoesNotBlockFreshWordInDifferentApplication() throws {
    try assertFreshWordInOtherApplication(missingOrdinaryKey: true)
  }
  private func assertFreshWordInOtherApplication(missingOrdinaryKey: Bool) throws {
    let context = GapContext()
    var candidates: [AutomaticBoundaryCandidate] = []
    let runtime = InputRuntime(context: context, initialLayout: .init(rawValue: "US"),
      snapshot: .init(modelVersion: 1, lexicon: [.init(word: "hello", language: .english, frequencyBand: 1)]),
      conservativeAutomaticEnabled: true, command: {
        if case .automaticBoundary(let candidate, _, _) = $0 { candidates.append(candidate) }
      })
    let adapter = EventTapAdapter(runtime: runtime)
    context.safe = false
    context.hasGesture = missingOrdinaryKey
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil,
      virtualKey: missingOrdinaryKey ? 37 : 48, keyDown: true))
    event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
    event.flags = missingOrdinaryKey ? [] : [.maskCommand]
    XCTAssertTrue(adapter.receive(.keyDown, event))
    context.token = .init(pid: 99, bundleID: "other", focusEpoch: 3, layoutEpoch: 1)
    context.safe = true
    for character in "hello" {
      runtime.accept(.init(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
        layout: .init(rawValue: "US"), context: context.token, origin: .physical,
        text: String(character), isRepeat: false))
    }
    XCTAssertEqual(runtime.manualWord()?.text, "hello")
    runtime.accept(.init(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: .init(rawValue: "US"), context: context.token, origin: .physical,
      text: " ", isRepeat: false))
    let drained = expectation(description: "new application first word delivered")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 1)
    XCTAssertTrue(candidates.last?.allowsOpaqueWordStart == true)
    XCTAssertEqual(candidates.last?.word.text, "hello")
  }
  private func assertGapSafety(gestureContextAvailable: Bool) throws {
    let context = GapContext()
    var candidates: [AutomaticBoundaryCandidate] = []
    let runtime = InputRuntime(context: context, initialLayout: .init(rawValue: "US"),
      snapshot: .init(modelVersion: 1, lexicon: [.init(word: "hello", language: .english, frequencyBand: 1)]),
      conservativeAutomaticEnabled: true, command: {
        if case .automaticBoundary(let candidate, _, _) = $0 { candidates.append(candidate) }
      })
    let adapter = EventTapAdapter(runtime: runtime)
    func type(_ text: String) {
      for character in text {
        runtime.accept(.init(kind: .down, keyCode: character == " " ? 49 : 0, modifiers: [],
          timestampNanos: 1, layout: .init(rawValue: "US"), context: context.token,
          origin: .physical, text: String(character), isRepeat: false))
      }
    }
    type("hel")
    context.safe = false
    context.hasGesture = gestureContextAvailable
    let dropped = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 37, keyDown: true))
    dropped.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
    XCTAssertTrue(adapter.receive(.keyDown, dropped))
    context.token = .init(pid: 42, bundleID: "test", focusEpoch: 3, layoutEpoch: 1)
    context.safe = true
    type("lo")
    XCTAssertNil(runtime.manualWord(), "A tail after lost input cannot authorize manual deletion")
    type(" ")
    XCTAssertNil(runtime.manualWord(), "Space cannot publish the incomplete tail as a recent word")
    let drained = expectation(description: "tail boundary delivered")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 1)
    XCTAssertEqual(candidates.count, 1)
    XCTAssertTrue(candidates.first?.requiresWordStartProof == true)
    XCTAssertFalse(candidates.first?.allowsOpaqueWordStart ?? true)
    type("hello")
    XCTAssertEqual(runtime.manualWord()?.text, "hello")
    type(" ")
    let next = expectation(description: "next whole word delivered")
    DispatchQueue.main.async { next.fulfill() }
    wait(for: [next], timeout: 1)
    XCTAssertEqual(candidates.count, 2)
    XCTAssertTrue(candidates.last?.allowsOpaqueWordStart == true)
    XCTAssertEqual(candidates.last?.word.text, "hello")
  }
}
private final class GapContext: ContextAccess, GestureContextReading {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  var safe = true
  var hasGesture = true
  func current() -> ContextToken? { safe ? token : nil }
  func gestureContext() -> ContextToken? { hasGesture ? token : nil }
  func isSafe(_ token: ContextToken) -> Bool { safe && token == self.token }
}
