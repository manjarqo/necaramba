import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ApplicationServicesTests: XCTestCase {
    func testAdditionalCorrectionsUnavailableByDefault() throws {
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let app = try ApplicationServices(rules: MemoryApplicationRules(),
            preferences: PreferencesController(defaults: defaults, publish: { _ in }),
            sound: MemorySound(), header: MemoryHeader(), statistics: MemoryStatistics(),
            login: LoginController(backend: LoginFake()), permissions: PermissionFake(),
            files: MemoryFiles(soundURL: URL(fileURLWithPath: "/virtual/chime.wav")),
            appSelection: MemoryAppSelection(), thumbnailer: MemoryThumbnailer())
        XCTAssertEqual((app.snapshot()["model"] as? [String: Any])?["additionalCorrectionsAvailable"] as? Bool, false)
        app.additionalCorrectionsAvailable = true
        app.modelState = "failed"
        XCTAssertEqual((app.snapshot()["model"] as? [String: Any])?["additionalCorrectionsAvailable"] as? Bool, true)
    }

    func testMissingAccessibilityRequiresPermissionEvenWhenListenAndPostAreGranted() throws {
        let permissions = PermissionFake()
        permissions.state = .init(listen: true, post: true, ax: false, secureInput: false)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let app = try ApplicationServices(rules: MemoryApplicationRules(),
            preferences: PreferencesController(defaults: defaults, publish: { _ in }),
            sound: MemorySound(), header: MemoryHeader(), statistics: MemoryStatistics(),
            login: LoginController(backend: LoginFake()), permissions: permissions,
            files: MemoryFiles(soundURL: URL(fileURLWithPath: "/virtual/chime.wav")),
            appSelection: MemoryAppSelection(), thumbnailer: MemoryThumbnailer())
        app.runtimeRunning = true; app.automaticReady = true
        XCTAssertEqual(app.snapshot()["status"] as? String, "permissionRequired")
    }

    func testExplicitCapabilityRefreshPublishesRefreshedRuntimeState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let permissions = PermissionFake()
        permissions.state = .init(listen: true, post: true, ax: true, secureInput: false)
        let app = try ApplicationServices(directory: directory, defaults: defaults,
            permissions: permissions, loginBackend: LoginFake(), onPreferences: { _ in })
        app.automaticReady = true
        app.onRefreshCapabilities = { app.runtimeRunning = true }
        _ = try await app.execute("refreshCapabilities", arguments: [:])
        XCTAssertEqual(app.snapshot()["status"] as? String, "active")
    }

    func testEnabledAutomaticReportsInitializationAndUnavailableInsteadOfOff() throws {
        let permissions = PermissionFake()
        permissions.state = .init(listen: true, post: true, ax: true, secureInput: false)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let app = try ApplicationServices(rules: MemoryApplicationRules(),
            preferences: PreferencesController(defaults: defaults, publish: { _ in }),
            sound: MemorySound(), header: MemoryHeader(), statistics: MemoryStatistics(),
            login: LoginController(backend: LoginFake()), permissions: permissions,
            files: MemoryFiles(soundURL: URL(fileURLWithPath: "/virtual/chime.wav")),
            appSelection: MemoryAppSelection(), thumbnailer: MemoryThumbnailer())
        app.runtimeRunning = true
        XCTAssertEqual(app.snapshot()["status"] as? String, "starting")
        app.modelState = "failed"
        XCTAssertEqual(app.snapshot()["status"] as? String, "unavailable")
        app.modelState = "current"; app.modelVersion = "1"
        XCTAssertEqual(app.snapshot()["status"] as? String, "unavailable")
        app.automaticReady = true
        XCTAssertEqual(app.snapshot()["status"] as? String, "active")
        app.modelState = "failed" // Failed update retains the already installed engine.
        XCTAssertEqual(app.snapshot()["status"] as? String, "active")
        app.runtimeIsRunning = { false }
        app.modelState = "current"
        XCTAssertEqual(app.snapshot()["status"] as? String, "starting")
        app.runtimeIsRunning = { true }
        try app.preferences.replace(.init(autoEnabled: false))
        XCTAssertEqual(app.snapshot()["status"] as? String, "off")
    }

    func testInjectedRulesAndSoundDriveCommandsWithoutDiskStores() async throws {
        let rules = MemoryApplicationRules()
        let sound = MemorySound()
        let app = try ApplicationServices(rules: rules,
            preferences: PreferencesController(defaults: UserDefaults(suiteName: UUID().uuidString)!, publish: { _ in }),
            sound: sound, header: MemoryHeader(), statistics: MemoryStatistics(),
            login: LoginController(backend: LoginFake()), permissions: PermissionFake(),
            files: MemoryFiles(soundURL: URL(fileURLWithPath: "/virtual/chime.wav")),
            appSelection: MemoryAppSelection(), thumbnailer: MemoryThumbnailer())
        _ = try await app.execute("addWord", arguments: ["text": "пример"])
        _ = try await app.execute("chooseSound", arguments: [:])
        XCTAssertEqual((app.snapshot()["words"] as? [[String: Any]])?.first?["original"] as? String, "пример")
        XCTAssertEqual(sound.customSoundURL?.path, "/virtual/chime.wav")
    }
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
    func testLayoutShortcutChoicePersistsAndRejectsAmbiguousPatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let app = try ApplicationServices(directory: directory, defaults: defaults,
            permissions: PermissionFake(), loginBackend: LoginFake(), onPreferences: { _ in })
        let keys = ["singleShiftEnabled", "altShiftEnabled", "controlShiftEnabled", "commandShiftEnabled"]
        for selected in keys + ["disabled"] {
            let patch = Dictionary(uniqueKeysWithValues: keys.map { ($0, $0 == selected) })
            _ = try await app.execute("setPreferences", arguments: ["patch": patch])
            try app.preferences.setAuto(false)
            let reopened = try ApplicationServices(directory: directory, defaults: defaults,
                permissions: PermissionFake(), loginBackend: LoginFake(), onPreferences: { _ in })
            let flags = try XCTUnwrap(reopened.snapshot()["preferences"] as? [String: Bool])
            for key in keys { XCTAssertEqual(flags[key], key == selected) }
        }
        _ = try await app.execute("setPreferences", arguments: ["patch": ["altShiftEnabled": true]])
        let before = app.preferences.snapshot
        do {
            _ = try await app.execute("setPreferences", arguments: ["patch": ["altShiftEnabled": true, "controlShiftEnabled": true]])
            XCTFail("Conflicting shortcuts must be rejected atomically")
        } catch {}
        XCTAssertEqual(app.preferences.snapshot, before)
        _ = try await app.execute("setPreferences", arguments: ["patch": ["singleShiftEnabled": true]])
        let flags = try XCTUnwrap(app.snapshot()["preferences"] as? [String: Bool])
        XCTAssertEqual(flags["singleShiftEnabled"], true)
        XCTAssertEqual(flags["altShiftEnabled"], false)
        XCTAssertEqual(flags["controlShiftEnabled"], false)
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
    func testUnknownLoginStatusAfterOSActionPublishesPartialFailure() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "test.necaramba." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: dir) }
        let login = MutableLoginFake(); login.statusUnavailable = true
        var writes = 0
        let app = try ApplicationServices(directory:dir, defaults:defaults, permissions:PermissionFake(), loginBackend:login,
            onPreferences:{ _ in }, preferencesWrite:{ _ in writes += 1; if writes > 1 { throw TestFailure.persistence } })
        var publications = 0; app.onChanged = { publications += 1 }
        do { _ = try await app.execute("setLoginEnabled", arguments:["enabled":true]); XCTFail() }
        catch let failure as NativeCommandFailure { XCTAssertEqual(failure.code,"partialFailure") }
        XCTAssertEqual(login.actions,[true])
        XCTAssertEqual(login.value,.enabled)
        XCTAssertEqual(login.status(),.unavailable)
        XCTAssertFalse(app.preferences.settings.loginPreferred)
        XCTAssertEqual(publications,1)
        XCTAssertEqual((app.snapshot()["login"] as? [String:Any])?["status"] as? String,"unavailable")
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
    var statusUnavailable = false
    var actions:[Bool] = []
    var failDisable = false
    func status()->LoginStatus { statusUnavailable ? .unavailable : value }
    func setEnabled(_ enabled:Bool) throws {
        actions.append(enabled)
        if !enabled && failDisable { throw TestFailure.persistence }
        value = enabled ? .enabled : .disabled
    }
}
private final class PermissionFake: PermissionReading {
    var state = PermissionState(listen:false,post:false,ax:false,secureInput:false)
    func current() -> PermissionState { state }
    func request(_ kind:PermissionKind) {}
}
private struct LoginFake: LoginBackend {
    func status()->LoginStatus { .disabled }
    func setEnabled(_ value:Bool) throws {}
}
private final class MemoryApplicationRules: ApplicationRuleStore {
    private var rows: [WordRule] = []
    func words() throws -> [WordRule] { rows }
    func legacyWords() throws -> [WordRule] { [] }
    func runtimeWordExclusions() throws -> Set<String> { Set(rows.map(\.normalized)) }
    func addWord(_ text: String, at: Int64) throws -> WordRule {
        let value = try RuleValidation.word(text)
        let row = WordRule(id: UUID(), normalized: value.normalized, original: value.original, createdAt: at, shareOptIn: false)
        rows.append(row); return row
    }
    func deleteWord(id: UUID) throws { rows.removeAll { $0.id == id } }
    func clearWords() throws { rows.removeAll() }
    func apps() throws -> [AppRule] { [] }
    func setApp(_ rule: AppRule) throws {}
    func deleteApp(bundleID: String) throws {}
    func exportArchive() throws -> Data { try JSONEncoder().encode(RuleArchiveV1(words: rows, apps: [])) }
    func importArchive(_ data: Data, preferences: Data?) throws { rows += try JSONDecoder().decode(RuleArchiveV1.self, from: data).words }
    func preferencesData() throws -> Data? { nil }
    func savePreferences(_ data: Data) throws {}
}
private final class MemorySound: ApplicationSound {
    var customSoundURL: URL?
    func importSound(from source: URL) throws -> URL { customSoundURL = source; return source }
    func reset() throws { customSoundURL = nil }
    func setEnabled(_ value: Bool) {}
    func playCorrection(committedID: UUID) {}
}
private final class MemoryHeader: ApplicationHeader {
    func importImage(data: Data) throws {}
    func loadImageData() throws -> Data? { nil }
    func remove() throws {}
}
private final class MemoryStatistics: ApplicationStatistics {
    var totals: [CounterKind: Int] { [:] }
    func recordCommitted(id: UUID, kind: CounterKind, day: String) throws {}
    func reset() throws {}
}
@MainActor private struct MemoryFiles: ApplicationFiles {
    let soundURL: URL
    func choose(_ kind: ApplicationFileKind) async -> URL? { soundURL }
    func read(_ url: URL, maximumBytes: Int) throws -> Data { Data() }
    func save(_ data: Data, name: String) async throws {}
}
private struct MemoryAppSelection: ApplicationSelection {
    func identify(_ url: URL) -> SelectedApplication? { nil }
}
private struct MemoryThumbnailer: ApplicationThumbnailer {
    func thumbnail(from data: Data) throws -> ApplicationThumbnail? { nil }
}
