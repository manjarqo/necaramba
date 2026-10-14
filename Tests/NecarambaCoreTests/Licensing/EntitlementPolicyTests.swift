import XCTest
@testable import NecarambaCore
final class EntitlementPolicyTests: XCTestCase {
    func testGraceExpiresAtBoundary() {
        let d = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(EntitlementPolicy.allowsPaidFeatures(state: .grace(until: d), now: d.addingTimeInterval(-1)))
        XCTAssertFalse(EntitlementPolicy.allowsPaidFeatures(state: .grace(until: d), now: d))
        XCTAssertFalse(EntitlementPolicy.allowsPaidFeatures(state: .pending, now: d))
    }
}
extension EntitlementPolicyTests {
    func testExpiryAndOfflineNeverExtendSignedExpiration() {
        let checked = Date(timeIntervalSince1970: 10_000)
        let expiry = checked.addingTimeInterval(60)
        XCTAssertEqual(EntitlementPolicy.offline(lastVerified: checked, expires: expiry, now: checked), .grace(until: expiry))
        XCTAssertEqual(EntitlementPolicy.offline(lastVerified: checked, expires: expiry, now: expiry), .expired)
        XCTAssertEqual(EntitlementPolicy.offline(lastVerified: checked, expires: expiry, now: checked.addingTimeInterval(-1)), .unavailable)
        for state: EntitlementState in [.checking, .pending, .expired, .revoked, .unavailable, .active(until: checked, renews: true), .trial(until: checked)] { XCTAssertFalse(EntitlementPolicy.allowsPaidFeatures(state: state, now: checked)) }
        XCTAssertTrue(EntitlementPolicy.allowsPaidFeatures(state: .active(until: nil, renews: false), now: checked))
    }
}
