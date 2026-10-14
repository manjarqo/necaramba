import Foundation
public enum EntitlementState: Equatable, Sendable {
    case checking, trial(until: Date), active(until: Date?, renews: Bool)
    case grace(until: Date), pending, expired, revoked, unavailable
}
public enum PurchaseOutcome: Equatable, Sendable { case entitled(EntitlementState), cancelled, pending }
