import Foundation
public struct RuleSharePayload: Codable, Equatable, Sendable {
    public let word: String
    public let language: Language
    public let modelVersion: UInt64
    public let feedback: String?
    public init(word: String, language: Language, modelVersion: UInt64, feedback: String?) {
        self.word = word; self.language = language; self.modelVersion = modelVersion; self.feedback = feedback
    }
    public func validated() throws -> RuleSharePayload {
        let word = try RuleValidation.word(word).original
        let feedback = feedback?.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard feedback.map({ $0.count <= 2000 && !$0.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t" } }) ?? true else { throw StoreError.invalidWord }
        return .init(word: word, language: language, modelVersion: modelVersion, feedback: feedback?.isEmpty == true ? nil : feedback)
    }
}
public protocol RuleShareTransport { func send(_ payload: RuleSharePayload) async throws }
