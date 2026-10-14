/// The composition root must explicitly select a development/free policy. No commercial entitlement is inferred.
public struct LocalEntitlementProvider: LicensingAdapter, Sendable {
    private let state: EntitlementState
    public init(_ state: EntitlementState) { self.state = state }
    public func current() async -> EntitlementState { state }
    public func snapshot() async -> EntitlementRevision { .init(state: state, sequence: 0) }
    public func updates() async -> AsyncStream<EntitlementRevision> { AsyncStream { $0.finish() } }
    public func purchase(productID: String) async throws -> PurchaseOutcome { throw LicensingError.unavailable }
    public func restore() async throws -> EntitlementState { state }
}
