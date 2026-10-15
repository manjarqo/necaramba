import Foundation
import Darwin
import NecarambaCore

public struct LocalPatternModel: Sendable {
  public let version: String
  public let classifier: PatternClassifier
  public let autocorrector: PatternAutocorrector
}

/// Loads only caller-supplied neutral JSON. Compilation is synchronous; callers
/// must perform it away from the input tap and main thread. No model is bundled.
public enum LocalPatternModelLoader {
  public enum LoadingError: Error { case invalidFile, resourceLimit, invalidModel }
  private static let maximumBytes = 64 * 1024 * 1024

  public static func load(url: URL) throws -> LocalPatternModel {
    guard url.isFileURL else { throw LoadingError.invalidFile }
    // Validate the opened descriptor, not an earlier path lookup. Refuse links,
    // devices and FIFOs (O_NONBLOCK prevents blocking on a malicious FIFO).
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw LoadingError.invalidFile }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0,
      attributes.st_mode & S_IFMT == S_IFREG else { throw LoadingError.invalidFile }
    guard attributes.st_size > 0, attributes.st_size <= maximumBytes else { throw LoadingError.resourceLimit }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw LoadingError.resourceLimit }
    let model = try JSONDecoder().decode(NeutralModel.self, from: data)
    guard !model.version.isEmpty, model.version.utf8.count <= 128,
      !model.kbm.languages.isEmpty,
      model.kbm.languages.keys.allSatisfy(validID), model.kbm.index.keys.allSatisfy(validID),
      model.kbm.languages.values.allSatisfy(validPair),
      Set(model.kbm.languages.values).count == model.kbm.languages.count,
      uniqueKeys(model.kbm.graph_records), uniqueKeys(model.autocorrect.graph_records)
    else { throw LoadingError.invalidModel }
    var featureSets: [Int: [PatternFeature]] = [:]
    for (id, entries) in model.kbm.index {
      featureSets[Int(id)!] = try entries.map { feature in
        guard feature.lang >= 0, let pair = model.kbm.languages[String(feature.lang)]
        else { throw LoadingError.invalidModel }
        return PatternFeature(languagePair: pair, weight: feature.weight,
          caseSensitive: feature.is_case_sensitive, knownWord: feature.is_known_word)
      }
    }
    let patterns = try model.kbm.graph_records.map { record in
      guard record.value >= 0, let features = featureSets[record.value]
      else { throw LoadingError.invalidModel }
      return ClassifierPattern(text: record.key, features: features)
    }
    for rule in model.autocorrect.rules {
      guard rule.prefix_len >= 0, rule.suffix_len >= 0,
        model.autocorrect.insert_pool.indices.contains(rule.insert_id)
      else { throw LoadingError.invalidModel }
    }
    let rewrites = try model.autocorrect.graph_records.map { record in
      guard model.autocorrect.rules.indices.contains(record.value) else { throw LoadingError.invalidModel }
      let rule = model.autocorrect.rules[record.value]
      return PatternAutocorrectRule(pattern: record.key,
        rewrite: .init(prefixBytes: rule.prefix_len, suffixBytes: rule.suffix_len,
          insertion: model.autocorrect.insert_pool[rule.insert_id]),
        caseSensitive: rule.case_sensitive ?? false, isYofikator: rule.is_yofikator ?? false)
    }
    return try LocalPatternModel(version: model.version,
      classifier: PatternClassifier(patterns: patterns, supportedLanguagePairs: Set(model.kbm.languages.values)),
      autocorrector: PatternAutocorrector(rules: rewrites))
  }
  private static func validID(_ text: String) -> Bool {
    guard let id = Int(text), id >= 0 else { return false }
    return String(id) == text
  }
  private static func validPair(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    return parts.count == 2 && parts[0] != parts[1] && parts.allSatisfy {
      (2...8).contains($0.utf8.count) && $0.utf8.allSatisfy { (97...122).contains($0) }
    }
  }
  private static func uniqueKeys(_ records: [NeutralModel.Record]) -> Bool {
    Set(records.map(\.key)).count == records.count
  }
}

private struct NeutralModel: Decodable {
  let version: String
  let kbm: KBM
  let autocorrect: Autocorrect
  struct KBM: Decodable {
    let graph_records: [Record]
    let index: [String: [Feature]]
    let languages: [String: String]
  }
  struct Autocorrect: Decodable {
    let graph_records: [Record]
    let rules: [Rule]
    let insert_pool: [String]
  }
  struct Record: Decodable { let key: String; let value: Int }
  struct Feature: Decodable {
    let lang: Int
    let weight: Int32
    let is_known_word: Bool
    let is_case_sensitive: Bool
  }
  struct Rule: Decodable {
    let prefix_len: Int
    let suffix_len: Int
    let insert_id: Int
    let case_sensitive: Bool?
    let is_yofikator: Bool?
  }
}
