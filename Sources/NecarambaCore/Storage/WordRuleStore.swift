import Foundation

public protocol WordRuleStore {
  func words() throws -> [WordRule]
  func addWord(_ text: String, at: Int64) throws -> WordRule
  func deleteWord(id: UUID) throws
  func clearWords() throws
}
