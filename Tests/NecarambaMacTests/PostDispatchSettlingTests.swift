import XCTest
import NecarambaCore
@testable import NecarambaMac

/// After posting, our own layout selection may republish the same field with a new
/// layout epoch, or briefly hide it. The edit stays dispatched in that same field.
@MainActor final class PostDispatchSettlingTests: XCTestCase {
  private let us = LayoutID(rawValue: "US")
  private let ru = LayoutID(rawValue: "RU")

  private func word(_ token: ContextToken) -> (BufferedWord, InputEvent) {
    let events = "ghbdtn".map { InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
      layout: us, context: token, origin: .physical, text: String($0), isRepeat: false) }
    let boundary = InputEvent(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: us, context: token, origin: .physical, text: " ", isRepeat: false)
    return (.init(text: "ghbdtn", events: events, context: token, layout: us, delimiter: " "), boundary)
  }

  private func republish(_ context: ContextState, hiddenFor reads: Int) -> () -> Void {
    {
      // The field disappears for a moment, then returns with the target layout.
      context.update(pid: 42, bundleID: "test", focusID: "field", layout: self.us, qualified: false)
      var remaining = reads
      DispatchQueue.main.async {
        func step() {
          if remaining == 0 {
            context.update(pid: 42, bundleID: "test", focusID: "field", layout: self.ru, qualified: true)
          } else { remaining -= 1; DispatchQueue.main.async(execute: step) }
        }
        step()
      }
    }
  }

  func testEmptyProxyStaysDispatchedWhenTheSameFieldReturnsWithNewLayoutEpoch() async {
    let context = ContextState()
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: us, qualified: true)
    let token = context.current()!
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: SettlingEmptyReader(),
      allowAutomaticBoundary: { true })
    adapter.inputGeneration = { 1 }
    let hide = republish(context, hiddenFor: 2)
    adapter.executeAsync = { _, _, _, valid in
      guard valid() else { return .aborted }
      hide()
      return .committed
    }
    let (captured, boundary) = word(token)
    let result = await adapter.replaceAutomaticBoundaryAsync(.init(word: captured, boundary: boundary,
      inputGeneration: 1), with: "привет ")
    XCTAssertEqual(result, .dispatched)
  }

  func testOpaqueTerminalStaysDispatchedWhenTheSameFieldReturnsWithNewLayoutEpoch() async {
    let context = ContextState()
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: us, qualified: true)
    let token = context.current()!
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: SettlingOpaqueReader(),
      allowAutomaticBoundary: { true })
    adapter.inputGeneration = { 1 }
    let hide = republish(context, hiddenFor: 2)
    adapter.executePhysicalAsync = { _, _, valid in
      guard valid() else { return .aborted }
      hide()
      return .committed
    }
    let (captured, boundary) = word(token)
    let result = await adapter.replaceAutomaticBoundaryAsync(.init(word: captured, boundary: boundary,
      inputGeneration: 1), with: "привет ")
    XCTAssertEqual(result, .dispatched)
  }

  func testDifferentFieldAfterPostingRemainsUncertain() async {
    let context = ContextState()
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: us, qualified: true)
    let token = context.current()!
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: SettlingEmptyReader(),
      allowAutomaticBoundary: { true })
    adapter.inputGeneration = { 1 }
    adapter.executeAsync = { _, _, _, valid in
      guard valid() else { return .aborted }
      context.update(pid: 42, bundleID: "test", focusID: "other", layout: self.ru, qualified: true)
      return .committed
    }
    let (captured, boundary) = word(token)
    let result = await adapter.replaceAutomaticBoundaryAsync(.init(word: captured, boundary: boundary,
      inputGeneration: 1), with: "привет ")
    XCTAssertEqual(result, .uncertain)
  }
}

private final class SettlingEmptyReader: AXSelectionReading {
  let identity = UUID()
  func read(in token: ContextToken) -> AXTextSnapshot? {
    .init(identity: identity, value: "", range: NSRange(location: 0, length: 0))
  }
}
private final class SettlingOpaqueReader: AXSelectionReading {
  let identity = UUID()
  func read(in token: ContextToken) -> AXTextSnapshot? { nil }
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    .opaque(.init(context: token, identity: identity))
  }
}
