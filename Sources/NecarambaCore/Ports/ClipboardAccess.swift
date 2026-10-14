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
