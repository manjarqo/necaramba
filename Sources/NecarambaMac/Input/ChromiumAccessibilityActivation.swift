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

  static func supports(_ bundleID: String) -> Bool {
    ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"].contains(bundleID)
  }
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
