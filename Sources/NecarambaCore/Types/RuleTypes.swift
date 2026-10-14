public struct Lexeme: Codable, Equatable, Sendable {
    public let word: String
    public let language: Language
    public let frequencyBand: UInt8

    public init(word: String, language: Language, frequencyBand: UInt8) {
        self.word = word
        self.language = language
        self.frequencyBand = frequencyBand
    }
}

public struct ReplacementRule: Codable, Equatable, Sendable {
    public let source: String
    public let target: String
    public let caseSensitive: Bool

    public init(source: String, target: String, caseSensitive: Bool) {
        self.source = source
        self.target = target
        self.caseSensitive = caseSensitive
    }
}

public struct LayoutMapping: Codable, Equatable, Sendable {
    public let source: LayoutID
    public let target: LayoutID
    public let pairs: [String: String]

    public init(source: LayoutID, target: LayoutID, pairs: [String: String]) {
        self.source = source
        self.target = target
        self.pairs = pairs
    }
}

public struct RuleSnapshot: Codable, Equatable, Sendable {
    public let modelVersion: UInt64
    public let lexicon: [Lexeme]
    public let typos: [ReplacementRule]
    public let yoRules: [ReplacementRule]
    public let protectedTokens: Set<String>
    public let mappings: [LayoutMapping]

    public init(modelVersion: UInt64, lexicon: [Lexeme] = [], typos: [ReplacementRule] = [], yoRules: [ReplacementRule] = [], protectedTokens: Set<String> = [], mappings: [LayoutMapping] = []) {
        self.modelVersion = modelVersion
        self.lexicon = lexicon
        self.typos = typos
        self.yoRules = yoRules
        self.protectedTokens = protectedTokens
        self.mappings = mappings
    }
}
