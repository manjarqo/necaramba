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
    func testLoginPersistenceFailureRestoresSystemStatus() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: dir) }
        let login = MutableLoginFake()
        var writes = 0
        let app = try ApplicationServices(directory:dir, defaults:defaults, permissions:PermissionFake(), loginBackend:login,
            onPreferences:{ _ in }, preferencesWrite: { _ in writes += 1; if writes > 1 { throw TestFailure.persistence } })
        do { _ = try await app.execute("setLoginEnabled", arguments:["enabled":true]); XCTFail() } catch {}
        XCTAssertEqual(login.actions, [true, false])
        XCTAssertEqual(login.status(), .disabled)
        XCTAssertFalse(app.preferences.settings.loginPreferred)
        XCTAssertEqual((app.snapshot()["login"] as? [String:Any])?["status"] as? String, "disabled")
    }
    func testLoginRollbackFailurePublishesActualStatus() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: dir) }
        let login = MutableLoginFake(); login.failDisable = true
        var writes = 0
        let app = try ApplicationServices(directory:dir, defaults:defaults, permissions:PermissionFake(), loginBackend:login,
            onPreferences:{ _ in }, preferencesWrite: { _ in writes += 1; if writes > 1 { throw TestFailure.persistence } })
        var publications = 0; app.onChanged = { publications += 1 }
        do { _ = try await app.execute("setLoginEnabled", arguments:["enabled":true]); XCTFail() }
        catch let failure as NativeCommandFailure { XCTAssertEqual(failure.code, "partialFailure") }
        XCTAssertEqual(login.status(), .enabled)
        XCTAssertFalse(app.preferences.settings.loginPreferred)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual((app.snapshot()["login"] as? [String:Any])?["status"] as? String, "enabled")
    }
    func testDelayedArchiveImportPreservesOriginalDataAfterNativeChange() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archiveURL = dir.appendingPathComponent("import.json")
        let archive = ApplicationArchiveV1(rules: RuleArchiveV1(words:[], apps:[]),
                                           preferences:StoredPreferencesV1(selectedColor:7))
        try JSONEncoder().encode(archive).write(to:archiveURL)
        var selected:CheckedContinuation<URL?,Never>?
        let app = try ApplicationServices(directory:dir, defaults:defaults, permissions:PermissionFake(), loginBackend:LoginFake(),
            onPreferences:{ _ in }, chooseFile:{ _ in await withCheckedContinuation { selected = $0 } })
        _ = try await app.execute("addWord", arguments:["text":"пример"])
        let bridge = NativeCommandCoordinator(snapshot:{ app.snapshot() }, execute:{ method, arguments in
            try await app.execute(method, arguments:arguments)
        })
        let envelope:[String:Any] = ["requestID":"import", "expectedSessionID":bridge.sessionID,
                                     "expectedRevision":0, "arguments":[String:Any]()]
        let pending = Task { try await bridge.command("importArchive", envelope:envelope) }
        while selected == nil { await Task.yield() }
        bridge.publishChange()
        selected?.resume(returning:archiveURL)
        do { _ = try await pending.value; XCTFail("stale archive committed") }
        catch let failure as NativeCommandFailure { XCTAssertEqual(failure.code, "conflict") }
        XCTAssertEqual(try app.rules.words().map(\.original), ["пример"])
        XCTAssertEqual(app.preferences.settings.selectedColor, 0)
    }
}
private enum TestFailure:Error { case persistence }
private final class MutableLoginFake:LoginBackend {
    var value:LoginStatus = .disabled
    var actions:[Bool] = []
    var failDisable = false
    func status()->LoginStatus { value }
    func setEnabled(_ enabled:Bool) throws {
        actions.append(enabled)
        if !enabled && failDisable { throw TestFailure.persistence }
        value = enabled ? .enabled : .disabled
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
