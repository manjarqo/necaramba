import Foundation
public struct RuleIndex: Sendable {
    private let knownWords: Set<String>
    private let protectedWords: Set<String>
    private let typos: [ReplacementRule]
    private let yo: [ReplacementRule]
    public init(snapshot: RuleSnapshot) {
        knownWords = Set(snapshot.lexicon.map { TokenGuard.normalized($0.word) })
        protectedWords = Set(snapshot.protectedTokens.map(TokenGuard.normalized))
        typos = snapshot.typos; yo = snapshot.yoRules
    }
    public func isKnown(_ text: String) -> Bool { knownWords.contains(TokenGuard.normalized(text)) }
    public func isProtected(_ text: String) -> Bool { protectedWords.contains(TokenGuard.normalized(text)) || TokenGuard.isProtected(text) }
    public func typo(for text: String) -> String? { lookup(text, rules: typos) }
    public func yo(for text: String) -> String? { lookup(text, rules: yo) }
    private func lookup(_ text: String, rules: [ReplacementRule]) -> String? {
        let matches = rules.filter { $0.caseSensitive ? $0.source.precomposedStringWithCanonicalMapping == text.precomposedStringWithCanonicalMapping : TokenGuard.normalized($0.source) == TokenGuard.normalized(text) }
        let targets = Set(matches.map(\.target))
        guard targets.count == 1, let rule = matches.first else { return nil }
        return rule.caseSensitive ? rule.target : Self.preserveCase(text, target: rule.target)
    }
    public static func preserveCase(_ source: String, target: String) -> String {
        if source == source.uppercased() { return target.uppercased() }
        if source == source.lowercased() { return target.lowercased() }
        if source == source.prefix(1).uppercased() + source.dropFirst().lowercased() {
            return target.prefix(1).uppercased() + target.dropFirst().lowercased()
        }
        return target
    }
    public static func doubleCapsCandidate(_ text: String) -> String? {
        let chars = Array(text)
        guard chars.count >= 3, chars[0].isUppercase, chars[1].isUppercase,
              chars.dropFirst(2).allSatisfy({ $0.isLowercase }) else { return nil }
        return String(chars[0]) + String(chars.dropFirst()).lowercased()
    }
}
