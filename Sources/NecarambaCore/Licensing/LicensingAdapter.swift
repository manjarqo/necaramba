/// Sequence numbers are local to one adapter instance and order a snapshot against its updates.
public struct EntitlementRevision: Sendable {
    public let state: EntitlementState
    public let sequence: UInt64
    public init(state: EntitlementState, sequence: UInt64) { self.state = state; self.sequence = sequence }
}
public protocol LicensingAdapter {
    func current() async -> EntitlementState
    func snapshot() async -> EntitlementRevision
    /// Verified changes ordered with snapshot(). The consumer owns the stream lifetime.
    func updates() async -> AsyncStream<EntitlementRevision>
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restore() async throws -> EntitlementState
}
public enum LicensingError: Error { case unavailable, unknownProduct, unverified }
