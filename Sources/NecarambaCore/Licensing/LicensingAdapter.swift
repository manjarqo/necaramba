public protocol LicensingAdapter {
    func current() async -> EntitlementState
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restore() async throws -> EntitlementState
}
public enum LicensingError: Error { case unavailable, unknownProduct, unverified }
