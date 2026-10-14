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
}
