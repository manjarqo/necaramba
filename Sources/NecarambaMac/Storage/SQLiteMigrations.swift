import CSQLite
import Foundation
import NecarambaCore

extension SQLiteStore {
  func migrate(url: URL, extraSQL: [String]) throws {
    let integrity = try statement("PRAGMA integrity_check") { s -> Bool in
      try sqlite3_step(s) == SQLITE_ROW && text(s, 0) == "ok"
    }
    guard integrity else { throw StoreError.failedIntegrityCheck }
    let version = try statement("PRAGMA user_version") { s -> Int in
      guard sqlite3_step(s) == SQLITE_ROW else { throw StoreError.failedIntegrityCheck }
      return Int(sqlite3_column_int(s, 0))
    }
    guard version <= 1 else { throw StoreError.unsupportedSchema }
    let tables = try statement(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ) { s -> Set<String> in
      var result = Set<String>()
      while sqlite3_step(s) == SQLITE_ROW { result.insert(try text(s, 0)) }
      return result
    }
    if tables.contains("migrations") {
      let ledger = try statement("SELECT COALESCE(MAX(version),0) FROM migrations") { s -> Int in
        guard sqlite3_step(s) == SQLITE_ROW else { throw StoreError.unsupportedSchema }
        return Int(sqlite3_column_int(s, 0))
      }
      guard ledger == version, ledger <= 1 else { throw StoreError.unsupportedSchema }
    }
    if version == 1 {
      guard
        Set([
          "word_rules", "legacy_word_rules", "app_rules", "migrations", "daily_counters",
          "model_state",
        ]).isSubset(of: tables)
      else { throw StoreError.unsupportedSchema }
      for table in ["word_rules", "legacy_word_rules"] { try validateWordSchema(table) }
      try validateColumns(
        "app_rules",
        expected: [
          ("bundle_id", "TEXT", 0, 1), ("display_name", "TEXT", 1, 0), ("bookmark", "BLOB", 0, 0),
          ("mode", "TEXT", 1, 0), ("updated_at", "INTEGER", 1, 0),
        ])
      try validateColumns(
        "migrations", expected: [("version", "INTEGER", 0, 1), ("applied_at", "INTEGER", 1, 0)])
      try validateColumns(
        "daily_counters",
        expected: [("day", "TEXT", 0, 1), ("kind", "TEXT", 0, 2), ("count", "INTEGER", 0, 0)])
      try validateColumns(
        "model_state",
        expected: [
          ("slot", "TEXT", 0, 1), ("version", "INTEGER", 1, 0), ("digest", "TEXT", 1, 0),
          ("installed_at", "INTEGER", 1, 0),
        ])
      return
    }
    // The only admitted v0 fixture is the documented own word_rules schema.
    // Unknown tables/columns are never treated as an empty database.
    if !tables.isEmpty {
      guard tables == ["word_rules"] else { throw StoreError.unsupportedSchema }
      try validateWordSchema("word_rules")
      var ids = Set<UUID>()
      for word in try readWords("word_rules") {
        let validated = try RuleValidation.word(word.original, maximumLength: 100)
        guard word.normalized == validated.normalized, ids.insert(word.id).inserted else {
          throw StoreError.invalidArchive
        }
      }
      try backupDatabase(to: url.appendingPathExtension("migration-\(UUID().uuidString).backup"))
    }
    try transaction {
      try execute(
        "CREATE TABLE IF NOT EXISTS word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0)"
      )
      try execute(
        "CREATE TABLE legacy_word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0)"
      )
      try execute(
        "CREATE TABLE app_rules(bundle_id TEXT PRIMARY KEY, display_name TEXT NOT NULL, bookmark BLOB, mode TEXT CHECK(mode IN ('allow','deny')) NOT NULL, updated_at INTEGER NOT NULL)"
      )
      try execute(
        "CREATE TABLE migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)")
      try execute(
        "CREATE TABLE daily_counters(day TEXT, kind TEXT, count INTEGER CHECK(count>=0), PRIMARY KEY(day,kind))"
      )
      try execute(
        "CREATE TABLE model_state(slot TEXT PRIMARY KEY, version INTEGER NOT NULL, digest TEXT NOT NULL, installed_at INTEGER NOT NULL)"
      )
      // Canonicalize UUID text before partitioning so deletion uses the persisted identity.
      try execute("UPDATE word_rules SET id=upper(id)")
      for word in try readWords("word_rules") where word.original.count > 20 {
        try insert(word, table: "legacy_word_rules")
        try write("DELETE FROM word_rules WHERE id=?", [word.id.uuidString])
      }
      for sql in extraSQL { try execute(sql) }
      try write(
        "INSERT INTO migrations(version,applied_at) VALUES(1,?)",
        [Int64(Date().timeIntervalSince1970)])
      try execute("PRAGMA user_version=1")
    }
  }
  func validateColumns(_ table: String, expected: [(String, String, Int32, Int32)]) throws {
    let actual = try statement("PRAGMA table_info(\(table))") {
      s -> [(String, String, Int32, Int32)] in
      var result: [(String, String, Int32, Int32)] = []
      while true {
        let code = sqlite3_step(s)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else { throw StoreError.unsupportedSchema }
        result.append(
          (
            try text(s, 1), try text(s, 2).uppercased(), sqlite3_column_int(s, 3),
            sqlite3_column_int(s, 5)
          ))
      }
      return result
    }
    guard actual.count == expected.count,
      zip(actual, expected).allSatisfy({ a, b in
        a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
      })
    else { throw StoreError.unsupportedSchema }
  }
  func validateWordSchema(_ table: String) throws {
    try validateColumns(
      table,
      expected: [
        ("id", "TEXT", 0, 1), ("normalized", "TEXT", 1, 0), ("original", "TEXT", 1, 0),
        ("created_at", "INTEGER", 1, 0), ("share_opt_in", "INTEGER", 1, 0),
      ])
    let indexes = try statement(
      "SELECT name FROM pragma_index_list(?) WHERE \"unique\"=1 AND partial=0", [table]
    ) { s -> [String] in
      var result: [String] = []
      while sqlite3_step(s) == SQLITE_ROW { result.append(try text(s, 0)) }
      return result
    }
    var normalizedUnique = false
    for index in indexes {
      let columns = try statement("SELECT name FROM pragma_index_info(?) ORDER BY seqno", [index]) {
        s -> [String] in
        var result: [String] = []
        while sqlite3_step(s) == SQLITE_ROW { result.append(try text(s, 0)) }
        return result
      }
      if columns == ["normalized"] { normalizedUnique = true }
    }
    guard normalizedUnique else { throw StoreError.unsupportedSchema }
  }

}
