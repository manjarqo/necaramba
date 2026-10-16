import Foundation

public struct PasteboardItem: Equatable, Sendable {
    public let representations: [String: Data]
    public init(representations: [String: Data]) { self.representations = representations }
}
public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [PasteboardItem]
    public let changeCount: Int
    public init(items: [PasteboardItem], changeCount: Int) { self.items = items; self.changeCount = changeCount }
}
public enum ClipboardError: Error, Equatable {
    case unsupportedRepresentation, tooLarge, noText, copyTimeout, contextChanged, writeFailed
}
public protocol ClipboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot(maxBytes: Int) throws -> PasteboardSnapshot
    func write(_ items: [PasteboardItem]) throws -> Int
}
/// Writes text that the pasteboard materializes only when a reader asks for it.
/// `onProvided` runs on the providing thread each time data is requested.
public protocol PromisedTextWriting: AnyObject {
    func writePromisedText(_ text: String, onProvided: @escaping () -> Void) throws -> Int
}
public enum CommandShortcut: Sendable, Equatable { case copy, paste }
/// Posts an application command shortcut to the field proven by `context`.
public protocol CommandShortcutPosting: AnyObject {
    @MainActor func post(_ shortcut: CommandShortcut, in context: ContextToken, generation: UInt64) async -> Bool
}
