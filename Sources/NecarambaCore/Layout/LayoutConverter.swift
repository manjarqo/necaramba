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
    /// Character pairs do not establish a trusted physical mapping.
    public static func convert(keys: [InputEvent], to: LayoutID, mappings: [LayoutMapping]) -> String? { nil }
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
