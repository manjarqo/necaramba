import XCTest
import NecarambaCore
@testable import NecarambaMac
private final class SnapshotSpy: RuleSnapshotConsumer {
    var versions: [UInt64] = []
    func install(_ snapshot: RuleSnapshot) { versions.append(snapshot.modelVersion) }
}
private struct OfflineDownloader: RulePackageDownloading {
    func fetch(from: URL) async throws -> RulePackage { throw URLError(.notConnectedToInternet) }
}
final class RuleUpdateCoordinatorTests: XCTestCase {
    func testOfflineStartupInstallsLocalSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let f = RuleFixtures(); let consumer = SnapshotSpy()
        let coordinator = RuleUpdateCoordinator(store: .init(root: root, verifier: f.verifier), bundled: try f.package(version: 0), consumer: consumer, downloader: OfflineDownloader(), endpoint: URL(string: "https://test.invalid/rules"))
        await coordinator.start(); XCTAssertEqual(consumer.versions, [0]); await coordinator.stop()
    }
    func testInvalidTransportEndpointCannotFetch() async throws {
        let downloader = RuleDownloader(allowedHost: "test.invalid")
        do { _ = try await downloader.fetch(from: URL(string: "http://test.invalid")!); XCTFail() }
        catch { XCTAssertEqual(error as? RuleDownloadError, .invalidEndpoint) }
    }
}
