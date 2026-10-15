import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ContextStateTests: XCTestCase {
  func testDuplicateFocusNotificationKeepsSameFieldTokenValid() throws {
    let state = ContextState()
    publish(state, focus: "field")
    let before = try XCTUnwrap(state.current())
    state.reconcileFocus { self.publish(state, focus: "field"); return state.publishedCurrent() }
    XCTAssertEqual(state.current(), before)
    XCTAssertTrue(state.isSafe(before))
  }
  func testReconciliationHidesCachedEvidenceUntilSameFieldConfirmed() throws {
    let state = ContextState()
    publish(state, focus: "field")
    let before = try XCTUnwrap(state.current())
    state.reconcileFocus {
      XCTAssertNil(state.current())
      XCTAssertNil(state.gestureContext())
      XCTAssertFalse(state.isSafe(before))
      self.publish(state, focus: "field")
      return before
    }
    XCTAssertEqual(state.current(), before)
  }
  func testChangedAndReturnedFocusNeverRevivesOldToken() throws {
    let state = ContextState()
    publish(state, focus: "first")
    let before = try XCTUnwrap(state.current())
    state.reconcileFocus { self.publish(state, focus: "second"); return state.publishedCurrent() }
    XCTAssertFalse(state.isSafe(before))
    state.reconcileFocus { self.publish(state, focus: "first"); return state.publishedCurrent() }
    XCTAssertFalse(state.isSafe(before))
  }
  func testRepeatedNoneditableFocusKeepsGestureEpochStable() throws {
    let state = ContextState()
    publish(state, focus: "noneditable", qualified: false)
    let before = try XCTUnwrap(state.gestureContext())
    for _ in 0..<3 {
      state.reconcileFocus {
        self.publish(state, focus: "noneditable", qualified: false)
        return nil
      }
      XCTAssertEqual(state.gestureContext(), before)
      XCTAssertNil(state.current())
    }
    publish(state, focus: "other", qualified: false)
    XCTAssertNotEqual(state.gestureContext(), before)
    publish(state, focus: "noneditable", qualified: false)
    XCTAssertNotEqual(state.gestureContext(), before)
  }
  func testKnownNoneditableFocusPreservesLayoutGestureContext() {
    let state = ContextState()
    state.reconcileFocus {
      self.publish(state, focus: "noneditable", qualified: false)
      return nil
    }
    XCTAssertNil(state.current())
    XCTAssertNotNil(state.gestureContext())
  }
  func testMissingOrSecureFocusInvalidatesPreviouslyUsableContext() throws {
    for missing in [false, true] {
      let state = ContextState()
      publish(state, focus: "field")
      let before = try XCTUnwrap(state.current())
      state.reconcileFocus {
        if !missing { self.publish(state, focus: "field", qualified: false) }
        state.invalidate(.focusChanged)
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

extension ContextStateTests {
  func testCaptureInvalidationCountsOncePerReconciliationWithoutPublishingStaleToken() {
    let state = ContextState()
    state.update(pid: 1, bundleID: "test", focusID: "a", layout: .init(rawValue: "RU"), qualified: true)
    let old = state.current()!
    state.reconcileFocus {
      XCTAssertNil(state.current())
      XCTAssertNil(state.gestureContext())
      XCTAssertFalse(state.isSafe(old))
      return nil
    }
    XCTAssertEqual(state.reconciliationCaptureInvalidations, 1)
    state.reconcileFocus { XCTAssertNil(state.gestureContext()); return nil }
    XCTAssertEqual(state.reconciliationCaptureInvalidations, 2)
  }
}
