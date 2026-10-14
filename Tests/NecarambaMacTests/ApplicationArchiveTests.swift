import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ApplicationArchiveTests:XCTestCase {
    func testImportCommitsRulesAndPreferencesTogetherAndSurvivesReopen() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let source=try SQLiteStore(url:root.appendingPathComponent("source.sqlite"))
        _ = try source.addWord("пример",at:1)
        let prefs=StoredPreferencesV1(selectedColor:7)
        let targetURL=root.appendingPathComponent("target.sqlite")
        let target=try SQLiteStore(url:targetURL)
        try target.importArchive(try source.exportArchive(),preferences:JSONEncoder().encode(prefs))
        let reopened=try SQLiteStore(url:targetURL)
        XCTAssertEqual(try reopened.words().map(\.original),["пример"])
        XCTAssertEqual(try JSONDecoder().decode(StoredPreferencesV1.self,from:XCTUnwrap(reopened.preferencesData())),prefs)
    }
    func testConflictDoesNotPartiallyChangePreferencesOrRules() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try SQLiteStore(url:root.appendingPathComponent("rules.sqlite"))
        _ = try store.addWord("пример",at:1)
        let before=try JSONEncoder().encode(StoredPreferencesV1(selectedColor:3))
        try store.savePreferences(before)
        XCTAssertThrowsError(try store.importArchive(store.exportArchive(),preferences:JSONEncoder().encode(StoredPreferencesV1(selectedColor:9))))
        XCTAssertEqual(try store.preferencesData(),before)
        XCTAssertEqual(try store.words().count,1)
    }
}
