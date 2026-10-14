import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ApplicationServicesTests: XCTestCase {
    func testCommandsPersistConfirmedStateAndRejectUnknownPreferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let app = try ApplicationServices(directory: directory, defaults: defaults,
            permissions: PermissionFake(), loginBackend: LoginFake(), onPreferences: { _ in })
        _ = try await app.execute("addWord", arguments: ["text": "превет"])
        XCTAssertEqual((app.snapshot()["words"] as? [[String:Any]])?.first?["original"] as? String, "превет")
        _ = try await app.execute("setPreferences", arguments: ["patch": ["autoEnabled": false]])
        XCTAssertFalse(app.preferences.snapshot.autoEnabled)
        do { _ = try await app.execute("setPreferences", arguments: ["patch": ["recordTypedText": true]]); XCTFail() } catch {}
        XCTAssertFalse(app.preferences.snapshot.autoEnabled)
        let reopened = try ApplicationServices(directory: directory, defaults: defaults,
            permissions: PermissionFake(), loginBackend: LoginFake(), onPreferences: { _ in })
        XCTAssertEqual((reopened.snapshot()["words"] as? [[String:Any]])?.count, 1)
        XCTAssertFalse(reopened.preferences.snapshot.autoEnabled)
    }
    func testCancelledClearDoesNotDeleteRules() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString; let defaults=UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain); try? FileManager.default.removeItem(at:dir) }
        let app=try ApplicationServices(directory:dir,defaults:defaults,permissions:PermissionFake(),loginBackend:LoginFake(),onPreferences:{ _ in })
        _ = try await app.execute("addWord",arguments:["text":"пример"])
        do { _ = try await app.execute("clearWords",arguments:["confirmed":false]); XCTFail() } catch {}
        XCTAssertEqual(try app.rules.words().count,1)
    }
}
private final class PermissionFake: PermissionReading {
    func current() -> PermissionState { .init(listen:false,post:false,ax:false,secureInput:false) }
    func request(_ kind:PermissionKind) {}
}
private struct LoginFake: LoginBackend {
    func status()->LoginStatus { .disabled }
    func setEnabled(_ value:Bool) throws {}
}
