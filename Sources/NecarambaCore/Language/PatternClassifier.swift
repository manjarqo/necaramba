/// Independent, declarative pattern features. No model data is bundled here.
public struct PatternFeature: Equatable, Sendable {
  public let languagePair: String
  public let weight: Int32
  public let caseSensitive: Bool
  public let knownWord: Bool
  public init(languagePair: String, weight: Int32, caseSensitive: Bool = false, knownWord: Bool = false) {
    self.languagePair = languagePair; self.weight = weight
    self.caseSensitive = caseSensitive; self.knownWord = knownWord
  }
}
public struct ClassifierPattern: Equatable, Sendable {
  public let text: String
  public let features: [PatternFeature]
  public init(text: String, features: [PatternFeature]) { self.text = text; self.features = features }
}
public struct PatternClassification: Equatable, Sendable {
  public enum Status: Sendable { case unsupported, scored, known, rejected }
  public let status: Status
  public let score: Int32
  public init(status: Status, score: Int32) { self.status = status; self.score = score }
}
/// Compiles caller-owned patterns into a UTF-8 trie. This is a scoring primitive,
/// not a layout-switching decision or a loader for any third-party model.
public struct PatternClassifier: Sendable {
  public enum Framing: Sendable { case complete, incomplete }
  public enum CompilationError: Error, Equatable {
    case invalidLanguagePair, malformedPattern, undefinedLanguagePair, resourceLimit
  }
  public static let maximumInputBytes = 512
  public static let maximumPatternBytes = 512
  private static let maximumNodes = 2_000_000
  private static let maximumFeatures = 1_000_000
  private static let maximumFeatureVisits = 100_000
  private struct Node: Sendable {
    var children: [UInt8: Int] = [:]
    var features: [PatternFeature] = []
  }
  private let nodes: [Node]
  private let supportedLanguagePairs: Set<String>

  /// Pair identifiers are opaque, canonical IDs. Resolve layout orientation in
  /// the caller; this primitive never guesses an inverse pair or score sign.
  public init(patterns: [ClassifierPattern], supportedLanguagePairs: Set<String>) throws {
    guard supportedLanguagePairs.count <= 256,
      supportedLanguagePairs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 })
    else { throw CompilationError.invalidLanguagePair }
    guard patterns.count <= 250_000 else { throw CompilationError.resourceLimit }
    var nodes = [Node()]
    var featureCount = 0
    for pattern in patterns {
      guard !pattern.text.isEmpty, pattern.text.utf8.count <= Self.maximumPatternBytes
      else { throw CompilationError.malformedPattern }
      let bytes = Array(pattern.text.utf8)
      guard
        bytes.contains(where: { $0 >= 32 }),
        bytes.enumerated().allSatisfy({ position, byte in
          byte >= 32 || (byte == 2 && position == 0) || (byte == 3 && position == bytes.count - 1)
        })
      else { throw CompilationError.malformedPattern }
      guard pattern.features.allSatisfy({ supportedLanguagePairs.contains($0.languagePair) })
      else { throw CompilationError.undefinedLanguagePair }
      guard pattern.features.count <= Self.maximumFeatures - featureCount
      else { throw CompilationError.resourceLimit }
      featureCount += pattern.features.count
      var index = 0
      for byte in bytes {
        if let next = nodes[index].children[byte] { index = next }
        else {
          guard nodes.count < Self.maximumNodes else { throw CompilationError.resourceLimit }
          let next = nodes.count
          nodes.append(Node())
          nodes[index].children[byte] = next
          index = next
        }
      }
      // Duplicate declarations deliberately retain all features and their order.
      nodes[index].features.append(contentsOf: pattern.features)
    }
    self.nodes = nodes
    self.supportedLanguagePairs = supportedLanguagePairs
  }

  /// Token preprocessing and fallback are explicit opt-in; raw classify stays
  /// available independently. Completion depends on the ORIGINAL last scalar.
  /// Unknown controls inside a token fail closed rather than reaching the trie.
  public func classifyToken(_ input: String, languagePair: String,
    forceComplete: Bool = false) -> PatternClassification {
    guard supportedLanguagePairs.contains(languagePair), input.utf8.count <= Self.maximumInputBytes
    else { return Self.unsupported }
    let complete = forceComplete || input.unicodeScalars.last.map {
      [9, 10, 13, 32, 45].contains($0.value)
    } == true
    let framing: Framing = complete ? .complete : .incomplete
    let trimmed = Self.trimWhitespace(input)
    guard Self.validInput(trimmed) else { return Self.unsupported }
    var result = Accumulator()
    guard evaluate(trimmed, languagePair: languagePair, framing: framing, into: &result)
    else { return Self.unsupported }
    // The feature vector is checked AFTER language and case filtering; even a
    // zero-weight assertion prevents fallback, regardless of its final score.
    guard result.matches == 0 else { return result.classification }
    let punctuation: Set<UInt32> = complete
      ? [33, 36, 38, 40, 41, 42, 43, 45, 47, 63, 64, 94]
      : [33, 40, 41, 43, 61, 95]
    var scalars = Array(trimmed.unicodeScalars)[...]
    while let last = scalars.last, punctuation.contains(last.value) { scalars = scalars.dropLast() }
    while let first = scalars.first, first.value == 45 || first.value == 40 { scalars = scalars.dropFirst() }
    let cleaned = Self.trimWhitespace(String(String.UnicodeScalarView(scalars)))
    let variants = Array(cleaned.utf8) == Array(trimmed.utf8) ? [cleaned] : [cleaned, trimmed]
    for variant in variants {
      guard evaluate(variant, languagePair: languagePair, framing: framing, into: &result)
      else { return Self.unsupported }
    }
    return result.classification
  }

  /// Caller supplies the untrimmed token and decides whether its boundary is
  /// complete. No whitespace trimming, NFC normalization or delimiter inference.
  /// Lowercasing uses Swift's Unicode lowercased(), not a model-specific table.
  /// Overflow/invalid input/resource exhaustion fail closed with unsupported(0).
  public func classify(_ text: String, languagePair: String,
    framing: Framing = .complete) -> PatternClassification {
    guard supportedLanguagePairs.contains(languagePair), Self.validInput(text)
    else { return Self.unsupported }
    var result = Accumulator()
    guard evaluate(text, languagePair: languagePair, framing: framing, into: &result)
    else { return Self.unsupported }
    return result.classification
  }

  private static let unsupported = PatternClassification(status: .unsupported, score: 0)
  private struct Accumulator {
    var score: Int32 = 0
    var known = false
    var rejected = false
    var visits = 0
    var matches = 0
    var classification: PatternClassification {
      .init(status: rejected ? .rejected : known ? .known : .scored, score: score)
    }
  }
  private static func validInput(_ text: String) -> Bool {
    text.utf8.count <= maximumInputBytes && text.utf8.allSatisfy { $0 >= 32 }
  }
  private static func trimWhitespace(_ text: String) -> String {
    func whitespace(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.value {
      case 9...13, 32, 0x85, 0xa0, 0x1680, 0x2000...0x200a,
           0x2028, 0x2029, 0x202f, 0x205f, 0x3000: return true
      default: return false
      }
    }
    var scalars = Array(text.unicodeScalars)[...]
    while let first = scalars.first, whitespace(first) { scalars = scalars.dropFirst() }
    while let last = scalars.last, whitespace(last) { scalars = scalars.dropLast() }
    return String(String.UnicodeScalarView(scalars))
  }
  private func evaluate(_ text: String, languagePair: String, framing: Framing,
    into result: inout Accumulator) -> Bool {
    if text.isEmpty { return true }
    let lowercase = Array(text.lowercased().utf8)
    guard lowercase.count <= Self.maximumInputBytes else { return false }
    let end: [UInt8] = framing == .complete ? [3] : []
    let passes = [(false, [2] + lowercase + end), (true, [2] + Array(text.utf8) + end)]
    for (sensitive, bytes) in passes {
      for start in bytes.indices {
        var index = 0
        for position in start..<bytes.count {
          guard let next = nodes[index].children[bytes[position]] else { break }
          index = next
          for feature in nodes[index].features {
            result.visits += 1
            guard result.visits <= Self.maximumFeatureVisits else { return false }
            guard feature.caseSensitive == sensitive, feature.languagePair == languagePair else { continue }
            result.matches += 1
            if feature.weight == 0 {
              if feature.knownWord { result.known = true } else { result.rejected = true }
            } else {
              let (sum, overflow) = result.score.addingReportingOverflow(feature.weight)
              guard !overflow else { return false }
              result.score = sum
            }
          }
        }
      }
    }
    return true
  }
}
