import XCTest
@testable import NecarambaMac

final class ChromiumAccessibilityActivationTests: XCTestCase {
  func testTabbyRequestsElectronAccessibilityWithoutMatchingHelpers() {
    var attempts = 0
    let activation = ChromiumAccessibilityActivation { _, _ in {} }
    activation.start(bundleID: "org.tabby", activate: { attempts += 1; return true }, refresh: {})
    XCTAssertEqual(attempts, 1)
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "org.tabby"), "AXManualAccessibility")
    XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: "org.tabby.helper"))
  }
  func testOrcaRequestsElectronAccessibilityWithoutMatchingHelpers() {
    var attempts = 0
    let activation = ChromiumAccessibilityActivation { _, _ in {} }
    activation.start(bundleID: "com.stablyai.orca", activate: { attempts += 1; return true }, refresh: {})
    XCTAssertEqual(attempts, 1)
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.stablyai.orca"), "AXManualAccessibility")
    for bundle in ["com.stablyai.orca.helper", "com.stablyai.orca.Renderer", "other.com.stablyai.orca"] {
      XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: bundle))
    }
  }
  func testVSCodiumRequestsElectronAccessibilityAndRefreshes() {
    var tick: (() -> Void)?
    var activated = 0
    var refreshed = 0
    let activation = ChromiumAccessibilityActivation { _, action in tick = action; return {} }
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.vscodium"), "AXManualAccessibility")
    activation.start(bundleID: "com.vscodium", activate: { activated += 1; return true }) { refreshed += 1 }
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(refreshed, 0)
    tick?()
    XCTAssertEqual(refreshed, 1)
  }

  func testVSCodiumActivationDoesNotIncludeHelpersOrUnqualifiedBundles() {
    for bundle in ["com.vscodium.helper", "com.vscodium.insiders", "other.com.vscodium"] {
      XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: bundle))
      let activation = ChromiumAccessibilityActivation { _, _ in XCTFail("Unexpected timer"); return {} }
      activation.start(bundleID: bundle, activate: { XCTFail("Unexpected activation"); return true }, refresh: {})
    }
  }

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
  func testOtherApplicationsDoNotActivateAndFailuresScheduleRecovery() {
    var scheduled = 0
    var activated = 0
    let activation = ChromiumAccessibilityActivation { _, _ in scheduled += 1; return {} }
    activation.start(bundleID: "com.apple.Safari", activate: { activated += 1; return true }, refresh: {})
    XCTAssertEqual(activated, 0)
    activation.start(bundleID: "com.google.Chrome", activate: { activated += 1; return false }, refresh: {})
    XCTAssertEqual(activated, 1)
    XCTAssertEqual(scheduled, 1)
  }
  func testActivationRecoversAfterTimeoutAndRefreshesOnlyAfterSuccess() {
    var pending: [() -> Void] = []
    var attempts = 0
    var refreshes = 0
    let activation = ChromiumAccessibilityActivation { _, action in pending.append(action); return {} }
    activation.start(bundleID: "com.vscodium", activate: {
      attempts += 1; return attempts == 2
    }, refresh: { refreshes += 1 })
    XCTAssertEqual(pending.count, 1)
    guard !pending.isEmpty else { return }
    pending.removeFirst()()
    XCTAssertEqual(attempts, 2)
    XCTAssertEqual(refreshes, 0)
    XCTAssertEqual(pending.count, 1)
    guard !pending.isEmpty else { return }
    pending.removeFirst()()
    XCTAssertEqual(refreshes, 1)
  }

  func testFailedActivationRetriesAreBoundedAndStopInvalidatesQueuedAttempt() {
    var pending: [() -> Void] = []
    var attempts = 0
    let activation = ChromiumAccessibilityActivation { _, action in pending.append(action); return {} }
    activation.start(bundleID: "com.vscodium", activate: { attempts += 1; return false },
      refresh: { XCTFail("No successful activation") })
    for _ in 0..<10 {
      guard !pending.isEmpty else { break }
      pending.removeFirst()()
    }
    XCTAssertEqual(attempts, 3)
    XCTAssertTrue(pending.isEmpty)
    activation.start(bundleID: "com.vscodium", activate: { attempts += 1; return false }, refresh: {})
    activation.stop()
    pending.forEach { $0() }
    XCTAssertEqual(attempts, 4)
  }

}
