public protocol LicensingAdapter {
    func current() async -> EntitlementState
    /// Verified changes after the current snapshot. The consumer owns the stream lifetime.
    func updates() async -> AsyncStream<EntitlementState>
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restore() async throws -> EntitlementState
}
public enum LicensingError: Error { case unavailable, unknownProduct, unverified }
