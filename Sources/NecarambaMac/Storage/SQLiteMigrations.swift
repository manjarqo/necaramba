import CSQLite
import Foundation
import NecarambaCore

extension SQLiteStore {
  func migrate(url: URL, extraSQL: [String]) throws {
    let integrity = try statement("PRAGMA integrity_check") { s -> Bool in
      sqlite3_step(s) == SQLITE_ROW && text(s, 0) == "ok"
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
      while sqlite3_step(s) == SQLITE_ROW { result.insert(text(s, 0)) }
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
      return
    }
    // The only admitted v0 fixture is the documented own word_rules schema.
    // Unknown tables/columns are never treated as an empty database.
    if !tables.isEmpty {
      guard tables == ["word_rules"] else { throw StoreError.unsupportedSchema }
      let columns = try statement("PRAGMA table_info(word_rules)") { s -> [String] in
        var result: [String] = []
        while sqlite3_step(s) == SQLITE_ROW { result.append(text(s, 1)) }
        return result
      }
      guard columns == ["id", "normalized", "original", "created_at", "share_opt_in"] else {
        throw StoreError.unsupportedSchema
      }
      for word in try readWords("word_rules") {
        let validated = try RuleValidation.word(word.original, maximumLength: 100)
        guard word.normalized == validated.normalized else { throw StoreError.invalidArchive }
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
}
