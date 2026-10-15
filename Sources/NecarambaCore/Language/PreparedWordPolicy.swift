/// Immutable, small policy snapshot. Construct when user policy changes, then
/// reuse for all decisions in that configuration generation.
public struct PreparedWordPolicy: Sendable {
    private let excluded: Set<String>
    private let protected: Set<String>

    public init(excluded: Set<String>, protected: Set<String>) {
        self.excluded = Set(excluded.map(TokenGuard.normalized))
        self.protected = Set(protected.map(TokenGuard.normalized))
    }

    public func contains(_ word: String) -> Bool {
        let normalized = TokenGuard.normalized(word)
        return excluded.contains(normalized) || protected.contains(normalized)
    }

    // Engines retain their model's protection rules and reason precedence.
    // User exclusions must be checked independently at every correction stage.
    func containsExcluded(_ word: String) -> Bool {
        excluded.contains(TokenGuard.normalized(word))
    }
}
