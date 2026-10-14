import NecarambaCore
import XCTest
@testable import NecarambaMac

final class ManualWordTrackingTests: XCTestCase {
  private let layout = LayoutID(rawValue: "US")
  private func fixture() -> (ContextState, InputRuntime) {
    let context = ContextState()
    context.update(pid: 42, bundleID: "editor", focusID: "field", layout: layout, qualified: true)
    return (context, InputRuntime(context: context, initialLayout: layout))
  }
  private func type(_ text: String, into runtime: InputRuntime, context: ContextState,
                    origin: EventOrigin = .physical) {
    for (index, char) in text.enumerated() {
      _ = runtime.accept(.init(kind: .down, keyCode: 0, modifiers: [],
        timestampNanos: UInt64(index), layout: layout, context: context.current()!,
        origin: origin, text: String(char), isRepeat: false))
    }
  }
  func testManualWordIncludesRussianPhysicalPunctuation() {
    let (context, runtime) = fixture()
    type("[jhjij", into: runtime, context: context)
    XCTAssertEqual(runtime.manualWord()?.text, "[jhjij")
  }
  func testFirstWordAfterRuleInstallRemainsAvailableWithTrailingSpace() {
    let (context, runtime) = fixture()
    runtime.install(.init(modelVersion: 2))
    type("ghbdtn ", into: runtime, context: context)
    XCTAssertEqual(runtime.manualWord()?.text, "ghbdtn")
    XCTAssertEqual(runtime.manualWord()?.delimiter, " ")
  }
  func testSubmissionAndTabClearManualWord() {
    for boundary in ["\n", "\r", "\t"] {
      let (context, runtime) = fixture()
      type("ghbdtn" + boundary, into: runtime, context: context)
      XCTAssertNil(runtime.manualWord(), "manual correction after submission/navigation")
    }
  }
  func testPlainPasteShortcutClearsPreviousPhysicalWordEvenWhenPassedThrough() {
    let (context, runtime) = fixture()
    type("ghbdtn", into: runtime, context: context)
    _ = runtime.accept(.init(kind: .down, keyCode: 9, modifiers: [.command, .shift],
      timestampNanos: 10, layout: layout, context: context.current()!, origin: .physical,
      text: "V", isRepeat: false))
    XCTAssertNil(runtime.manualWord())
  }
  func testForeignInputCannotLeavePhysicalSuffixEligible() {
    let (context, runtime) = fixture()
    type("ghbdtn", into: runtime, context: context)
    type("x", into: runtime, context: context, origin: .foreignSynthetic)
    XCTAssertNil(runtime.manualWord())
  }
  func testPermissionOrFocusLossCannotLeavePhysicalSuffixEligible() {
    let (context, runtime) = fixture()
    type("ghbdtn", into: runtime, context: context)
    let old = context.current()!
    context.invalidate(.focusChanged)
    _ = runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [.shift],
      timestampNanos: 10, layout: layout, context: old, origin: .physical,
      text: nil, isRepeat: false))
    XCTAssertNil(runtime.manualWord())
  }
  func testPreferenceUpdateClearsPhysicalSuffix() {
    let (context, runtime) = fixture()
    type("ghbdtn", into: runtime, context: context)
    runtime.updatePreferences(.defaults)
    XCTAssertNil(runtime.manualWord())
  }
}
