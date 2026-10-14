import Foundation
import NecarambaCore

public struct RuleArchiveV1: Codable {
  public let schemaVersion: Int
  public let words: [WordRule]
  public let legacyWords: [WordRule]
  public let apps: [AppRule]
  public init(
    schemaVersion: Int = 1, words: [WordRule], legacyWords: [WordRule] = [], apps: [AppRule]
  ) {
    self.schemaVersion = schemaVersion
    self.words = words
    self.legacyWords = legacyWords
    self.apps = apps
  }
  enum CodingKeys: String, CodingKey { case schemaVersion, words, legacyWords, apps }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    words = try c.decode([WordRule].self, forKey: .words)
    legacyWords = try c.decodeIfPresent([WordRule].self, forKey: .legacyWords) ?? []
    apps = try c.decode([AppRule].self, forKey: .apps)
  }
}
