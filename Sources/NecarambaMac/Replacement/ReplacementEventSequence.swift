import Foundation

/// The workaround is scoped to exact application identities, never engine substrings.
/// Selection replacement inserts directly and must never emit a preparatory key.
public enum ReplacementEventSequence {
  /// Decide before constructing or posting any event; oversized text retains Unicode transport.
  public static func canReplayPhysical(keyCount: Int, deleteCount: Int, temporarySpace: Bool) -> Bool {
    guard keyCount > 0, keyCount <= 256, deleteCount >= 0, deleteCount <= 128 else { return false }
    return keyCount + deleteCount + (temporarySpace ? 2 : 0) <= 256
  }

  public static func usesTemporarySpace(bundleID: String, selected: Bool) -> Bool {
    guard !selected else { return false }
    return ApplicationProfileRegistry.shared.profile(for: bundleID)?.temporarySpace == true
  }

  public static func deletionCount(originalCount: Int, bundleID: String, selected: Bool) -> Int {
    guard !selected else { return 0 }
    return originalCount + (usesTemporarySpace(bundleID: bundleID, selected: false) ? 1 : 0)
  }
}

/// Enumerates possible observations of a single posted batch, not evidence that it ran.
/// Callers must independently verify focus, generation and exact final value/range.
/// AX value and range histories can advance independently because reads may be torn.
public struct ReplacementObservationProgress {
  private struct State {
    let middle: String
    let range: NSRange
    let step: Int
  }
  private let prefix: String
  private let suffix: String
  private let states: [State]

  public init?(beforeValue: String, beforeSelection: NSRange, replacementRange: NSRange,
    original: String, replacement: String, bundleID: String, selected: Bool
  ) {
    guard beforeValue.utf8.count <= 1024 * 1024,
      (selected || !original.isEmpty), original.count <= 128, original.utf16.count <= 512,
      !replacement.isEmpty,
      (selected ? replacement.utf16.count <= 1024 :
        replacement.count <= 128 && replacement.utf16.count <= 512),
      let edit = Range(replacementRange, in: beforeValue),
      Range(beforeSelection, in: beforeValue) != nil,
      String(beforeValue[edit]) == original else { return nil }
    prefix = String(beforeValue[..<edit.lowerBound])
    suffix = String(beforeValue[edit.upperBound...])
    let offset = prefix.utf16.count
    var result = [State(middle: original, range: beforeSelection, step: 0)]
    var step = 0
    if !selected {
      if ReplacementEventSequence.usesTemporarySpace(bundleID: bundleID, selected: false) {
        step += 1
        result.append(State(middle: original + " ",
          range: NSRange(location: offset + original.utf16.count + 1, length: 0), step: step))
        step += 1
        result.append(State(middle: original,
          range: NSRange(location: offset + original.utf16.count, length: 0), step: step))
      }
      var remainder = original
      while !remainder.isEmpty {
        remainder.removeLast()
        step += 1
        result.append(State(middle: remainder,
          range: NSRange(location: offset + remainder.utf16.count, length: 0), step: step))
      }
    }
    // An insertion may expose an empty prefix before its first Unicode scalar.
    step += 1
    result.append(State(middle: "", range: NSRange(location: offset, length: 0), step: step))
    var inserted = ""
    for scalar in replacement.unicodeScalars {
      inserted.unicodeScalars.append(scalar)
      step += 1
      result.append(State(middle: inserted,
        range: NSRange(location: offset + inserted.utf16.count, length: 0), step: step))
    }
    states = result
  }

  public func valueProgress(_ value: String, minimum: Int) -> Int? {
    guard value.utf8.count <= 1024 * 1024 else { return nil }
    let length = value.utf16.count
    let prefixLength = prefix.utf16.count
    let suffixLength = suffix.utf16.count
    guard length >= prefixLength + suffixLength else { return nil }
    let source = value as NSString
    guard source.substring(to: prefixLength) == prefix,
      source.substring(from: length - suffixLength) == suffix else { return nil }
    let middle = source.substring(with: NSRange(location: prefixLength,
      length: length - prefixLength - suffixLength))
    return states.first { $0.step >= minimum && $0.middle == middle }?.step
  }

  public func rangeProgress(_ range: NSRange, minimum: Int) -> Int? {
    states.first { $0.step >= minimum && $0.range == range }?.step
  }
}
