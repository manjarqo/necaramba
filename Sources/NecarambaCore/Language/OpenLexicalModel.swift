import Foundation

/// Independently sourced word membership, not calibrated frequencies or a release-quality claim.
/// Data loading is explicit: this candidate does not replace the app's installed signed rules.
public struct OpenLexicalModel: Sendable {
    public enum ValidationError: Error { case invalidSize, invalidSchema, invalidVersion, invalidLanguages, invalidLexicon }
    public static let maximumDataSize = 64 * 1024 * 1024
    public static let maximumWordCount = 2_000_000
    public let version: String
    private let english: [String]
    private let russian: [String]

    private struct Payload: Decodable {
        let schemaVersion: Int
        let version: String
        let languages: [String: [String]]
    }

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumDataSize else { throw ValidationError.invalidSize }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1 else { throw ValidationError.invalidSchema }
        guard !payload.version.isEmpty, payload.version.utf8.count <= 64,
              payload.version.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (97...122).contains($0.value) ||
                  (48...57).contains($0.value) || [45, 46, 95].contains($0.value)
              }) else { throw ValidationError.invalidVersion }
        guard Set(payload.languages.keys) == ["en", "ru"],
              let en = payload.languages["en"], let ru = payload.languages["ru"],
              !en.isEmpty, !ru.isEmpty else { throw ValidationError.invalidLanguages }
        guard en.count <= Self.maximumWordCount, ru.count <= Self.maximumWordCount - en.count else {
            throw ValidationError.invalidLexicon
        }
        func validate(_ words: [String], russian: Bool) -> Bool {
            var seen = Set<String>()
            seen.reserveCapacity(words.count)
            for word in words {
                guard !word.isEmpty, word.unicodeScalars.count <= 128,
                      word.unicodeScalars.allSatisfy({ scalar in
                          russian ? (1072...1103).contains(scalar.value) || scalar.value == 1105 :
                              (97...122).contains(scalar.value)
                      }), seen.insert(word).inserted else { return false }
            }
            return true
        }
        guard validate(en, russian: false), validate(ru, russian: true) else { throw ValidationError.invalidLexicon }
        version = payload.version
        english = en
        russian = ru
    }

    /// The base's signed-package identity and policy fields are retained for evaluation.
    /// This newly composed snapshot is not itself a verified signed payload.
    public func snapshot(replacingLexiconIn base: RuleSnapshot) -> RuleSnapshot {
        let lexicon = english.map { Lexeme(word: $0, language: .english, frequencyBand: 1) } +
            russian.map { Lexeme(word: $0, language: .russian, frequencyBand: 1) }
        return .init(modelVersion: base.modelVersion, lexicon: lexicon, typos: base.typos,
                     yoRules: base.yoRules, protectedTokens: base.protectedTokens, mappings: base.mappings)
    }
}
