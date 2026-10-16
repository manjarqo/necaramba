import XCTest
import NecarambaCore
@testable import NecarambaMac

final class PostingAdmissionTests: XCTestCase {
  private let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 3, layoutEpoch: 7)

  func testOnlyAuthoritativeReconciliationOfMissingTokenIsRetried() {
    func decide(cached: ContextToken?, reconciling: Bool, elapsed: UInt64 = 5_000_000,
                cancelled: Bool = false, secure: Bool = false) -> EventTapAdapter.PostingAdmission {
      EventTapAdapter.admission(cancelled: cancelled, elapsedNanos: elapsed, secureInput: secure,
        cached: cached, expected: token, reconciling: reconciling)
    }
    XCTAssertEqual(decide(cached: token, reconciling: false), .admit)
    XCTAssertEqual(decide(cached: nil, reconciling: true), .retry)
    XCTAssertEqual(decide(cached: nil, reconciling: false), .reject(10), "An invalidated token is never retried")
    let changed = ContextToken(pid: 42, bundleID: "test", focusEpoch: 4, layoutEpoch: 7)
    XCTAssertEqual(decide(cached: changed, reconciling: true), .reject(10), "A different published token is final")
    XCTAssertEqual(decide(cached: nil, reconciling: true, elapsed: 100_000_000), .reject(8))
    XCTAssertEqual(decide(cached: nil, reconciling: true, cancelled: true), .reject(7))
    XCTAssertEqual(decide(cached: token, reconciling: false, secure: true), .reject(9))
  }

  func testContextStateReportsReconciliationOnlyWhileHidingSafety() {
    let state = ContextState()
    state.update(pid: 42, bundleID: "test", focusID: "field", layout: .init(rawValue: "US"), qualified: true)
    XCTAssertFalse(state.isReconciling)
    var observed: (Bool, ContextToken?)?
    state.reconcileFocus {
      observed = (state.isReconciling, state.current())
      return state.publishedCurrent()
    }
    XCTAssertEqual(observed?.0, true)
    XCTAssertNil(observed?.1)
    XCTAssertFalse(state.isReconciling)
    XCTAssertNotNil(state.current())
  }

  func testRuntimeExposesReconciliationOfItsContextState() {
    let state = ContextState()
    let runtime = InputRuntime(context: state, initialLayout: .init(rawValue: "US"), command: { _ in })
    XCTAssertFalse(runtime.contextReconciling())
    var inside = false
    state.reconcileFocus { inside = runtime.contextReconciling(); return nil }
    XCTAssertTrue(inside)
  }
}
