import XCTest
import NecarambaCore
@testable import NecarambaMac
final class ReplacementTests: XCTestCase {
 let token = ContextToken(pid:42,bundleID:"test",focusEpoch:1,layoutEpoch:1)
 func testStaleContextNeverWrites() {
  let context = ContextState(); let sender = Sender()
  let coordinator = ReplacementCoordinator(context:context,layouts:Layouts(),sender:sender)
  XCTAssertEqual(coordinator.apply(EditPlan(expected:token,original:"ghbdtn",replacement:"привет",sourceLayout:LayoutID(rawValue:"US"),targetLayout:LayoutID(rawValue:"RU"),delimiter:" ")), .aborted)
  XCTAssertEqual(sender.calls,0)
 }
 func testUncertainNeverCreatesUndo() {
  let context = ContextState(); context.update(pid:42,bundleID:"test",focusID:"field",layout:LayoutID(rawValue:"US"),qualified:true)
  let sender = Sender(); sender.result = .uncertain
  let coordinator = ReplacementCoordinator(context:context,layouts:Layouts(),sender:sender)
  let plan = EditPlan(expected:context.current()!,original:"g",replacement:"п",sourceLayout:LayoutID(rawValue:"US"),targetLayout:LayoutID(rawValue:"RU"),delimiter:"")
  XCTAssertEqual(coordinator.apply(plan),.uncertain); XCTAssertEqual(coordinator.undoLast(),.aborted); XCTAssertEqual(sender.calls,1)
 }
}
private final class Sender: KeySending { var calls=0; var result:ApplyResult = .committed; func replaceVerifiedSuffix(_ plan:EditPlan)->ApplyResult { calls += 1; return result } }
private final class Layouts: LayoutAccess { var id=LayoutID(rawValue:"US"); func current()->LayoutID? { id }; func supported()->[LayoutID] { [id,LayoutID(rawValue:"RU")] }; func select(_ id:LayoutID)->Bool { self.id=id; return true } }
