public struct PatternAutocorrectRule: Sendable {
  public let pattern: String
  public let rewrite: PatternRewriteRule
  public let caseSensitive: Bool
  public let isYofikator: Bool
  public init(pattern: String, rewrite: PatternRewriteRule,
    caseSensitive: Bool = false, isYofikator: Bool = false) {
    self.pattern = pattern; self.rewrite = rewrite
    self.caseSensitive = caseSensitive; self.isYofikator = isYofikator
  }
}
public struct PatternAutocorrection: Equatable, Sendable {
  public enum Status: Sendable { case unchanged, corrected, unsupported }
  public let status: Status
  public let replacement: String?
  public let appliedRuleCount: Int
  public let appliedTypo: Bool
  public let appliedYo: Bool
  public init(status: Status, replacement: String?, appliedRuleCount: Int,
    appliedTypo: Bool = false, appliedYo: Bool = false) {
    self.status = status; self.replacement = replacement; self.appliedRuleCount = appliedRuleCount
    self.appliedTypo = appliedTypo; self.appliedYo = appliedYo
  }
}
/// Dataset-independent UTF-8 matcher and Unicode-scalar rewrite interpreter.
/// Uses Swift Unicode casing tables; no normalization or locale-aware folding.
/// Literal TAB output is text, not permission to dispatch a keyboard event.
/// Delivery adapters must independently validate any replacement before editing.
public struct PatternAutocorrector: Sendable {
  public enum CompilationError: Error { case malformedRule, resourceLimit }
  private struct Node: Sendable {
    var children: [UInt8: Int] = [:]
    var rules: [Int] = []
  }
  private struct CompiledRule: Sendable {
    let material: [Unicode.Scalar]
    let replacement: String
    let caseSensitive: Bool
    let yo: Bool
  }
  private let nodes: [Node]
  private let rules: [CompiledRule]
  private static let unsupported = PatternAutocorrection(status: .unsupported, replacement: nil, appliedRuleCount: 0)
  private static let unchanged = PatternAutocorrection(status: .unchanged, replacement: nil, appliedRuleCount: 0)
  private static let workLimit = 2_000_000

  public init(rules: [PatternAutocorrectRule]) throws {
    guard rules.count <= 100_000 else { throw CompilationError.resourceLimit }
    var nodes = [Node()]
    var compiled: [CompiledRule] = []
    for rule in rules {
      guard !rule.pattern.isEmpty, rule.pattern.utf8.count <= 512 else { throw CompilationError.malformedRule }
      let bytes = Array(rule.pattern.utf8)
      guard bytes.enumerated().allSatisfy({ index, byte in
        byte >= 32 || (byte == 2 && index == 0) || (byte == 3 && index == bytes.count - 1)
      }) else { throw CompilationError.malformedRule }
      let material = Array(rule.pattern.unicodeScalars.filter { $0.value != 2 && $0.value != 3 })
      guard !material.isEmpty,
        let replacement = rule.rewrite.apply(to: String(String.UnicodeScalarView(material))),
        replacement.utf8.allSatisfy({ $0 >= 32 || $0 == 9 })
      else { throw CompilationError.malformedRule }
      var index = 0
      for byte in bytes {
        if let next = nodes[index].children[byte] { index = next }
        else {
          guard nodes.count < 2_000_000 else { throw CompilationError.resourceLimit }
          let next = nodes.count
          nodes.append(Node()); nodes[index].children[byte] = next; index = next
        }
      }
      nodes[index].rules.append(compiled.count)
      compiled.append(.init(material: material, replacement: replacement,
        caseSensitive: rule.caseSensitive, yo: rule.isYofikator))
    }
    self.nodes = nodes; self.rules = compiled
  }

  /// Primary framing uses the original delimiter; forceComplete is an explicit
  /// caller override. Fallback runs only for an empty match list, before toggles.
  /// Current text retains original whitespace and punctuation during rewriting.
  public func correct(_ input: String, typoEnabled: Bool = true, yoEnabled: Bool = true,
    forceComplete: Bool = false) -> PatternAutocorrection {
    guard input.utf8.count <= 512 else { return Self.unsupported }
    let trimmed = Self.trimWhitespace(input)
    guard trimmed.utf8.allSatisfy({ $0 >= 32 }) else { return Self.unsupported }
    if !typoEnabled && !yoEnabled { return Self.unchanged }
    let complete = forceComplete || input.unicodeScalars.last.map { [9, 10, 13, 32, 45].contains($0.value) } == true
    var work = 0
    guard var matches = lookup(trimmed, complete: complete, work: &work) else { return Self.unsupported }
    if matches.isEmpty {
      var cleaned = Array(trimmed.unicodeScalars)[...]
      if complete {
        while let last = cleaned.last, [33, 41, 44, 45, 46].contains(last.value) { cleaned = cleaned.dropLast() }
        while let first = cleaned.first, first.value == 45 || first.value == 40 { cleaned = cleaned.dropFirst() }
      }
      let fallback = Self.trimWhitespace(String(String.UnicodeScalarView(cleaned)))
      guard let found = lookup(fallback, complete: complete, work: &work) else { return Self.unsupported }
      matches = found
    }
    var current = input
    var applied = 0
    var appliedTypo = false
    var appliedYo = false
    for id in matches {
      let rule = rules[id]
      work += current.utf8.count + rule.replacement.utf8.count
      guard work <= Self.workLimit else { return Self.unsupported }
      let sourceSet = Set(current.unicodeScalars.flatMap { String($0).lowercased().unicodeScalars })
      let novel = rule.replacement.unicodeScalars.flatMap { String($0).lowercased().unicodeScalars }
        .filter { !sourceSet.contains($0) }
      let effectiveYo = rule.yo || (novel.count == 1 && novel.first?.value == 0x451)
      guard effectiveYo ? yoEnabled : typoEnabled else { continue }
      guard let changed = replace(current, rule: rule, work: &work) else { return Self.unsupported }
      if Array(changed.utf8) != Array(current.utf8) {
        applied += 1; current = changed
        if effectiveYo { appliedYo = true } else { appliedTypo = true }
      }
    }
    guard Array(current.utf8) != Array(input.utf8) else {
      return .init(status: .unchanged, replacement: nil, appliedRuleCount: applied, appliedTypo: appliedTypo, appliedYo: appliedYo)
    }
    return .init(status: .corrected, replacement: current, appliedRuleCount: applied, appliedTypo: appliedTypo, appliedYo: appliedYo)
  }

  private func lookup(_ text: String, complete: Bool, work: inout Int) -> [Int]? {
    let framed = "\u{2}" + text + (complete ? "\u{3}" : "")
    var matches: [Int] = []
    func scan(_ bytes: [UInt8], deduplicating: Bool, seen: inout Set<Int>) -> Bool {
      for start in bytes.indices {
        var node = 0
        for position in start..<bytes.count {
          work += 1
          guard work <= Self.workLimit else { return false }
          guard let next = nodes[node].children[bytes[position]] else { break }
          node = next
          for id in nodes[node].rules {
            work += 1
            guard work <= Self.workLimit, matches.count < 100_000 else { return false }
            if !deduplicating || !seen.contains(id) { matches.append(id); seen.insert(id) }
          }
        }
      }
      return true
    }
    var seen: Set<Int> = []
    guard scan(Array(framed.utf8), deduplicating: false, seen: &seen) else { return nil }
    if framed.unicodeScalars.contains(where: { $0.properties.isUppercase }) {
      let lower = framed.lowercased()
      guard lower.utf8.count <= 514, scan(Array(lower.utf8), deduplicating: true, seen: &seen) else { return nil }
    }
    return matches
  }

  private func replace(_ text: String, rule: CompiledRule, work: inout Int) -> String? {
    let source = Array(text.unicodeScalars)
    let replacement = Array(rule.replacement.unicodeScalars)
    var output = String.UnicodeScalarView()
    var outputBytes = 0
    var cursor = 0
    func append(_ value: String) -> Bool {
      outputBytes += value.utf8.count
      guard outputBytes <= 512 else { return false }
      output.append(contentsOf: value.unicodeScalars)
      return true
    }
    while cursor < source.count {
      var matches = cursor + rule.material.count <= source.count
      if matches {
        for offset in rule.material.indices {
          work += 1
          guard work <= Self.workLimit else { return nil }
          let a = source[cursor + offset], b = rule.material[offset]
          let equal = a == b || (!rule.caseSensitive &&
            Array(String(a).lowercased().unicodeScalars) == Array(String(b).lowercased().unicodeScalars))
          if !equal { matches = false; break }
        }
      }
      if !matches {
        guard append(String(source[cursor])) else { return nil }
        cursor += 1
        continue
      }
      let span = source[cursor..<cursor + rule.material.count]
      let majority = span.filter { $0.properties.isUppercase }.count * 2 > span.count
      for (offset, scalar) in replacement.enumerated() {
        let uppercase = !rule.caseSensitive && (majority ||
          (offset < span.count && source[cursor + offset].properties.isUppercase))
        guard append(uppercase ? String(scalar).uppercased() : String(scalar)) else { return nil }
      }
      cursor += rule.material.count
    }
    return String(output)
  }

  private static func trimWhitespace(_ text: String) -> String {
    func whitespace(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.value {
      case 9...13, 32, 0x85, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000: return true
      default: return false
      }
    }
    var scalars = Array(text.unicodeScalars)[...]
    while let first = scalars.first, whitespace(first) { scalars = scalars.dropFirst() }
    while let last = scalars.last, whitespace(last) { scalars = scalars.dropLast() }
    return String(String.UnicodeScalarView(scalars))
  }
}
