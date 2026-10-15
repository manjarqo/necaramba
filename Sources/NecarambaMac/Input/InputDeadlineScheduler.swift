import Foundation

/// Executor-confined one-shot scheduler. Stale callbacks cannot fire after cancellation.
final class InputDeadlineScheduler {
  typealias Schedule = (UInt64, @escaping () -> Void) -> () -> Void
  private let schedule: Schedule
  private var deadline: UInt64?
  private var cancel: (() -> Void)?
  private var generation: UInt64 = 0
  init(schedule: @escaping Schedule) { self.schedule = schedule }
  deinit { cancel?() }
  func update(deadline next: UInt64?, action: @escaping () -> Void) {
    guard next != deadline else { return }
    generation &+= 1
    cancel?()
    cancel = nil
    deadline = next
    guard let next else { return }
    let expected = generation
    cancel = schedule(next) { [weak self] in
      guard let self, self.generation == expected, self.deadline == next else { return }
      self.generation &+= 1
      self.deadline = nil
      self.cancel = nil
      action()
    }
  }
}
