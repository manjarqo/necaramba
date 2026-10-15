/// Shared immutable exact word membership. Callers normalize case before lookup.
public protocol OpenWordLookup: Sendable {
    func contains(_ word: String, language: Language) -> Bool
}
