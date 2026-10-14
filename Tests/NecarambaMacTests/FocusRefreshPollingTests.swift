import XCTest
@testable import NecarambaMac

final class FocusRefreshPollingTests: XCTestCase {
  func testUnsupportedNotificationsRefreshImmediatelyAndPollUntilStopped() {
    var tick: (() -> Void)?
    var cancelled = 0
    var refreshed = 0
    let polling = FocusRefreshPolling { action in
      tick = action
      return { cancelled += 1 }
    }
    polling.start(notificationsAvailable: false) { refreshed += 1 }
    XCTAssertEqual(refreshed, 1)
    XCTAssertNotNil(tick)
    tick?()
    XCTAssertEqual(refreshed, 2)
    polling.stop()
    XCTAssertEqual(cancelled, 1)
    tick?()
    XCTAssertEqual(refreshed, 2)
  }
  func testReattachCancelsOldPollAndSupportedObserverDoesNotPoll() {
    var oldTick: (() -> Void)?
    var scheduled = 0
    var cancelled = 0
    var oldRefreshes = 0
    var newRefreshes = 0
    let polling = FocusRefreshPolling { action in
      scheduled += 1
      oldTick = action
      return { cancelled += 1 }
    }
    polling.start(notificationsAvailable: false) { oldRefreshes += 1 }
    polling.start(notificationsAvailable: true) { newRefreshes += 1 }
    oldTick?()
    XCTAssertEqual(oldRefreshes, 1)
    XCTAssertEqual(newRefreshes, 1)
    XCTAssertEqual(scheduled, 1)
    XCTAssertEqual(cancelled, 1)
  }
}
