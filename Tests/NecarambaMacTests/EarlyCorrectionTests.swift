import NecarambaCore
import XCTest

@testable import NecarambaMac

final class EarlyCorrectionTests: XCTestCase {
  func testTypingContinuesAfterVerifiedRewrite() {
    let context = ContextState()
    let us = LayoutID(rawValue: "US")
    let ru = LayoutID(rawValue: "RU")
    context.update(pid: 42, bundleID: "test", focusID: "a", layout: us, qualified: true)
    let mapping = LayoutMapping(
      source: us, target: ru, pairs: ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т"])
    let snapshot = RuleSnapshot(
      modelVersion: 1, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)],
      mappings: [mapping])
    let done = expectation(description: "early correction")
    var editor = ""
    let runtime = InputRuntime(
      context: context, initialLayout: us, snapshot: snapshot, earlyEnabled: true,
      command: { command in
        guard case .boundary(let word, let snapshot, let prefs) = command else { return }
        guard
          case .replace(let correction) = LinguisticEngine(snapshot: snapshot).decide(
            word: word, preferences: prefs, excludedWords: [])
        else { return }
        XCTAssertEqual(word.delimiter, "")
        XCTAssertTrue(editor.hasSuffix(word.text))
        editor.removeLast(word.text.count)
        editor += correction.replacement
        done.fulfill()
      })
    for (n, pair) in zip([5, 4, 11, 2, 17, 45], Array("ghbdtn")).enumerated() {
      let event = InputEvent(
        kind: .down, keyCode: UInt16(pair.0), modifiers: [], timestampNanos: UInt64(n), layout: us,
        context: context.current()!, origin: .physical, text: String(pair.1), isRepeat: false)
      if runtime.accept(event) == .pass { editor += String(pair.1) }
    }
    wait(for: [done], timeout: 1)
    let punctuation = InputEvent(
      kind: .down, keyCode: 18, modifiers: [.shift], timestampNanos: 10, layout: us,
      context: context.current()!, origin: .physical, text: "!", isRepeat: false)
    if runtime.accept(punctuation) == .pass { editor += "!" }
    XCTAssertEqual(editor, "привет!")
  }
}
