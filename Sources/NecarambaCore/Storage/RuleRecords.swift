import Foundation

public struct WordRule: Codable, Equatable, Sendable {
  public let id: UUID
  public let normalized: String
  public let original: String
  public let createdAt: Int64
  public let shareOptIn: Bool
  public init(id: UUID, normalized: String, original: String, createdAt: Int64, shareOptIn: Bool) {
    self.id = id
    self.normalized = normalized
    self.original = original
    self.createdAt = createdAt
    self.shareOptIn = shareOptIn
  }
}
public enum AppRuleMode: String, Codable, Sendable { case allow, deny }
public struct AppRule: Codable, Equatable, Sendable {
  public let bundleID: String
  public let displayName: String
  public let bookmark: Data?
  public let mode: AppRuleMode
  public let updatedAt: Int64
  public init(
    bundleID: String, displayName: String, bookmark: Data?, mode: AppRuleMode, updatedAt: Int64
  ) {
    self.bundleID = bundleID
    self.displayName = displayName
    self.bookmark = bookmark
    self.mode = mode
    self.updatedAt = updatedAt
  }
}
public enum StoreError: Error, Equatable {
  case invalidWord, duplicateWord, invalidArchive, unsupportedSchema
  case databaseFailure(Int32)
  case failedIntegrityCheck
}
public enum RuleValidation {
  public static func normalize(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.folding(
      options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")
    ).precomposedStringWithCanonicalMapping
  }
  public static func word(_ text: String, maximumLength: Int = 20) throws -> (
    original: String, normalized: String
  ) {
    // Reject controls before trimming so leading newlines cannot evade validation.
    guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
      !text.contains("="), !text.contains("%")
    else { throw StoreError.invalidWord }
    let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    let scalars = original.unicodeScalars
    guard (1...maximumLength).contains(original.count),
      !(scalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
        && !scalars.contains(where: { CharacterSet.letters.contains($0) }))
    else { throw StoreError.invalidWord }
    return (original, normalize(original))
  }
  public static func app(_ rule: AppRule) throws {
    guard !rule.bundleID.isEmpty,
      rule.bundleID == rule.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
      !rule.bundleID.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { throw StoreError.invalidArchive }
  }
}
