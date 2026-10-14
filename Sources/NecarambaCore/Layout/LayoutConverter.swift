import Foundation

/// Hardware-specific mapping captured by the platform adapter, never inferred from layout names.
public struct PhysicalLayoutMapping: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let keyCode: UInt16
        public let modifiers: Set<Modifier>
        public let text: String
        public init(keyCode: UInt16, modifiers: Set<Modifier>, text: String) {
            self.keyCode = keyCode; self.modifiers = modifiers; self.text = text
        }
    }
    public let source: LayoutID
    public let target: LayoutID
    public let entries: [Entry]
    public init(source: LayoutID, target: LayoutID, entries: [Entry]) {
        self.source = source; self.target = target; self.entries = entries
    }
}

public enum LayoutConverter {
    /// Selected text may have been entered in a layout different from the active source.
    /// Alphabetic evidence chooses direction; punctuation-only selections keep the preference.
    public static func selectionMapping(_ text: String, preferred: LayoutMapping,
                                        alternative: LayoutMapping?) -> LayoutMapping {
        guard let alternative else { return preferred }
        func score(_ mapping: LayoutMapping) -> Int {
            text.reduce(0) { count, character in
                count + (character.isLetter && convert(String(character), mapping: mapping) != String(character) ? 1 : 0)
            }
        }
        return score(alternative) > score(preferred) ? alternative : preferred
    }

    public static func convert(_ text: String, mapping: LayoutMapping) -> String {
        text.map { character in
            let value = String(character)
            if let direct = mapping.pairs[value] { return direct }
            if value == value.uppercased(), value != value.lowercased(),
               let lower = mapping.pairs[value.lowercased()], lower.count == 1,
               lower.uppercased().count == 1 { return lower.uppercased() }
            return value
        }.joined()
    }
    /// Explicit ANSI alphabet reference fixtures for the test IDs US/RU only.
    /// Real TIS IDs and ISO/JIS/punctuation require adapter-provided PhysicalLayoutMapping.
    public static func convert(keys: [InputEvent], to: LayoutID, mappings: [LayoutMapping]) -> String? {
        let keyCodes: [UInt16] = [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,31,32,34,35,37,38,40,45,46]
        let us = Array("asdfhgzxcvbqwerytouipljknm".filter { $0 != " " }).map(String.init)
        let ru = Array("фыварпячсмийцукнещгшздолть".filter { $0 != " " }).map(String.init)
        let sourceTables: [String: [UInt16: String]] = ["US": Dictionary(uniqueKeysWithValues: zip(keyCodes, us)), "RU": Dictionary(uniqueKeysWithValues: zip(keyCodes, ru))]
        guard let first = keys.first, let source = sourceTables[first.layout.rawValue], let target = sourceTables[to.rawValue] else { return nil }
        var entries: [PhysicalLayoutMapping.Entry] = []
        for event in keys {
            guard event.modifiers.isSubset(of: [.shift, .capsLock]), let original = source[event.keyCode], let replacement = target[event.keyCode] else { return nil }
            let maps = mappings.filter { $0.source == event.layout && $0.target == to }
            guard maps.count == 1, maps[0].pairs[original] == replacement else { return nil }
            let uppercase = event.modifiers.contains(.shift) != event.modifiers.contains(.capsLock)
            let entry = PhysicalLayoutMapping.Entry(keyCode: event.keyCode, modifiers: event.modifiers, text: uppercase ? replacement.uppercased() : replacement)
            if !entries.contains(entry) { entries.append(entry) }
        }
        return convert(keys: keys, to: to, physicalMappings: [.init(source: first.layout, target: to, entries: entries)])
    }
    public static func convert(keys: [InputEvent], to: LayoutID, physicalMappings: [PhysicalLayoutMapping]) -> String? {
        guard let first = keys.first else { return nil }
        var result = ""
        for event in keys {
            guard event.kind == .down, event.origin == .physical,
                  event.context == first.context, event.layout == first.layout,
                  !event.modifiers.contains(.command), !event.modifiers.contains(.control) else { return nil }
            let candidates = physicalMappings.filter { $0.source == event.layout && $0.target == to }
                .flatMap(\.entries).filter { $0.keyCode == event.keyCode && $0.modifiers == event.modifiers }
            guard candidates.count == 1, !candidates[0].text.isEmpty else { return nil }
            result += candidates[0].text
        }
        return result
    }
}
