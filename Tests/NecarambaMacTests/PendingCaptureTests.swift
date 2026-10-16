import XCTest
import NecarambaCore
@testable import NecarambaMac

/// Keys typed while the application is known but its field is not yet confirmed
/// may complete a word only behind a readable whole-word AX proof.
final class PendingCaptureTests: XCTestCase {
  private let us = LayoutID(rawValue: "US")

  private func harness() -> (PendingContext, InputRuntime, () -> [AutomaticBoundaryCandidate]) {
    let context = PendingContext()
    var candidates: [AutomaticBoundaryCandidate] = []
    let runtime = InputRuntime(context: context, initialLayout: us,
      snapshot: .init(modelVersion: 1, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)]),
      conservativeAutomaticEnabled: true, command: {
        if case .automaticBoundary(let candidate, _, _) = $0 { candidates.append(candidate) }
      })
    return (context, runtime, {
      let drained = self.expectation(description: "boundary delivered")
      DispatchQueue.main.async { drained.fulfill() }
      self.wait(for: [drained], timeout: 1)
      return candidates
    })
  }
  private func type(_ text: String, _ runtime: InputRuntime, _ token: ContextToken) {
    for character in text {
      runtime.accept(.init(kind: .down, keyCode: character == " " ? 49 : 0, modifiers: [],
        timestampNanos: 1, layout: us, context: token, origin: .physical,
        text: String(character), isRepeat: false))
    }
  }

  func testWordStartedBeforeFieldConfirmationRequiresReadableWholeWordProof() {
    let (context, runtime, delivered) = harness()
    context.safe = false
    type("ghb", runtime, context.gesture)
    context.confirm(focusEpoch: 3)
    type("dtn ", runtime, context.token)
    let candidate = delivered().last
    XCTAssertEqual(candidate?.word.text, "ghbdtn")
    XCTAssertEqual(candidate?.requiresWordStartProof, true)
    XCTAssertEqual(candidate?.allowsOpaqueWordStart, false, "Opaque fields cannot prove the recovered prefix")
    XCTAssertTrue(candidate?.word.events.allSatisfy { $0.context == context.token } == true)
  }

  func testPrefixTypedInConfirmedFieldSurvivesTheGap() {
    let (context, runtime, delivered) = harness()
    type("gh", runtime, context.token)
    context.safe = false
    type("b", runtime, context.gesture)
    context.confirm(focusEpoch: 4)
    type("dtn ", runtime, context.token)
    XCTAssertEqual(delivered().last?.word.text, "ghbdtn")
  }

  func testPendingInputFromAnotherApplicationIsDiscarded() {
    let (context, runtime, delivered) = harness()
    context.safe = false
    type("ghb", runtime, context.gesture)
    context.confirm(focusEpoch: 3, pid: 77, bundleID: "other")
    type("dtn ", runtime, context.token)
    XCTAssertEqual(delivered().last?.word.text, "dtn")
  }

  func testNavigationOrPointerDuringTheGapDiscardsPendingInput() {
    for interruption in 0..<2 {
      let (context, runtime, delivered) = harness()
      context.safe = false
      type("ghb", runtime, context.gesture)
      if interruption == 0 {
        runtime.accept(.init(kind: .down, keyCode: 123, modifiers: [], timestampNanos: 1,
          layout: us, context: context.gesture, origin: .physical, text: nil, isRepeat: false))
      } else {
        runtime.invalidateContext(reason: .mouseNavigation)
      }
      context.confirm(focusEpoch: 3)
      type("dtn ", runtime, context.token)
      XCTAssertEqual(delivered().last?.word.text, "dtn", "interruption \(interruption)")
    }
  }

  func testInputWithoutAnyApplicationContextIsNotRecovered() {
    let (context, runtime, delivered) = harness()
    runtime.missedInput(keyCode: 5, command: false)
    context.confirm(focusEpoch: 3)
    type("dtn ", runtime, context.token)
    let candidate = delivered().last
    XCTAssertEqual(candidate?.word.text, "dtn")
    XCTAssertEqual(candidate?.allowsOpaqueWordStart, false)
  }
}

private final class PendingContext: ContextAccess, GestureContextReading {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  var gesture = ContextToken(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
  var safe = true
  func confirm(focusEpoch: UInt64, pid: Int32 = 42, bundleID: String = "test") {
    token = .init(pid: pid, bundleID: bundleID, focusEpoch: focusEpoch, layoutEpoch: 1)
    safe = true
  }
  func current() -> ContextToken? { safe ? token : nil }
  func gestureContext() -> ContextToken? { safe ? token : gesture }
  func isSafe(_ token: ContextToken) -> Bool { safe && token == self.token }
}
