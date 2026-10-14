import CSQLite
import Foundation
import NecarambaCore

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
/// All database access is confined to one serial executor; never invoke from the event tap.
public final class SQLiteStore: WordRuleStore, AppRuleStore {
  let queue = DispatchQueue(label: "org.necaramba.rules.sqlite")
  var db: OpaquePointer?
  public convenience init(url: URL) throws { try self.init(url: url, migrationSQL: []) }
  init(url: URL, migrationSQL: [String]) throws {
    let code = sqlite3_open_v2(
      url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard code == SQLITE_OK else {
      sqlite3_close(db)
      db = nil
      throw StoreError.databaseFailure(code)
    }
    do {
      try migrate(url: url, extraSQL: migrationSQL)
      try execute("PRAGMA foreign_keys=ON")
      try execute("PRAGMA journal_mode=WAL")
      sqlite3_busy_timeout(db, 5000)
    } catch {
      sqlite3_close(db)
      db = nil
      throw error
    }
  }
  deinit { sqlite3_close(db) }
  func execute(_ sql: String) throws {
    let code = sqlite3_exec(db, sql, nil, nil, nil)
    guard code == SQLITE_OK else { throw StoreError.databaseFailure(code) }
  }
  func statement<T>(_ sql: String, _ bindings: [Any] = [], _ body: (OpaquePointer) throws -> T)
    throws -> T
  {
    var raw: OpaquePointer?
    let code = sqlite3_prepare_v2(db, sql, -1, &raw, nil)
    guard code == SQLITE_OK, let s = raw else { throw StoreError.databaseFailure(code) }
    defer { sqlite3_finalize(s) }
    for (offset, value) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      if let value = value as? String {
        result = sqlite3_bind_text(s, index, value, -1, transient)
      } else if let value = value as? Int64 {
        result = sqlite3_bind_int64(s, index, value)
      } else if let value = value as? Data {
        result =
          value.isEmpty
          ? sqlite3_bind_zeroblob(s, index, 0)
          : value.withUnsafeBytes {
            sqlite3_bind_blob(s, index, $0.baseAddress, Int32($0.count), transient)
          }
      } else {
        result = sqlite3_bind_null(s, index)
      }
      guard result == SQLITE_OK else { throw StoreError.databaseFailure(result) }
    }
    return try body(s)
  }
  func write(_ sql: String, _ bindings: [Any]) throws {
    try statement(sql, bindings) { s in
      let c = sqlite3_step(s)
      guard c == SQLITE_DONE else { throw StoreError.databaseFailure(c) }
    }
  }
  func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  func text(_ s: OpaquePointer, _ column: Int32) -> String {
    String(cString: sqlite3_column_text(s, column))
  }
  func readWords(_ table: String) throws -> [WordRule] {
    try statement(
      "SELECT id,normalized,original,created_at,share_opt_in FROM \(table) ORDER BY normalized,id"
    ) { s in
      var values: [WordRule] = []
      while true {
        let c = sqlite3_step(s)
        if c == SQLITE_DONE { break }
        guard c == SQLITE_ROW, let id = UUID(uuidString: text(s, 0)) else {
          throw StoreError.invalidArchive
        }
        values.append(
          WordRule(
            id: id, normalized: text(s, 1), original: text(s, 2),
            createdAt: sqlite3_column_int64(s, 3), shareOptIn: sqlite3_column_int(s, 4) != 0))
      }
      return values
    }
  }
  public func words() throws -> [WordRule] { try queue.sync { try readWords("word_rules") } }
  public func legacyWords() throws -> [WordRule] {
    try queue.sync { try readWords("legacy_word_rules") }
  }
  func insert(_ word: WordRule, table: String) throws {
    try write(
      "INSERT INTO \(table)(id,normalized,original,created_at,share_opt_in) VALUES(?,?,?,?,?)",
      [
        word.id.uuidString, word.normalized, word.original, word.createdAt,
        Int64(word.shareOptIn ? 1 : 0),
      ])
  }
  public func addWord(_ text: String, at: Int64) throws -> WordRule {
    let v = try RuleValidation.word(text)
    return try queue.sync {
      try transaction {
        guard
          !(try readWords("word_rules") + readWords("legacy_word_rules")).contains(where: {
            $0.normalized == v.normalized
          })
        else { throw StoreError.duplicateWord }
        let w = WordRule(
          id: UUID(), normalized: v.normalized, original: v.original, createdAt: at,
          shareOptIn: false)
        try insert(w, table: "word_rules")
        return w
      }
    }
  }
  public func deleteWord(id: UUID) throws {
    try queue.sync { try write("DELETE FROM word_rules WHERE id=?", [id.uuidString]) }
  }
  public func clearWords() throws { try queue.sync { try execute("DELETE FROM word_rules") } }
  func readApps() throws -> [AppRule] {
    try statement(
      "SELECT bundle_id,display_name,bookmark,mode,updated_at FROM app_rules ORDER BY bundle_id"
    ) { s in
      var values: [AppRule] = []
      while true {
        let c = sqlite3_step(s)
        if c == SQLITE_DONE { break }
        guard c == SQLITE_ROW, let mode = AppRuleMode(rawValue: text(s, 3)) else {
          throw StoreError.invalidArchive
        }
        let bookmark: Data? =
          sqlite3_column_type(s, 2) == SQLITE_NULL
          ? nil
          : (sqlite3_column_bytes(s, 2) == 0
            ? Data()
            : Data(bytes: sqlite3_column_blob(s, 2), count: Int(sqlite3_column_bytes(s, 2))))
        values.append(
          AppRule(
            bundleID: text(s, 0), displayName: text(s, 1), bookmark: bookmark, mode: mode,
            updatedAt: sqlite3_column_int64(s, 4)))
      }
      return values
    }
  }
  public func apps() throws -> [AppRule] { try queue.sync { try readApps() } }
  func insertApp(_ a: AppRule, replace: Bool) throws {
    try write(
      "INSERT \(replace ? "OR REPLACE":"") INTO app_rules(bundle_id,display_name,bookmark,mode,updated_at) VALUES(?,?,?,?,?)",
      [a.bundleID, a.displayName, a.bookmark as Any, a.mode.rawValue, a.updatedAt])
  }
  public func setApp(_ rule: AppRule) throws {
    try RuleValidation.app(rule)
    try queue.sync { try insertApp(rule, replace: true) }
  }
  public func deleteApp(bundleID: String) throws {
    try queue.sync { try write("DELETE FROM app_rules WHERE bundle_id=?", [bundleID]) }
  }
  public func exportArchive() throws -> Data {
    try queue.sync {
      try transaction {
        try JSONEncoder().encode(
          RuleArchiveV1(
            words: readWords("word_rules"), legacyWords: readWords("legacy_word_rules"),
            apps: readApps()))
      }
    }
  }
  public func importArchive(_ data: Data) throws {
    let archive: RuleArchiveV1
    do { archive = try JSONDecoder().decode(RuleArchiveV1.self, from: data) } catch {
      throw StoreError.invalidArchive
    }
    guard archive.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
    var normal: [WordRule] = []
    var legacy: [WordRule] = []
    var names = Set<String>()
    var ids = Set<UUID>()
    var bundles = Set<String>()
    for w in archive.words + archive.legacyWords {
      let v = try RuleValidation.word(w.original, maximumLength: 100)
      guard v.normalized == w.normalized, names.insert(w.normalized).inserted,
        ids.insert(w.id).inserted
      else { throw StoreError.invalidArchive }
      if v.original.count > 20 { legacy.append(w) } else { normal.append(w) }
    }
    for app in archive.apps {
      try RuleValidation.app(app)
      guard bundles.insert(app.bundleID).inserted else { throw StoreError.invalidArchive }
    }
    try queue.sync {
      try transaction {
        let existing = try readWords("word_rules") + readWords("legacy_word_rules")
        guard names.isDisjoint(with: existing.map(\.normalized)),
          ids.isDisjoint(with: existing.map(\.id)),
          bundles.isDisjoint(with: try readApps().map(\.bundleID))
        else { throw StoreError.invalidArchive }
        for w in normal { try insert(w, table: "word_rules") }
        for w in legacy { try insert(w, table: "legacy_word_rules") }
        for a in archive.apps { try insertApp(a, replace: false) }
      }
    }
  }
  public func backup(to url: URL) throws { try queue.sync { try backupDatabase(to: url) } }
  func backupDatabase(to url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { throw StoreError.invalidArchive }
    var destination: OpaquePointer?
    let open = sqlite3_open(url.path, &destination)
    guard open == SQLITE_OK else {
      sqlite3_close(destination)
      throw StoreError.databaseFailure(open)
    }
    defer { sqlite3_close(destination) }
    guard let backup = sqlite3_backup_init(destination, "main", db, "main") else {
      throw StoreError.databaseFailure(sqlite3_errcode(destination))
    }
    let step = sqlite3_backup_step(backup, -1)
    let finish = sqlite3_backup_finish(backup)
    guard step == SQLITE_DONE, finish == SQLITE_OK else {
      try? FileManager.default.removeItem(at: url)
      throw StoreError.databaseFailure(step == SQLITE_DONE ? finish : step)
    }
  }
}
