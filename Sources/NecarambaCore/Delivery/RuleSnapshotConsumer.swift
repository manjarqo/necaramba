public protocol RuleSnapshotConsumer: AnyObject {
    /// Enqueues the immutable snapshot; the runtime reports its version after the transaction boundary.
    func install(_ snapshot: RuleSnapshot)
}
