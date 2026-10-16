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
    // Electron documents AXManualAccessibility for third-party assistive tools; Chrome
    // and Gecko need AXEnhancedUserInterface. Applications come from verified profiles.
    // https://www.electronjs.org/docs/latest/tutorial/accessibility
    switch ApplicationProfileRegistry.shared.profile(for: bundleID)?.accessibilityActivation {
    case .manual: return "AXManualAccessibility"
    case .enhanced: return "AXEnhancedUserInterface"
    case nil: return nil
    }
  }
  static func supports(_ bundleID: String) -> Bool { attribute(for: bundleID) != nil }
  func start(bundleID: String, activate: @escaping () -> Bool, refresh: @escaping () -> Void) {
    stop()
    guard Self.supports(bundleID) else { return }
    let expected = generation
    attempt(remaining: 3, expected: expected, activate: activate, refresh: refresh)
  }
  private func attempt(remaining: Int, expected: UInt64,
                       activate: @escaping () -> Bool, refresh: @escaping () -> Void) {
    guard generation == expected else { return }
    let succeeded = activate()
    guard generation == expected else { return }
    if succeeded {
      cancel = schedule(2.2) { [weak self] in
        guard let self, self.generation == expected else { return }
        self.cancel = nil
        refresh()
      }
    } else if remaining > 1 {
      // Electron may time out while constructing its first accessibility tree.
      // Retry away from the input callback, bounded to this activation epoch.
      cancel = schedule(0.5) { [weak self] in
        guard let self, self.generation == expected else { return }
        self.cancel = nil
        self.attempt(remaining: remaining - 1, expected: expected,
          activate: activate, refresh: refresh)
      }
    }
  }
  func stop() {
    generation &+= 1
    cancel?()
    cancel = nil
  }
}
