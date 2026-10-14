import XCTest
import NecarambaCore
@testable import NecarambaMac
final class RuleSlotStoreTests: XCTestCase {
    func testCorruptCurrentFallsBackToVerifiedPreviousAndKeepsHighWater() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures(); let store = RuleSlotStore(root: root, verifier: f.verifier)
        _ = try store.promote(f.package(version: 1)); _ = try store.promote(f.package(version: 2))
        try Data("broken".utf8).write(to: root.appendingPathComponent("generations/2/payload.json"))
        XCTAssertEqual(try store.load(bundled: f.package(version: 0)).modelVersion, 1)
        XCTAssertThrowsError(try store.promote(f.package(version: 1)))
        XCTAssertEqual(try RuleSlotStore(root: root, verifier: f.verifier).load(bundled: f.package(version: 0)).modelVersion, 1)
    }
    func testSameVersionConflictingDigestIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures(); let store = RuleSlotStore(root: root, verifier: f.verifier)
        let p = try f.package(version: 1); _ = try store.promote(p)
        XCTAssertEqual(try store.promote(p).modelVersion, 1)
        XCTAssertThrowsError(try store.promote(f.package(version: 1, protectedToken: "different")))
    }
}
private final class FailingRuleDurability: RuleDurability {
    let failAt: Int
    var calls = 0
    let real = POSIXRuleDurability()
    init(_ failAt: Int) { self.failAt = failAt }
    func step() throws { calls += 1; if calls == failAt { throw RuleStorageError.ioFailure } }
    func write(_ data: Data, to url: URL) throws { try step(); try real.write(data, to: url) }
    func rename(_ source: URL, to destination: URL) throws { try step(); try real.rename(source, to: destination) }
    func syncDirectory(_ url: URL) throws { try step(); try real.syncDirectory(url) }
}
extension RuleSlotStoreTests {
    func testDurabilityFaultsKeepWholeOldOrNewStateAfterRestart() throws {
        for fault in 1...9 {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let f = RuleFixtures(); let p1 = try f.package(version: 1); let p2 = try f.package(version: 2)
            _ = try RuleSlotStore(root: root, verifier: f.verifier).promote(p1)
            let io = FailingRuleDurability(fault)
            XCTAssertThrowsError(try RuleSlotStore(root: root, verifier: f.verifier, durability: io).promote(p2))
            let restarted = RuleSlotStore(root: root, verifier: f.verifier)
            let version = try restarted.load(bundled: f.package(version: 0)).modelVersion
            XCTAssertTrue([1, 2].contains(version), "fault \(fault)")
            if version == 2 { XCTAssertThrowsError(try restarted.promote(p1)) }
        }
    }
    func testStartupCleansOnlyUnreferencedGenerations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures(); let store = RuleSlotStore(root: root, verifier: f.verifier)
        _ = try store.promote(f.package(version: 1)); _ = try store.promote(f.package(version: 2)); _ = try store.promote(f.package(version: 3))
        _ = try store.load(bundled: f.package(version: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("generations/1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("generations/2").path))
    }
}
extension RuleSlotStoreTests {
    func testBundledVersionBecomesRemoteFloorBeforeFirstInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures(); let store = RuleSlotStore(root: root, verifier: f.verifier)
        XCTAssertEqual(try store.load(bundled: f.package(version: 3)).modelVersion, 3)
        XCTAssertThrowsError(try store.promote(f.package(version: 2)))
    }
    func testBundledVersionRemainsRemoteFloorWhenInstalledSlotLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures()
        _ = try RuleSlotStore(root: root, verifier: f.verifier).promote(f.package(version: 1))
        let restarted = RuleSlotStore(root: root, verifier: f.verifier)
        XCTAssertEqual(try restarted.load(bundled: f.package(version: 3)).modelVersion, 1)
        XCTAssertThrowsError(try restarted.promote(f.package(version: 2))) {
            XCTAssertEqual($0 as? RuleVerificationError, .downgrade)
        }
    }
    func testMissingStateWithInstalledGenerationBlocksRemotePromotion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures()
        _ = try RuleSlotStore(root: root, verifier: f.verifier).promote(f.package(version: 3))
        try FileManager.default.removeItem(at: root.appendingPathComponent("state.json"))
        let restarted = RuleSlotStore(root: root, verifier: f.verifier)
        XCTAssertEqual(try restarted.load(bundled: f.package(version: 0)).modelVersion, 0)
        XCTAssertThrowsError(try restarted.promote(f.package(version: 1)))
    }
    func testMalformedStateFallsBackToBundledButBlocksRemotePromotion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures()
        _ = try RuleSlotStore(root: root, verifier: f.verifier).promote(f.package(version: 3))
        try Data("broken".utf8).write(to: root.appendingPathComponent("state.json"))
        let restarted = RuleSlotStore(root: root, verifier: f.verifier)
        XCTAssertEqual(try restarted.load(bundled: f.package(version: 0)).modelVersion, 0)
        XCTAssertThrowsError(try restarted.promote(f.package(version: 4)))
    }
}
