import Foundation

/// Independently authored, exact replacements. No inferred or fuzzy edits.
public struct OpenCorrectionRules: Sendable {
    public enum ValidationError: Error { case invalid }
    public let version: String
    let typos: [String: String]
    let yo: [String: String]
    /// Never changed automatically, including by layout conversion.
    let protectedWords: Set<String>
    /// Ambiguous е/ё alternatives: never gain or lose ё, but a physical layout
    /// conversion may still produce them. Schema 1 has no such distinction.
    let yoProtectedWords: Set<String>
    /// Explicit English contractions; the only accepted words with an apostrophe.
    let contractions: Set<String>

    public init(data: Data) throws {
        let base: Set<String> = ["schemaVersion", "version", "typos", "yo", "protectedWords"]
        guard data.count <= 8 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = object["schemaVersion"] as? Int, schema == 1 || schema == 2,
              Set(object.keys) == (schema == 1 ? base : base.union(["yoProtectedWords", "contractions"])),
              let version = object["version"] as? String, !version.isEmpty, version.utf8.count <= 128,
              let typoRows = object["typos"] as? [[String: String]],
              let yoRows = object["yo"] as? [[String: String]],
              let protected = object["protectedWords"] as? [String],
              let yoProtected = schema == 1 ? [] : object["yoProtectedWords"] as? [String],
              let contractions = schema == 1 ? [] : object["contractions"] as? [String],
              typoRows.count + yoRows.count <= 100_000, protected.count + yoProtected.count <= 10_000,
              contractions.count <= 1_000
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
        func contraction(_ word: String) -> Bool {
            word.utf8.count <= 32 && word.range(of: "^[a-z]+'[a-z]+$", options: .regularExpression) != nil
        }
        guard Set(yoProtected).count == yoProtected.count, Set(contractions).count == contractions.count,
              yoProtected.allSatisfy({ valid($0) && russian($0) }), contractions.allSatisfy(contraction),
              Set(yoProtected).isDisjoint(with: protected), Set(yoProtected).isDisjoint(with: yo.keys),
              Set(yoProtected).isDisjoint(with: yo.values), Set(yoProtected).isDisjoint(with: typos.keys)
        else { throw ValidationError.invalid }
        self.version = version; self.typos = typos; self.yo = yo; self.protectedWords = Set(protected)
        self.yoProtectedWords = Set(yoProtected); self.contractions = Set(contractions)
    }
}
