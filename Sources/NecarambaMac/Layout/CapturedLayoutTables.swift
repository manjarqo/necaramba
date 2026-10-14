import Foundation
import NecarambaCore

public protocol LayoutTableCapturing: AnyObject { func captureTables() -> CapturedLayoutTables }
public protocol RuleEngineBuilding: AnyObject {
  func build(snapshot: RuleSnapshot, physicalMappings: [PhysicalLayoutMapping]) -> LinguisticEngine
}
public final class RuleEngineBuilder: RuleEngineBuilding {
  public init() {}
  public func build(snapshot: RuleSnapshot, physicalMappings: [PhysicalLayoutMapping])
    -> LinguisticEngine
  { .init(snapshot: snapshot, physicalMappings: physicalMappings) }
}
/// Immutable translations. No Carbon/TIS handle escapes main-thread capture.
public struct CapturedLayoutTables: Sendable {
  public struct Layout: Sendable {
    public let id: LayoutID
    public let entries: [PhysicalLayoutMapping.Entry]
    public init(id: LayoutID, entries: [PhysicalLayoutMapping.Entry]) {
      self.id = id
      self.entries = entries
    }
  }
  public let layouts: [Layout]
  public init(layouts: [Layout]) { self.layouts = layouts }
  /// Explicit conversion uses observed physical pairs, independently of classifier compatibility.
  public func manualMapping(source sourceID: LayoutID, target targetID: LayoutID) -> LayoutMapping? {
    guard sourceID != targetID,
      let source = layouts.first(where: { $0.id == sourceID }),
      let target = layouts.first(where: { $0.id == targetID }) else { return nil }
    let targetEntries = Dictionary(grouping: target.entries) {
      Key(code: $0.keyCode, modifiers: $0.modifiers)
    }
    var candidates: [String: Set<String>] = [:]
    for entry in source.entries where entry.text.count == 1 {
      guard entry.modifiers.isSubset(of: [.shift, .capsLock]) else { continue }
      for replacement in targetEntries[Key(code: entry.keyCode, modifiers: entry.modifiers)] ?? []
      where replacement.text.count == 1 {
        candidates[entry.text, default: []].insert(replacement.text)
      }
    }
    var pairs: [String: String] = [:]
    for (text, replacements) in candidates {
      // An ambiguous character stays unchanged, including uppercase: no inferred fallback.
      pairs[text] = replacements.count == 1 ? replacements.first! : text
    }
    guard pairs.contains(where: { $0.key != $0.value }) else { return nil }
    return .init(source: sourceID, target: targetID, pairs: pairs)
  }
  /// Reconstruct both sides from physical events; session-tap Unicode may describe another layout.
  public func manualConversion(_ word: BufferedWord, target targetID: LayoutID)
    -> (word: BufferedWord, replacement: String)?
  {
    guard let source = layouts.first(where: { $0.id == word.layout }),
      let target = layouts.first(where: { $0.id == targetID }), !word.events.isEmpty else { return nil }
    var events: [InputEvent] = []
    for event in word.events {
      guard event.context == word.context, event.layout == word.layout,
        event.origin == .physical, event.kind == .down,
        event.modifiers.isSubset(of: [.shift, .capsLock]) else { return nil }
      let matches = source.entries.filter { $0.keyCode == event.keyCode && $0.modifiers == event.modifiers }
      guard matches.count == 1, let text = matches.first?.text, text.count == 1 else { return nil }
      events.append(.init(kind: event.kind, keyCode: event.keyCode, modifiers: event.modifiers,
        timestampNanos: event.timestampNanos, layout: event.layout, context: event.context,
        origin: event.origin, text: text, isRepeat: event.isRepeat))
    }
    guard let replacement = LayoutConverter.convert(keys: events, to: targetID,
      physicalMappings: [.init(source: word.layout, target: targetID, entries: target.entries)]),
      replacement.count == events.count else { return nil }
    return (.init(text: events.compactMap(\.text).joined(), events: events,
      context: word.context, layout: word.layout, delimiter: word.delimiter), replacement)
  }
  public func resolve(_ snapshot: RuleSnapshot) -> RuleSnapshot {
    let ids = Set(layouts.map(\.id))
    let mappings = snapshot.mappings.compactMap { mapping -> LayoutMapping? in
      guard !mapping.pairs.isEmpty else { return nil }
      var matches: [LayoutMapping] = []
      for source in layouts {
        for target in layouts where target.id != source.id {
          if ids.contains(mapping.source) && source.id != mapping.source { continue }
          if ids.contains(mapping.target) && target.id != mapping.target { continue }
          let proven = mapping.pairs.allSatisfy { original, replacement in
            source.entries.contains { entry in
              entry.modifiers.isEmpty && entry.text == original
                && target.entries.contains {
                  $0.keyCode == entry.keyCode && $0.modifiers.isEmpty && $0.text == replacement
                }
            }
          }
          if proven {
            matches.append(.init(source: source.id, target: target.id, pairs: mapping.pairs))
          }
        }
      }
      return matches.count == 1 ? matches[0] : nil
    }
    return .init(
      modelVersion: snapshot.modelVersion, lexicon: snapshot.lexicon, typos: snapshot.typos,
      yoRules: snapshot.yoRules, protectedTokens: snapshot.protectedTokens, mappings: mappings)
  }
  public func physicalMappings(for snapshot: RuleSnapshot) -> [PhysicalLayoutMapping] {
    snapshot.mappings.compactMap { mapping in
      guard let source = layouts.first(where: { $0.id == mapping.source }),
        let target = layouts.first(where: { $0.id == mapping.target })
      else { return nil }
      let keys = Set(source.entries.map { Key(code: $0.keyCode, modifiers: $0.modifiers) })
      let entries = target.entries.filter {
        keys.contains(.init(code: $0.keyCode, modifiers: $0.modifiers))
      }
      return entries.isEmpty
        ? nil : .init(source: mapping.source, target: mapping.target, entries: entries)
    }
  }
  private struct Key: Hashable {
    let code: UInt16
    let modifiers: Set<Modifier>
  }
}
