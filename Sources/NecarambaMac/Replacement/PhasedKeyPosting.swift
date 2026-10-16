import NecarambaCore

/// Serialized asynchronous phases. The scheduler must resume on the ownership executor.
/// No editor mutation is retried, including a partially delivered key batch.
enum PhasedKeyPosting {
  static func run<Event>(deletion: [Event], insertion: [Event],
    schedule: @escaping (Double, @escaping () -> Void) -> Void,
    authorized: @escaping () -> Bool,
    post: @escaping ([Event]) -> ApplyResult, finish: @escaping (ApplyResult) -> Void) {
    schedule(0.025) {
      guard authorized() else { finish(.aborted); return }
      let deleted = deletion.isEmpty ? ApplyResult.committed : post(deletion)
      guard deleted == .committed else { finish(deleted); return }
      schedule(0.025) {
        guard authorized() else { finish(deletion.isEmpty ? .aborted : .uncertain); return }
        let inserted = post(insertion)
        finish(inserted == .aborted && !deletion.isEmpty ? .uncertain : inserted)
      }
    }
  }
}
