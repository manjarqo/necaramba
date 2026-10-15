import XCTest
@testable import NecarambaMac

final class FocusRefreshPollingTests: XCTestCase {
  func testHealthyObserverDoesNotScheduleAnIdleTimer() {
    var scheduled = 0
    let polling = FocusRefreshPolling { _ in scheduled += 1; return {} }
    polling.start(notificationsAvailable: true) {}
    XCTAssertEqual(scheduled, 0)
  }
  func testTransientFailureAndLaterInvalidationRecoverWithoutAnotherNotification() {
    var ticks: [() -> Void] = []
    var pending = true
    var attempts = 0
    let polling = FocusRefreshPolling { action in ticks.append(action); return {} }
    polling.start(notificationsAvailable: true, needsRecovery: { pending }) {
      attempts += 1
      pending = attempts == 1
    }
    XCTAssertEqual(ticks.count, 1)
    ticks.removeFirst()()
    XCTAssertEqual(attempts, 2)
    XCTAssertTrue(ticks.isEmpty)
    pending = true
    polling.updateRecovery()
    XCTAssertEqual(ticks.count, 1)
    ticks.removeFirst()()
    XCTAssertEqual(attempts, 3)
    XCTAssertTrue(ticks.isEmpty)
  }
  func testBlockedPermissionKeepsRecoveryObligationUntilPermissionReturns() {
    var ticks: [() -> Void] = []
    var blocked = true
    var pending = true
    var reads = 0
    let polling = FocusRefreshPolling { action in ticks.append(action); return {} }
    polling.start(notificationsAvailable: true, needsRecovery: { pending }) {
      guard !blocked else { return }
      reads += 1
      pending = false
    }
    for _ in 0..<4 { ticks.removeFirst()() }
    XCTAssertEqual(reads, 0)
    XCTAssertEqual(ticks.count, 1)
    blocked = false
    ticks.removeFirst()()
    XCTAssertEqual(reads, 1)
    XCTAssertTrue(ticks.isEmpty)
  }
  func testMissingObserverPollsAndReattachRejectsStaleCallback() {
    var ticks: [() -> Void] = []
    var cancelled = 0
    var oldReads = 0
    var newReads = 0
    let polling = FocusRefreshPolling { action in
      ticks.append(action)
      return { cancelled += 1 }
    }
    polling.start(notificationsAvailable: false) { oldReads += 1 }
    ticks.removeFirst()()
    XCTAssertEqual(oldReads, 2)
    let stale = ticks.removeFirst()
    polling.start(notificationsAvailable: true) { newReads += 1 }
    stale()
    XCTAssertEqual(oldReads, 2)
    XCTAssertEqual(newReads, 1)
    XCTAssertEqual(cancelled, 1)
    XCTAssertTrue(ticks.isEmpty)
  }
  func testStopCancelsRecoveryAndRejectsAlreadyDeliveredCallback() {
    var tick: (() -> Void)?
    var reads = 0
    let polling = FocusRefreshPolling { action in tick = action; return {} }
    polling.start(notificationsAvailable: false) { reads += 1 }
    polling.stop()
    tick?()
    XCTAssertEqual(reads, 1)
  }
}
