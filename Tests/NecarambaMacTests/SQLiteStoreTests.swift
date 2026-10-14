import CSQLite
import NecarambaCore
import XCTest

@testable import NecarambaMac

final class SQLiteStoreTests: XCTestCase {
  func temporary(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir.appendingPathComponent("rules.sqlite"))
  }
  func testInvalidImportKeepsExistingRule() throws {
    try temporary { url in
      let store = try SQLiteStore(url: url)
      _ = try store.addWord("превет", at: 1)
      XCTAssertThrowsError(try store.importArchive(Data(#"{"schemaVersion":1,"words":[{}]}"#.utf8)))
      XCTAssertEqual(try SQLiteStore(url: url).words().map(\.original), ["превет"])
    }
  }
  func testPersistenceUniquenessAppsAndBackup() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      let word = try s.addWord(" École ", at: 2)
      XCTAssertThrowsError(try s.addWord("e\u{301}COLE", at: 3))
      try s.setApp(
        AppRule(
          bundleID: "org.test.app", displayName: "Test", bookmark: Data([0, 1]), mode: .deny,
          updatedAt: 4))
      let backup = url.appendingPathExtension("backup")
      try s.backup(to: backup)
      XCTAssertEqual(try SQLiteStore(url: backup).words(), [word])
      XCTAssertEqual(try SQLiteStore(url: url).apps().first?.bookmark, Data([0, 1]))
      try s.deleteWord(id: word.id)
      try s.deleteApp(bundleID: "org.test.app")
      XCTAssertTrue(try s.words().isEmpty)
      XCTAssertTrue(try s.apps().isEmpty)
    }
  }
  func testArchiveLegacyBoundariesAndConflictRollback() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      func record(_ text: String) -> WordRule {
        WordRule(
          id: UUID(), normalized: RuleValidation.normalize(text), original: text, createdAt: 1,
          shareOptIn: false)
      }
      let legacy = record(String(repeating: "a", count: 100))
      try s.importArchive(
        JSONEncoder().encode(RuleArchiveV1(words: [record("word"), legacy], apps: [])))
      XCTAssertEqual(try s.words().count, 1)
      XCTAssertEqual(try s.legacyWords(), [legacy])
      let bytes = try s.exportArchive()
      let other = try SQLiteStore(url: url.appendingPathExtension("other"))
      try other.importArchive(bytes)
      XCTAssertEqual(try other.legacyWords(), [legacy])
      XCTAssertThrowsError(
        try s.importArchive(
          JSONEncoder().encode(RuleArchiveV1(words: [record("new"), record("WORD")], apps: []))))
      XCTAssertEqual(try s.words().map(\.original), ["word"])
      XCTAssertThrowsError(
        try s.importArchive(
          JSONEncoder().encode(
            RuleArchiveV1(words: [record(String(repeating: "b", count: 101))], apps: []))))
      XCTAssertThrowsError(try s.addWord(String(repeating: "b", count: 21), at: 1))
    }
  }
  func testMigrationFailureKeepsV0RowsAndVersion() throws {
    try temporary { url in
      var db: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
      let id = UUID().uuidString
      XCTAssertEqual(
        sqlite3_exec(
          db,
          "CREATE TABLE word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0); INSERT INTO word_rules VALUES('\(id)','old','old',1,0)",
          nil, nil, nil), SQLITE_OK)
      sqlite3_close(db)
      XCTAssertThrowsError(
        try SQLiteStore(url: url, migrationSQL: ["SELECT missing_column FROM word_rules"]))
      XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
      var st: OpaquePointer?
      sqlite3_prepare_v2(db, "SELECT original FROM word_rules", -1, &st, nil)
      XCTAssertEqual(sqlite3_step(st), SQLITE_ROW)
      XCTAssertEqual(String(cString: sqlite3_column_text(st, 0)), "old")
      sqlite3_finalize(st)
      sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &st, nil)
      _ = sqlite3_step(st)
      XCTAssertEqual(sqlite3_column_int(st, 0), 0)
      sqlite3_finalize(st)
      sqlite3_close(db)
      XCTAssertEqual(try SQLiteStore(url: url).words().map(\.original), ["old"])
    }
  }
  func testNewerAndCorruptDatabaseArePreserved() throws {
    try temporary { url in
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil)
      sqlite3_close(db)
      XCTAssertThrowsError(try SQLiteStore(url: url))
      let corrupt = url.appendingPathExtension("corrupt")
      let bytes = Data("not a database".utf8)
      try bytes.write(to: corrupt)
      XCTAssertThrowsError(try SQLiteStore(url: corrupt))
      XCTAssertEqual(try Data(contentsOf: corrupt), bytes)
    }
  }
  func testImportSQLFailureRollsBackAlreadyInsertedRows() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      _ = try s.addWord("existing", at: 1)
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      XCTAssertEqual(
        sqlite3_exec(
          db,
          "CREATE TRIGGER reject_bad BEFORE INSERT ON word_rules WHEN NEW.original='bad' BEGIN SELECT RAISE(ABORT,'test failure'); END",
          nil, nil, nil), SQLITE_OK)
      sqlite3_close(db)
      let records = ["good", "bad"].map {
        WordRule(id: UUID(), normalized: $0, original: $0, createdAt: 1, shareOptIn: false)
      }
      XCTAssertThrowsError(
        try s.importArchive(JSONEncoder().encode(RuleArchiveV1(words: records, apps: []))))
      XCTAssertEqual(try SQLiteStore(url: url).words().map(\.original), ["existing"])
    }
  }
  func testEmptyBookmarkRemainsDistinctFromNil() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      try s.setApp(
        AppRule(
          bundleID: "org.empty", displayName: "Empty", bookmark: Data(), mode: .allow, updatedAt: 0)
      )
      XCTAssertEqual(try SQLiteStore(url: url).apps().first?.bookmark, Data())
    }
  }
  func testMigrationLedgerNewerSchemaIsRejected() throws {
    try temporary { url in
      _ = try SQLiteStore(url: url)
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      sqlite3_exec(db, "INSERT INTO migrations(version,applied_at) VALUES(99,0)", nil, nil, nil)
      sqlite3_close(db)
      XCTAssertThrowsError(try SQLiteStore(url: url))
    }
  }

  func testLegacy21PreservesOriginalAndOldArchiveWithoutLegacyKey() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      let original = "  " + String(repeating: "e\u{301}", count: 21) + "  "
      let word = WordRule(
        id: UUID(),
        normalized: RuleValidation.normalize(original.trimmingCharacters(in: .whitespaces)),
        original: original, createdAt: 8, shareOptIn: true)
      let archive = RuleArchiveV1(words: [word], apps: [])
      var object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
      object.removeValue(forKey: "legacyWords")
      try s.importArchive(JSONSerialization.data(withJSONObject: object))
      XCTAssertTrue(try s.words().isEmpty)
      XCTAssertEqual(try s.legacyWords().first?.original.utf8.map { $0 }, original.utf8.map { $0 })
      let reopened = try SQLiteStore(url: url)
      XCTAssertEqual(try reopened.legacyWords(), [word])
    }
  }
  func testArchiveRejectsForgedNormalizationAndAppConflict() throws {
    try temporary { url in
      let s = try SQLiteStore(url: url)
      try s.setApp(
        AppRule(bundleID: "org.test", displayName: "Old", bookmark: nil, mode: .deny, updatedAt: 1))
      let forged = WordRule(
        id: UUID(), normalized: "wrong", original: "word", createdAt: 1, shareOptIn: false)
      XCTAssertThrowsError(
        try s.importArchive(JSONEncoder().encode(RuleArchiveV1(words: [forged], apps: []))))
      let app = AppRule(
        bundleID: "org.test", displayName: "New", bookmark: nil, mode: .allow, updatedAt: 2)
      XCTAssertThrowsError(
        try s.importArchive(JSONEncoder().encode(RuleArchiveV1(words: [], apps: [app]))))
      XCTAssertEqual(try s.apps().first?.displayName, "Old")
    }
  }

  func testNullableV0SchemaRejectedWithoutMutation() throws {
    try temporary { url in
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      sqlite3_exec(
        db,
        "CREATE TABLE word_rules(id TEXT PRIMARY KEY, normalized TEXT, original TEXT, created_at INTEGER, share_opt_in INTEGER); INSERT INTO word_rules VALUES('11111111-1111-1111-1111-111111111111',NULL,NULL,1,0)",
        nil, nil, nil)
      sqlite3_close(db)
      XCTAssertThrowsError(try SQLiteStore(url: url))
      sqlite3_open(url.path, &db)
      var st: OpaquePointer?
      sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_rules WHERE original IS NULL", -1, &st, nil)
      _ = sqlite3_step(st)
      XCTAssertEqual(sqlite3_column_int(st, 0), 1)
      sqlite3_finalize(st)
      sqlite3_close(db)
    }
  }
  func testLowercaseV0UUIDsMigrateOnceAndDelete() throws {
    try temporary { url in
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      let shortID = UUID()
      let longID = UUID()
      let long = String(repeating: "l", count: 21)
      sqlite3_exec(
        db,
        "CREATE TABLE word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0); INSERT INTO word_rules VALUES('\(shortID.uuidString.lowercased())','short','short',1,0); INSERT INTO word_rules VALUES('\(longID.uuidString.lowercased())','\(long)','\(long)',2,0)",
        nil, nil, nil)
      sqlite3_close(db)
      let store = try SQLiteStore(url: url)
      XCTAssertEqual(try store.words().map(\.id), [shortID])
      XCTAssertEqual(try store.legacyWords().map(\.id), [longID])
      let other = try SQLiteStore(url: url.appendingPathExtension("other"))
      try other.importArchive(store.exportArchive())
      XCTAssertEqual(try other.words().map(\.id), [shortID])
      XCTAssertEqual(try other.legacyWords().map(\.id), [longID])
      try store.deleteWord(id: shortID)
      XCTAssertTrue(try SQLiteStore(url: url).words().isEmpty)
    }
  }
  func testAppNULRejectedBeforeReplacingOrImporting() throws {
    try temporary { url in
      let store = try SQLiteStore(url: url)
      let old = AppRule(
        bundleID: "org.test", displayName: "Old", bookmark: nil, mode: .allow, updatedAt: 1)
      try store.setApp(old)
      let bad = AppRule(
        bundleID: "org.test", displayName: "New\u{0}Hidden", bookmark: nil, mode: .deny,
        updatedAt: 2)
      XCTAssertThrowsError(try store.setApp(bad))
      let newBad = AppRule(
        bundleID: "org.other", displayName: bad.displayName, bookmark: nil, mode: .deny,
        updatedAt: 2)
      XCTAssertThrowsError(
        try store.importArchive(JSONEncoder().encode(RuleArchiveV1(words: [], apps: [newBad]))))
      XCTAssertEqual(try SQLiteStore(url: url).apps(), [old])
    }
  }

  func testUnexpectedNullWordIDThrowsInsteadOfCrashing() throws {
    try temporary { url in
      let store = try SQLiteStore(url: url)
      try store.execute("INSERT INTO word_rules VALUES(NULL,'valid','valid',0,0)")
      XCTAssertThrowsError(try store.words())
      XCTAssertThrowsError(try store.exportArchive())
    }
  }
  func testV1NullableWordSchemaRejected() throws {
    try temporary { url in
      _ = try SQLiteStore(url: url)
      var db: OpaquePointer?
      sqlite3_open(url.path, &db)
      sqlite3_exec(
        db,
        "DROP TABLE word_rules; CREATE TABLE word_rules(id TEXT PRIMARY KEY,normalized TEXT UNIQUE,original TEXT,created_at INTEGER,share_opt_in INTEGER)",
        nil, nil, nil)
      sqlite3_close(db)
      XCTAssertThrowsError(try SQLiteStore(url: url))
    }
  }

}
