import Foundation
import CSQLite
import NecarambaCore

public struct ApplicationArchiveV1: Codable {
    public let schemaVersion:Int
    public let rules:RuleArchiveV1
    public let preferences:StoredPreferencesV1
    public init(rules:RuleArchiveV1,preferences:StoredPreferencesV1) {
        schemaVersion=1; self.rules=rules; self.preferences=preferences
    }
}

extension SQLiteStore {
    public func preferencesData() throws -> Data? {
        try queue.sync {
            try statement("SELECT payload FROM application_preferences WHERE id=1") { s in
                let code=sqlite3_step(s)
                if code == SQLITE_DONE { return nil }
                guard code == SQLITE_ROW,sqlite3_column_type(s,0)==SQLITE_BLOB,
                      let bytes=sqlite3_column_blob(s,0),sqlite3_column_bytes(s,0)>0 else { throw StoreError.invalidArchive }
                return Data(bytes:bytes,count:Int(sqlite3_column_bytes(s,0)))
            }
        }
    }
    public func savePreferences(_ bytes:Data) throws {
        try JSONDecoder().decode(StoredPreferencesV1.self,from:bytes).validate()
        try queue.sync { try write("INSERT OR REPLACE INTO application_preferences(id,payload) VALUES(1,?)",[bytes]) }
    }
}
