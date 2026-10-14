import Foundation

public struct BufferedWord: Sendable, Equatable {
    public let text: String
    public let events: [InputEvent]
    public let context: ContextToken
    public let layout: LayoutID
    public let delimiter: String
    public init(text: String, events: [InputEvent], context: ContextToken, layout: LayoutID, delimiter: String) {
        self.text = text; self.events = events; self.context = context; self.layout = layout; self.delimiter = delimiter
    }
}

public struct WordBuffer: Sendable {
    private let maxGraphemes: Int
    private let maxUTF16: Int
    private var events: [InputEvent] = []
    private var text = ""
    private var untrusted = false
    public init(maxGraphemes: Int = 128, maxUTF16: Int = 512) {
        self.maxGraphemes = max(0, maxGraphemes); self.maxUTF16 = max(0, maxUTF16)
    }
    public mutating func invalidate(_ reason: InvalidationReason) { clear(); untrusted = true }
    private mutating func clear() { text = ""; events.removeAll(keepingCapacity: false) }
    public mutating func consume(_ event: InputEvent) -> BufferedWord? {
        if event.origin == .ours { return nil }
        guard event.origin == .physical else { invalidate(.unknownInput); return nil }
        if let first = events.first, first.context != event.context || first.layout != event.layout {
            invalidate(.focusChanged)
        }
        guard !event.modifiers.contains(.command), !event.modifiers.contains(.control) else {
            invalidate(.unknownInput); return nil
        }
        guard event.kind == .down else { return nil }
        guard let value = event.text, value.count == 1 else { invalidate(.unknownInput); return nil }
        if untrusted {
            if [" ", "\n", "\r", "\t"].contains(value) { clear(); untrusted = false }
            return nil
        }
        if Self.isBoundary(value) {
            defer { clear(); untrusted = false }
            guard !untrusted, let first = events.first else { return nil }
            return BufferedWord(text: text, events: events, context: first.context, layout: first.layout, delimiter: value)
        }
        guard !untrusted, value.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            invalidate(.unknownInput); return nil
        }
        let candidate = text + value
        guard candidate.count <= maxGraphemes, candidate.utf16.count <= maxUTF16 else {
            invalidate(.unknownInput); return nil
        }
        text = candidate; events.append(event)
        return nil
    }
    /// Adapter must first prove that the editor deleted exactly the final tracked grapheme.
    @discardableResult public mutating func consumeConfirmedBackspace(_ event: InputEvent) -> Bool {
        guard !untrusted, event.kind == .down, event.keyCode == 51, event.origin == .physical,
              event.modifiers.isSubset(of: [.shift, .capsLock]), let first = events.first,
              event.context == first.context, event.layout == first.layout, !text.isEmpty else {
            invalidate(.unknownInput); return false
        }
        text.removeLast(); events.removeLast()
        return true
    }
    private static func isBoundary(_ value: String) -> Bool {
        [" ", "\n", "\r", "\t", "!", "?"].contains(value)
    }
}
