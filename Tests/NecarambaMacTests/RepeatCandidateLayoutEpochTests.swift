import XCTest
import NecarambaCore
@testable import NecarambaMac

/// Our own layout selection republishes the field with a new layout epoch after an
/// automatic edit; double Shift must still find the retained word in that field.
final class RepeatCandidateLayoutEpochTests: XCTestCase {
  func testRetainedWordSurvivesLayoutEpochButNotFocusChange() {
    let context = EpochContext()
    let runtime = InputRuntime(context: context, initialLayout: .init(rawValue: "US"),
      snapshot: .init(modelVersion: 1), conservativeAutomaticEnabled: true, command: { _ in })
    let token = context.token
    let original = BufferedWord(text: "ghbdtn", events: [], context: token, layout: .init(rawValue: "US"), delimiter: " ")
    let candidate = ManualRepeatCandidate(original: original, currentText: "привет", context: token,
      layout: .init(rawValue: "RU"), delimiter: " ", fieldIdentity: UUID(), alternateText: nil)
    XCTAssertTrue(runtime.retainManualResult(candidate, expectedGeneration: runtime.inputGeneration()))
    context.token = .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 2)
    let found = runtime.manualRepeatCandidate()
    XCTAssertEqual(found?.currentText, "привет")
    XCTAssertEqual(found?.context, context.token, "The candidate is rebased into the republished field")
    context.token = .init(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 2)
    XCTAssertNil(runtime.manualRepeatCandidate(), "Another field never inherits the word")
  }
}

private final class EpochContext: ContextAccess {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
}
