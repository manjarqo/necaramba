import Foundation

/// Main-thread fallback when an application does not expose AX focus notifications.
final class FocusRefreshPolling {
  typealias Schedule = (@escaping () -> Void) -> () -> Void
  private let schedule: Schedule
  private var cancel: (() -> Void)?
  private var generation: UInt64 = 0

  init(schedule: @escaping Schedule = { action in
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }) { self.schedule = schedule }

  deinit { cancel?() }

  func start(notificationsAvailable: Bool, refresh: @escaping () -> Void) {
    stop()
    refresh()
    guard !notificationsAvailable else { return }
    let expected = generation
    cancel = schedule { [weak self] in
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
