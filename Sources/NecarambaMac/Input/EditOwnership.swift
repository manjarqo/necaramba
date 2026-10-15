import Foundation
import NecarambaCore

/// Confined to the tap executor. Preparation must not mutate the editor.
/// The destructive closure may only post an already-built, bounded event batch.
public final class EditOwnership<Event> {
  public enum Disposition {
    case pass, held
    case replay([Event])
  }
  private let capacity: Int
  private let deadlineNanos: UInt64
  private var began: UInt64?
  private var queued: [Event] = []
  public init(capacity: Int = 16, deadlineNanos: UInt64 = 100_000_000) {
    self.capacity = max(1, capacity)
    self.deadlineNanos = deadlineNanos
  }
  public var isActive: Bool { began != nil }
  public var nextDeadlineNanos: UInt64? {
    guard let began else { return nil }
    let (deadline, overflow) = began.addingReportingOverflow(deadlineNanos)
    return overflow ? UInt64.max : deadline
  }
  public func expired(at now: UInt64) -> Bool {
    guard let began else { return false }
    return now < began || now - began >= deadlineNanos
  }
  public func begin(now: UInt64) -> Bool {
    guard began == nil else { return false }
    began = now
    return true
  }
  public func intercept(_ event: Event, now: UInt64) -> Disposition {
    guard let began else { return .pass }
    guard now >= began, now - began < deadlineNanos, queued.count < capacity else {
      let release = cancel() + [event]
      return .replay(release)
    }
    queued.append(event)
    return .held
  }
  public func cancel() -> [Event] {
    began = nil
    let release = queued
    queued.removeAll(keepingCapacity: true)
    return release
  }
  public func commit(
    expectedGeneration: UInt64, currentGeneration: () -> UInt64, now: UInt64,
    mutation: () -> ApplyResult
  ) -> (result: ApplyResult, replay: [Event]) {
    guard let began, now >= began, now - began < deadlineNanos,
      currentGeneration() == expectedGeneration
    else {
      return (.aborted, cancel())
    }
    // No AX, tasks, waits, or reentrant run loop are allowed inside mutation.
    let result = mutation()
    return (result, cancel())
  }
}
extension EditOwnership.Disposition: Equatable where Event: Equatable {}
