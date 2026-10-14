import XCTest
import NecarambaCore
@testable import NecarambaMac
final class StoreKitLicensingAdapterTests: XCTestCase {
    func testMissingCommercialConfigurationIsUnavailable() async throws {
        let sut = StoreKitLicensingAdapter(productIDs: [], bundleID: "")
        let current = await sut.current(); XCTAssertEqual(current, .unavailable)
        do { _ = try await sut.purchase(productID: "other"); XCTFail() } catch {}
    }
    func testOfflineCacheReverifiesAndBoundsGrace() async throws {
        let checked = Date(timeIntervalSince1970: 1000)
        let cache = VerifiedEntitlementCache(storage: MemoryEntitlementMaterialStore(), verify: { material in
            guard material == "signed-fixture" else { return nil }
            return .init(productID: "test.local", expires: checked.addingTimeInterval(1_000_000), revoked: false)
        })
        try await cache.save(material: "signed-fixture", checkedAt: checked)
        let state = await cache.load(now: checked.addingTimeInterval(1))
        XCTAssertEqual(state, .grace(until: checked.addingTimeInterval(72 * 3600)))
        let rollback = await cache.load(now: checked.addingTimeInterval(-1)); XCTAssertEqual(rollback, .unavailable)
        let expired = await cache.load(now: checked.addingTimeInterval(72 * 3600)); XCTAssertEqual(expired, .expired)
    }
}
private final class MemoryEntitlementMaterialStore: EntitlementMaterialStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}
extension StoreKitLicensingAdapterTests {
    func testReplayingIdenticalSignedMaterialCannotExtendGrace() async throws {
        let checked = Date(timeIntervalSince1970: 1000)
        let cache = VerifiedEntitlementCache(storage: MemoryEntitlementMaterialStore(), verify: { _ in .init(productID: "test.local", expires: checked.addingTimeInterval(1_000_000), revoked: false) })
        try await cache.save(material: "same-signed-transaction", checkedAt: checked)
        try await cache.save(material: "same-signed-transaction", checkedAt: checked.addingTimeInterval(72 * 3600))
        let state = await cache.load(now: checked.addingTimeInterval(72 * 3600))
        XCTAssertEqual(state, .expired)
    }
    func testClockRollbackAfterObservedExpiryDoesNotRestoreGrace() async throws {
        let checked = Date(timeIntervalSince1970: 1000)
        let storage = MemoryEntitlementMaterialStore()
        let verifier: (String) async -> CachedEntitlementVerification? = { _ in
            .init(productID: "test.local", expires: checked.addingTimeInterval(1_000_000), revoked: false)
        }
        let cache = VerifiedEntitlementCache(storage: storage, verify: verifier)
        try await cache.save(material: "signed", checkedAt: checked)
        let expired = await cache.load(now: checked.addingTimeInterval(72 * 3600))
        XCTAssertEqual(expired, .expired)
        let restarted = VerifiedEntitlementCache(storage: storage, verify: verifier)
        let rolledBack = await restarted.load(now: checked.addingTimeInterval(100))
        XCTAssertEqual(rolledBack, .unavailable)
    }
}
