import XCTest
@testable import NecarambaMac

final class ChromiumAccessibilityActivationTests: XCTestCase {
  func testChromeActivatesThenRefreshesAfterDebounce() {
    var delay: TimeInterval?
    var tick: (() -> Void)?
    var activated = 0
    var refreshed = 0
    let activation = ChromiumAccessibilityActivation { seconds, action in
      delay = seconds; tick = action; return {}
    }
    activation.start(bundleID: "com.google.Chrome", activate: { activated += 1; return true }) { refreshed += 1 }
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(refreshed, 0)
    XCTAssertGreaterThan(delay ?? 0, 2)
    tick?()
    XCTAssertEqual(refreshed, 1)
  }
  func testDetachCancelsRefreshAndNeverDisablesSharedAccessibility() {
    var tick: (() -> Void)?
    var cancelled = 0
    var activated = 0
    var refreshed = 0
    let activation = ChromiumAccessibilityActivation { _, action in
      tick = action; return { cancelled += 1 }
    }
    activation.start(bundleID: "com.google.Chrome", activate: { activated += 1; return true }) { refreshed += 1 }
    activation.stop()
    tick?()
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(cancelled, 1)
    XCTAssertEqual(refreshed, 0)
  }
  func testOtherApplicationsAndFailedActivationDoNotScheduleRetry() {
    var scheduled = 0
    var activated = 0
    let activation = ChromiumAccessibilityActivation { _, _ in scheduled += 1; return {} }
    activation.start(bundleID: "com.apple.Safari", activate: { activated += 1; return true }, refresh: {})
    XCTAssertEqual(activated, 0)
    activation.start(bundleID: "com.google.Chrome", activate: { activated += 1; return false }, refresh: {})
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(scheduled, 0)
  }
}
