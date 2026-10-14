import Foundation
public enum EntitlementPolicy {
    public static func allowsPaidFeatures(state: EntitlementState, now: Date) -> Bool {
        switch state {
        case .active(let until, _): return until.map { now < $0 } ?? true
        case .trial(let until), .grace(let until): return now < until
        case .checking, .pending, .expired, .revoked, .unavailable: return false
        }
    }
    public static func offline(lastVerified: Date, expires: Date, now: Date) -> EntitlementState {
        guard now >= lastVerified else { return .unavailable }
        let until = min(expires, lastVerified.addingTimeInterval(72 * 3600))
        return now < until ? .grace(until: until) : .expired
    }
}
