import XCTest
import NecarambaCore
@testable import NecarambaMac

final class SparkBoundaryDeliveryTests: XCTestCase {
  func testSparkBoundaryWaitsForEditorToConsumeSpace() {
    let done = expectation(description: "settled boundary")
    var count = 0
    let (runtime, token) = fixture { _ in count += 1; done.fulfill() }
    feedWord(runtime, token)
    let nextTurn = expectation(description: "next main turn")
    DispatchQueue.main.async {
      XCTAssertEqual(count, 0, "AX must not read before Electron consumes Space")
      nextTurn.fulfill()
    }
    wait(for: [nextTurn, done], timeout: 1)
    XCTAssertEqual(count, 1)
  }

  func testNewInputDuringSparkSettlingCancelsOldCorrection() {
    var count = 0
    let (runtime, token) = fixture { _ in count += 1 }
    feedWord(runtime, token)
    let done = expectation(description: "cancelled boundary drained")
    DispatchQueue.main.async {
      self.feed(runtime, token, "g", 5)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done.fulfill() }
    wait(for: [done], timeout: 1)
    XCTAssertEqual(count, 0)
  }

  private func fixture(command: @escaping (RuntimeCommand) -> Void) -> (InputRuntime, ContextToken) {
    let context = ContextState()
    context.update(pid: 42, bundleID: "com.readdle.SparkDesktop", focusID: "editor",
      layout: .init(rawValue: "US"), qualified: true)
    let runtime = InputRuntime(context: context, initialLayout: .init(rawValue: "US"),
      snapshot: .init(modelVersion: 1, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)]),
      conservativeAutomaticEnabled: true, command: command)
    return (runtime, context.current()!)
  }
  private func feedWord(_ runtime: InputRuntime, _ token: ContextToken) {
    for (letter, key) in zip(Array("ghbdtn "), [5, 4, 11, 2, 17, 45, 49]) {
      feed(runtime, token, String(letter), UInt16(key))
    }
  }
  private func feed(_ runtime: InputRuntime, _ token: ContextToken, _ text: String, _ key: UInt16) {
    runtime.accept(.init(kind: .down, keyCode: key, modifiers: [], timestampNanos: 1,
      layout: .init(rawValue: "US"), context: token, origin: .physical, text: text, isRepeat: false))
  }
}
