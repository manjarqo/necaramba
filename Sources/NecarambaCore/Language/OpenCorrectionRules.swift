import Foundation

/// Independently authored, exact replacements. No inferred or fuzzy edits.
public struct OpenCorrectionRules: Sendable {
    public enum ValidationError: Error { case invalid }
    public let version: String
    let typos: [String: String]
    let yo: [String: String]
    let protectedWords: Set<String>

    public init(data: Data) throws {
        guard data.count <= 8 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "version", "typos", "yo", "protectedWords"],
              let schema = object["schemaVersion"] as? Int, schema == 1,
              let version = object["version"] as? String, !version.isEmpty, version.utf8.count <= 128,
              let typoRows = object["typos"] as? [[String: String]],
              let yoRows = object["yo"] as? [[String: String]],
              let protected = object["protectedWords"] as? [String],
              typoRows.count + yoRows.count <= 100_000, protected.count <= 10_000
        else { throw ValidationError.invalid }
        func valid(_ word: String) -> Bool {
            !word.isEmpty && word.count <= 128 && word.utf8.count <= 512 &&
                word == TokenGuard.normalized(word) && !TokenGuard.isProtected(word)
        }
        func russian(_ word: String) -> Bool { word.unicodeScalars.allSatisfy { (0x430...0x44f).contains($0.value) || $0.value == 0x451 } }
        func parse(_ rows: [[String: String]], isYo: Bool) throws -> [String: String] {
            var result: [String: String] = [:]
            for row in rows {
                guard Set(row.keys) == ["source", "target"], let source = row["source"], let target = row["target"],
                      valid(source), valid(target), source != target, result[source] == nil,
                      russian(source) == russian(target) else { throw ValidationError.invalid }
                if isYo {
                    guard russian(source), target.contains("ё"), !source.contains("ё"),
                          source == target.replacingOccurrences(of: "ё", with: "е") else { throw ValidationError.invalid }
                }
                result[source] = target
            }
            return result
        }
        let typos = try parse(typoRows, isYo: false), yo = try parse(yoRows, isYo: true)
        guard Set(typos.keys).isDisjoint(with: yo.keys), Set(protected).count == protected.count,
              protected.allSatisfy(valid) else { throw ValidationError.invalid }
        self.version = version; self.typos = typos; self.yo = yo; self.protectedWords = Set(protected)
    }
}
