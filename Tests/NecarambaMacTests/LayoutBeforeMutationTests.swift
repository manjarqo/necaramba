import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class LayoutBeforeMutationTests: XCTestCase {
  func testTargetLayoutIsVerifiedAndPlanRebasedBeforeMutation() async {
    let context = BeforeContext()
    let layouts = BeforeLayouts(context)
    let sender = BeforeSender(layouts: layouts, context: context)
    let coordinator = ReplacementCoordinator(context: context, layouts: layouts, sender: sender)
    let original = context.token
    let result = await coordinator.applyAsync(plan(original))
    XCTAssertEqual(result, .committed)
    XCTAssertEqual(sender.observedLayout, .init(rawValue: "RU"))
    XCTAssertNotEqual(sender.observedToken, original)
    XCTAssertEqual(sender.observedToken, context.token)
  }
  func testFailedLayoutVerificationDoesNotMutateText() async {
    let context = BeforeContext()
    let layouts = BeforeLayouts(context); layouts.accept = false
    let sender = BeforeSender(layouts: layouts, context: context)
    let coordinator = ReplacementCoordinator(context: context, layouts: layouts, sender: sender)
    let result = await coordinator.applyAsync(plan(context.token))
    XCTAssertEqual(result, .aborted)
    XCTAssertEqual(sender.calls, 0)
  }
  func testFocusChangeDuringLayoutSelectionDoesNotMutateText() async {
    let context = BeforeContext()
    let layouts = BeforeLayouts(context); layouts.changeFocus = true
    let sender = BeforeSender(layouts: layouts, context: context)
    let coordinator = ReplacementCoordinator(context: context, layouts: layouts, sender: sender)
    let result = await coordinator.applyAsync(plan(context.token))
    XCTAssertEqual(result, .aborted)
    XCTAssertEqual(sender.calls, 0)
  }
  func testNewInputDuringTargetActivationCannotAuthorizeOldWord() async {
    let context = BeforeContext()
    let layouts = BeforeLayouts(context)
    let sender = BeforeSender(layouts: layouts, context: context)
    let coordinator = ReplacementCoordinator(context: context, layouts: layouts, sender: sender)
    var generation: UInt64 = 10
    coordinator.inputGeneration = { generation }
    coordinator.selectLayout = { target, _, _ in
      _ = layouts.select(target)
      generation += 1
      return true
    }
    let result = await coordinator.applyAsync(plan(context.token))
    XCTAssertEqual(result, .aborted)
    XCTAssertEqual(sender.calls, 0)
  }
  private func plan(_ token: ContextToken) -> EditPlan {
    .init(expected: token, original: "ghbdtn", replacement: "привет", sourceLayout: .init(rawValue: "US"), targetLayout: .init(rawValue: "RU"), delimiter: "")
  }
}
private final class BeforeContext: ContextRefreshing {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func refresh() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
}
private final class BeforeLayouts: LayoutAccess {
  let context: BeforeContext
  var value = LayoutID(rawValue: "US")
  var accept = true
  var changeFocus = false
  init(_ context: BeforeContext) { self.context = context }
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool {
    guard accept else { return false }
    value = id
    context.token = .init(pid: 42, bundleID: "test", focusEpoch: changeFocus ? 2 : 1, layoutEpoch: 2)
    return true
  }
}
private final class BeforeSender: KeySending {
  let layouts: BeforeLayouts
  let context: BeforeContext
  var calls = 0
  var observedLayout: LayoutID?
  var observedToken: ContextToken?
  init(layouts: BeforeLayouts, context: BeforeContext) { self.layouts = layouts; self.context = context }
  func replaceVerifiedSuffix(_ plan: EditPlan) -> ApplyResult {
    calls += 1; observedLayout = layouts.current(); observedToken = plan.expected
    return context.isSafe(plan.expected) ? .committed : .aborted
  }
}
