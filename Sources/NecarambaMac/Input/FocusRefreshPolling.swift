import Foundation

/// Main-thread one-shot recovery. Call updateRecovery after each authoritative read
/// or invalidation: a healthy observer has no periodic idle wakeups.
final class FocusRefreshPolling {
  typealias Schedule = (@escaping () -> Void) -> () -> Void
  private let schedule: Schedule
  private var cancel: (() -> Void)?
  private var generation: UInt64 = 0
  private var notificationsAvailable = true
  private var needsRecovery: () -> Bool = { false }
  private var refresh: (() -> Void)?

  init(schedule: @escaping Schedule = { action in
    let timer = Timer(timeInterval: 0.25, repeats: false) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }) { self.schedule = schedule }

  deinit { cancel?() }

  func start(notificationsAvailable: Bool, needsRecovery: @escaping () -> Bool = { false },
             refresh: @escaping () -> Void) {
    stop()
    self.notificationsAvailable = notificationsAvailable
    self.needsRecovery = needsRecovery
    self.refresh = refresh
    refresh()
    updateRecovery()
  }

  func updateRecovery() {
    guard refresh != nil else { return }
    guard !notificationsAvailable || needsRecovery() else {
      cancel?()
      cancel = nil
      generation &+= 1
      return
    }
    guard cancel == nil else { return }
    let expected = generation
    cancel = schedule { [weak self] in
      guard let self, self.generation == expected else { return }
      self.cancel = nil
      // Invalidate this particular callback even if cancellation was delivered late.
      self.generation &+= 1
      self.refresh?()
      self.updateRecovery()
    }
  }

  func stop() {
    generation &+= 1
    cancel?()
    cancel = nil
    refresh = nil
    needsRecovery = { false }
  }
}
