import Foundation

/// Chrome debounces AXEnhancedUserInterface activation for two seconds.
/// https://chromium.googlesource.com/chromium/src/+/master/chrome/browser/chrome_browser_application_mac.mm
final class ChromiumAccessibilityActivation {
  typealias Schedule = (TimeInterval, @escaping () -> Void) -> () -> Void
  private let schedule: Schedule
  private var cancel: (() -> Void)?
  private var generation: UInt64 = 0

  init(schedule: @escaping Schedule = { delay, action in
    let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }) { self.schedule = schedule }
  deinit { cancel?() }

  static func attribute(for bundleID: String) -> String? {
    // Electron documents this attribute for third-party assistive tools.
    // https://www.electronjs.org/docs/latest/tutorial/accessibility
    if bundleID == "com.readdle.SparkDesktop" { return "AXManualAccessibility" }
    // Zen's Gecko engine may expose browser chrome without page accessibility.
    // https://bugzilla.mozilla.org/show_bug.cgi?id=1664992
    if bundleID == "app.zen-browser.zen" { return "AXEnhancedUserInterface" }
    if ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"].contains(bundleID) {
      return "AXEnhancedUserInterface"
    }
    return nil
  }
  static func supports(_ bundleID: String) -> Bool { attribute(for: bundleID) != nil }
  func start(bundleID: String, activate: () -> Bool, refresh: @escaping () -> Void) {
    stop()
    guard Self.supports(bundleID), activate() else { return }
    let expected = generation
    cancel = schedule(2.2) { [weak self] in
      guard let self, self.generation == expected else { return }
      refresh()
    }
  }
  func stop() {
    generation &+= 1
    cancel?()
    cancel = nil
  }
}
