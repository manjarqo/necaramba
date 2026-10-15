import Foundation
import NecarambaCore

// Offline research runner. Loads only an explicitly supplied local neutral export.
// No extracted model, decryption key or original executable is distributed here.
private struct NeutralModel: Decodable {
  let version: String
  let kbm: KBM
  let autocorrect: Autocorrect?
  struct Autocorrect: Decodable {
    let graph_records: [Record]
    let rules: [Rule]
    let insert_pool: [String]
    struct Rule: Decodable {
      let prefix_len: Int
      let suffix_len: Int
      let insert_id: Int
      let case_sensitive: Bool?
      let is_yofikator: Bool?
    }
  }
  struct KBM: Decodable {
    let graph_records: [Record]
    let index: [String: [Feature]]
    let languages: [String: String]
  }
  struct Record: Decodable { let key: String; let value: Int }
  struct Feature: Decodable {
    let lang: Int
    let weight: Int32
    let is_known_word: Bool
    let is_case_sensitive: Bool
  }
}
private enum Failure: Error, CustomStringConvertible {
  case usage, invalid(String)
  var description: String {
    switch self {
    case .usage: return "Usage: ModelReplayRunner --model /absolute/model-neutral.json --pair ru-en [--incomplete | --token] [--validate-autocorrect] [--autocorrect] --text TEXT [--text TEXT ...]"
    case .invalid(let reason): return reason
    }
  }
}
private func run() throws {
  let args = Array(CommandLine.arguments.dropFirst())
  var path: String?, pair: String?, texts: [String] = []
  var framing = PatternClassifier.Framing.complete
  var tokenMode = false
  var validateAutocorrect = false
  var applyAutocorrect = false
  var index = 0
  while index < args.count {
    let flag = args[index]; index += 1
    if flag == "--incomplete" { framing = .incomplete; continue }
    if flag == "--token" { tokenMode = true; continue }
    if flag == "--validate-autocorrect" { validateAutocorrect = true; continue }
    if flag == "--autocorrect" { applyAutocorrect = true; continue }
    guard index < args.count else { throw Failure.usage }
    let value = args[index]; index += 1
    switch flag {
    case "--model": guard path == nil else { throw Failure.usage }; path = value
    case "--pair": guard pair == nil else { throw Failure.usage }; pair = value
    case "--text": texts.append(value)
    default: throw Failure.usage
    }
  }
  guard let path, path.hasPrefix("/"), let requestedPair = pair,
    !texts.isEmpty, texts.count <= 100 else { throw Failure.usage }
  let url = URL(fileURLWithPath: path)
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 else {
    throw Failure.invalid("Model exceeds the 64 MiB research input limit")
  }
  let data = try Data(contentsOf: url)
  guard data.count <= 64 * 1024 * 1024 else { throw Failure.invalid("Model grew beyond input limit") }
  let model = try JSONDecoder().decode(NeutralModel.self, from: data)
  let pairs = Set(model.kbm.languages.values)
  let requestedParts = requestedPair.split(separator: "-", omittingEmptySubsequences: false)
  guard requestedParts.count == 2, requestedParts.allSatisfy({ !$0.isEmpty }) else { throw Failure.usage }
  let reversedPair = requestedParts.reversed().joined(separator: "-")
  guard let pair = pairs.contains(requestedPair) ? requestedPair : (pairs.contains(reversedPair) ? reversedPair : nil) else {
    throw Failure.invalid("Language pair is not present in the supplied model")
  }
  var patterns: [ClassifierPattern] = []
  patterns.reserveCapacity(model.kbm.graph_records.count)
  for record in model.kbm.graph_records {
    guard let rawFeatures = model.kbm.index[String(record.value)] else {
      throw Failure.invalid("Unresolved graph feature-set reference")
    }
    let features = try rawFeatures.map { feature -> PatternFeature in
      guard let languagePair = model.kbm.languages[String(feature.lang)] else {
        throw Failure.invalid("Unresolved feature language reference")
      }
      return PatternFeature(languagePair: languagePair, weight: feature.weight,
        caseSensitive: feature.is_case_sensitive, knownWord: feature.is_known_word)
    }
    patterns.append(ClassifierPattern(text: record.key, features: features))
  }
  let begin = ProcessInfo.processInfo.systemUptime
  let classifier = try PatternClassifier(patterns: patterns, supportedLanguagePairs: pairs)
  let buildMilliseconds = (ProcessInfo.processInfo.systemUptime - begin) * 1000
  let results: [[String: Any]] = texts.map { text in
    let result = tokenMode ? classifier.classifyToken(text, languagePair: pair) :
      classifier.classify(text, languagePair: pair, framing: framing)
    return ["input": text, "status": String(describing: result.status), "score": result.score]
  }
  var output: [String: Any] = ["modelVersion": model.version,
    "patternCount": patterns.count, "languagePair": pair,
    "framing": tokenMode ? "token-boundary" : (framing == .complete ? "complete" : "incomplete"),
    "compileMilliseconds": buildMilliseconds,
    "scope": "Independent static model replay; no live-editor changes, app policies, layout selection or original runtime parity implied. Raw framing does not trim; --token applies the documented token preprocessing. Autocorrect runs only when explicitly requested.",
    "results": results]
  if validateAutocorrect {
    guard let autocorrect = model.autocorrect else { throw Failure.invalid("Missing autocorrect table") }
    var accepted = 0
    var rejected = 0
    for record in autocorrect.graph_records {
      guard autocorrect.rules.indices.contains(record.value) else {
        throw Failure.invalid("Unresolved autocorrect rule reference")
      }
      let rule = autocorrect.rules[record.value]
      guard autocorrect.insert_pool.indices.contains(rule.insert_id) else {
        throw Failure.invalid("Unresolved autocorrect insertion reference")
      }
      let material = record.key.unicodeScalars.filter { $0.value != 2 && $0.value != 3 }
      let operation = PatternRewriteRule(prefixBytes: rule.prefix_len, suffixBytes: rule.suffix_len,
        insertion: autocorrect.insert_pool[rule.insert_id])
      if operation.apply(to: String(String.UnicodeScalarView(material))) != nil { accepted += 1 }
      else { rejected += 1 }
    }
    output["autocorrectSpliceValidation"] = ["accepted": accepted, "rejected": rejected]
  }
  if applyAutocorrect {
    guard let autocorrect = model.autocorrect else { throw Failure.invalid("Missing autocorrect table") }
    let rules = try autocorrect.graph_records.map { record -> PatternAutocorrectRule in
      guard autocorrect.rules.indices.contains(record.value) else {
        throw Failure.invalid("Unresolved autocorrect rule reference")
      }
      let rule = autocorrect.rules[record.value]
      guard autocorrect.insert_pool.indices.contains(rule.insert_id) else {
        throw Failure.invalid("Unresolved autocorrect insertion reference")
      }
      return .init(pattern: record.key,
        rewrite: .init(prefixBytes: rule.prefix_len, suffixBytes: rule.suffix_len,
          insertion: autocorrect.insert_pool[rule.insert_id]),
        caseSensitive: rule.case_sensitive ?? false, isYofikator: rule.is_yofikator ?? false)
    }
    let corrector = try PatternAutocorrector(rules: rules)
    output["autocorrectResults"] = texts.map { text -> [String: Any] in
      let result = corrector.correct(text, forceComplete: !tokenMode && framing == .complete)
      return ["input": text, "status": String(describing: result.status),
        "replacement": result.replacement as Any? ?? NSNull(), "appliedRuleCount": result.appliedRuleCount]
    }
  }
  let encoded = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
  FileHandle.standardOutput.write(encoded)
  FileHandle.standardOutput.write(Data("\n".utf8))
}
do { try run() }
catch {
  FileHandle.standardError.write(Data("ModelReplayRunner: \(error)\n".utf8))
  exit(2)
}
