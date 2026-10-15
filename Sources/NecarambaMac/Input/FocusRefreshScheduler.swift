import Foundation

/// Main-run-loop owner of coalesced reads and the single recovery/overlay timer.
/// Invalidation runs synchronously; only the expensive authoritative read is deferred.
final class FocusRefreshScheduler {
  typealias Enqueue = (@escaping () -> Void) -> Void
  private let enqueue: Enqueue
  private let polling: FocusRefreshPolling
  private var generation: UInt64 = 0
  private var pending = false
  private var refresh: (() -> Void)?

  init(enqueue: @escaping Enqueue = { action in
    RunLoop.main.perform(inModes: [.common], block: action)
  }, scheduleRecovery: @escaping FocusRefreshPolling.Schedule = { action in
    let timer = Timer(timeInterval: 0.25, repeats: false) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return { timer.invalidate() }
  }) {
    self.enqueue = enqueue
    polling = FocusRefreshPolling(schedule: scheduleRecovery)
  }

  func start(notificationsAvailable: Bool, needsRecovery: @escaping () -> Bool,
             refresh: @escaping () -> Void) {
    stop()
    self.refresh = refresh
    polling.start(notificationsAvailable: notificationsAvailable, needsRecovery: needsRecovery) { [weak self] in
      self?.requestRefresh()
    }
  }

  func requestRefresh(invalidate: () -> Void = {}) {
    invalidate()
    guard refresh != nil, !pending else { return }
    pending = true
    let expected = generation
    enqueue { [weak self] in
      guard let self, self.generation == expected else { return }
      self.pending = false
      self.refresh?()
      self.polling.updateRecovery()
    }
  }

  func updateRecovery() { polling.updateRecovery() }

  func stop() {
    generation &+= 1
    pending = false
    refresh = nil
    polling.stop()
  }
}
