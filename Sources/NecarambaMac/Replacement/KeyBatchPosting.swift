import NecarambaCore

/// Safety/deadline checks happen between complete down/up pairs.
/// An already-posted down always gets its release, even on context loss.
public enum KeyBatchPosting {
  public static func postPairs<Event>(_ events: [Event], isSafe: () -> Bool, post: (Event) -> Void)
    -> ApplyResult
  {
    guard !events.isEmpty, events.count <= 512, events.count % 2 == 0 else { return .aborted }
    var index = 0
    while index < events.count {
      guard isSafe() else { return index == 0 ? .aborted : .uncertain }
      post(events[index])
      post(events[index + 1])
      index += 2
    }
    return .committed
  }
  public enum StopReason: Int, Sendable {
    case completed = 0, invalidBatch, ownershipExpired, generationChanged, contextChanged, secureInput
  }
  public struct Report: Sendable {
    public let result: ApplyResult
    public let postedPairs: Int
    public let elapsedNanos: UInt64
    public let reason: StopReason
  }
  /// Uses the existing ownership lease; never starts a fresh deadline here.
  /// Safety is checked before each pair and releases always follow their downs.
  public static func postGuardedPairs<Event>(_ events: [Event],
    now: () -> UInt64, ownershipValid: (UInt64) -> Bool,
    generationValid: () -> Bool, contextValid: () -> Bool,
    secureInput: () -> Bool, post: (Event) -> Void) -> Report {
    let began = now()
    var pairs = 0
    var reason: StopReason = .completed
    func finish(_ result: ApplyResult) -> Report {
      let ended = now()
      return .init(result: result, postedPairs: pairs,
        elapsedNanos: ended >= began ? ended - began : 0, reason: reason)
    }
    guard !events.isEmpty, events.count <= 512, events.count % 2 == 0 else {
      reason = .invalidBatch
      return finish(.aborted)
    }
    while pairs * 2 < events.count {
      let time = now()
      if time < began || !ownershipValid(time) { reason = .ownershipExpired }
      else if !generationValid() { reason = .generationChanged }
      else if secureInput() { reason = .secureInput }
      else if !contextValid() { reason = .contextChanged }
      if reason != .completed { return finish(pairs == 0 ? .aborted : .uncertain) }
      post(events[pairs * 2])
      post(events[pairs * 2 + 1])
      pairs += 1
    }
    return finish(.committed)
  }

}
