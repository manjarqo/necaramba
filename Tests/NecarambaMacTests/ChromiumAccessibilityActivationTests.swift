import XCTest
@testable import NecarambaMac

final class ChromiumAccessibilityActivationTests: XCTestCase {
  func testZenStableActivatesPageAccessibilityAndRefreshesAfterActivation() {
    var tick: (() -> Void)?
    var activated = 0
    var refreshed = 0
    let activation = ChromiumAccessibilityActivation { _, action in
      tick = action; return {}
    }
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "app.zen-browser.zen"), "AXEnhancedUserInterface")
    activation.start(bundleID: "app.zen-browser.zen", activate: {
      activated += 1; return true
    }) { refreshed += 1 }
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(refreshed, 0)
    tick?()
    XCTAssertEqual(refreshed, 1)
  }
  func testZenActivationIsRestrictedToExactStableBundle() {
    var activated = 0
    var scheduled = 0
    let activation = ChromiumAccessibilityActivation { _, _ in scheduled += 1; return {} }
    for bundle in ["app.zen-browser.zen.beta", "app.zen-browser.zen-helper", "other.app.zen-browser.zen"] {
      activation.start(bundleID: bundle, activate: { activated += 1; return true }, refresh: {})
      XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: bundle))
    }
    XCTAssertEqual(activated, 0)
    XCTAssertEqual(scheduled, 0)
  }
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
  func testSparkActivatesAndRefreshesItsElectronAccessibilityTree() {
    var tick: (() -> Void)?
    var activated = 0
    var refreshed = 0
    let activation = ChromiumAccessibilityActivation { _, action in
      tick = action; return {}
    }
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.readdle.SparkDesktop"), "AXManualAccessibility")
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.google.Chrome"), "AXEnhancedUserInterface")
    XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: "com.apple.Safari"))
    activation.start(bundleID: "com.readdle.SparkDesktop", activate: {
      activated += 1; return true
    }) { refreshed += 1 }
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(refreshed, 0)
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
