import AppKit
import NecarambaCore

public final class SystemClipboard: ClipboardAccess {
    private let pasteboard: NSPasteboard
    private static let supported = Set([
        "public.utf8-plain-text", "public.utf16-external-plain-text", "public.html",
        "public.rtf", "com.apple.flat-rtfd", "public.png", "public.tiff", "public.jpeg",
        "com.adobe.pdf", "public.url", "public.file-url"
    ])
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    public var changeCount: Int { pasteboard.changeCount }
    public func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
        let generation = changeCount
        var items: [PasteboardItem] = []
        var total = 0
        for item in pasteboard.pasteboardItems ?? [] {
            // Unknown/lazy promised content is rejected before any clear/write.
            guard item.types.allSatisfy({ Self.supported.contains($0.rawValue) }) else { throw ClipboardError.unsupportedRepresentation }
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw ClipboardError.unsupportedRepresentation }
                guard data.count <= maxBytes - total else { throw ClipboardError.tooLarge }
                total += data.count; representations[type.rawValue] = data
            }
            items.append(PasteboardItem(representations: representations))
        }
        guard generation == changeCount else { throw ClipboardError.contextChanged }
        return PasteboardSnapshot(items: items, changeCount: generation)
    }
    public func write(_ items: [PasteboardItem]) throws -> Int {
        let objects: [NSPasteboardItem] = try items.map { value in
            let item = NSPasteboardItem()
            for (type, data) in value.representations {
                guard item.setData(data, forType: NSPasteboard.PasteboardType(type)) else { throw ClipboardError.writeFailed }
            }
            return item
        }
        pasteboard.clearContents()
        if !objects.isEmpty && !pasteboard.writeObjects(objects) { throw ClipboardError.writeFailed }
        return changeCount
    }
}
