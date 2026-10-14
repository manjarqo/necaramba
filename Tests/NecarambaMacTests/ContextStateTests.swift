import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ContextStateTests: XCTestCase {
  func testDuplicateFocusNotificationKeepsSameFieldTokenValid() throws {
    let state = ContextState()
    publish(state, focus: "field")
    let before = try XCTUnwrap(state.current())
    state.reconcileFocus { self.publish(state, focus: "field"); return state.current() }
    XCTAssertEqual(state.current(), before)
    XCTAssertTrue(state.isSafe(before))
  }
  func testChangedAndReturnedFocusNeverRevivesOldToken() throws {
    let state = ContextState()
    publish(state, focus: "first")
    let before = try XCTUnwrap(state.current())
    state.reconcileFocus { self.publish(state, focus: "second"); return state.current() }
    XCTAssertFalse(state.isSafe(before))
    state.reconcileFocus { self.publish(state, focus: "first"); return state.current() }
    XCTAssertFalse(state.isSafe(before))
  }
  func testMissingOrSecureFocusInvalidatesPreviouslyUsableContext() throws {
    for missing in [false, true] {
      let state = ContextState()
      publish(state, focus: "field")
      let before = try XCTUnwrap(state.current())
      state.reconcileFocus {
        if !missing { self.publish(state, focus: "field", qualified: false) }
        return nil
      }
      XCTAssertNil(state.current())
      XCTAssertNil(state.gestureContext())
      XCTAssertFalse(state.isSafe(before))
    }
  }
  private func publish(_ state: ContextState, focus: String, qualified: Bool = true) {
    state.update(pid: 42, bundleID: "test", focusID: focus, layout: .init(rawValue: "US"), qualified: qualified)
  }
}
