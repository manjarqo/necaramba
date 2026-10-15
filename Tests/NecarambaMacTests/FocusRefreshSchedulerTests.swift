import XCTest
import NecarambaCore
@testable import NecarambaMac

final class FocusRefreshSchedulerTests: XCTestCase {
  func testBurstInvalidatesImmediatelyAndCoalescesReads() {
    var queued: [() -> Void] = []
    let scheduler = FocusRefreshScheduler(enqueue: { queued.append($0) }, scheduleRecovery: { _ in
      XCTFail("Healthy observer must have no timer"); return {}
    })
    let state = ContextState()
    state.update(pid: 1, bundleID: "test", focusID: "a", layout: .init(rawValue: "RU"), qualified: true)
    let old = state.current()!
    var reads = 0
    scheduler.start(notificationsAvailable: true, needsRecovery: { false }) { reads += 1 }
    for _ in 0..<100 {
      scheduler.requestRefresh { state.invalidate(.focusChanged) }
      XCTAssertFalse(state.isSafe(old))
    }
    XCTAssertEqual(reads, 0)
    XCTAssertEqual(queued.count, 1)
    queued.removeFirst()()
    XCTAssertEqual(reads, 1)
  }
  func testStopAndNewProcessDiscardQueuedReads() {
    var queued: [() -> Void] = []
    let scheduler = FocusRefreshScheduler(enqueue: { queued.append($0) }, scheduleRecovery: { _ in return {} })
    var oldReads = 0
    var newReads = 0
    scheduler.start(notificationsAvailable: true, needsRecovery: { false }) { oldReads += 1 }
    scheduler.stop()
    scheduler.start(notificationsAvailable: true, needsRecovery: { false }) { newReads += 1 }
    queued.forEach { $0() }
    XCTAssertEqual(oldReads, 0)
    XCTAssertEqual(newReads, 1)
  }
}

extension FocusRefreshSchedulerTests {
  func testOverlayUsesSingleRecoveryTimerAndDismissalReturnsToIdle() {
    var queued: [() -> Void] = []
    var ticks: [() -> Void] = []
    var overlay = true
    var reads = 0
    let scheduler = FocusRefreshScheduler(enqueue: { queued.append($0) }, scheduleRecovery: { action in
      ticks.append(action); return {}
    })
    scheduler.start(notificationsAvailable: true, needsRecovery: { overlay }) { reads += 1 }
    queued.removeFirst()()
    XCTAssertEqual(ticks.count, 1)
    ticks.removeFirst()()
    XCTAssertEqual(queued.count, 1)
    XCTAssertEqual(ticks.count, 1)
    overlay = false
    queued.removeFirst()()
    let cancelled = ticks.removeFirst()
    cancelled()
    XCTAssertTrue(queued.isEmpty)
    XCTAssertTrue(ticks.isEmpty)
    XCTAssertEqual(reads, 2)
  }
}
