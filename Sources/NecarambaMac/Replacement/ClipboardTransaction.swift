import Foundation
import NecarambaCore

/// Caller serializes operations; restoration never overwrites a newer clipboard generation.
public final class ClipboardTransaction {
    private let access: ClipboardAccess
    private let original: PasteboardSnapshot
    private var ownedCount: Int?
    private let maxBytes: Int
    public init(access: ClipboardAccess, maxBytes: Int = 16 * 1024 * 1024) throws {
        self.access = access; self.maxBytes = maxBytes
        original = try access.snapshot(maxBytes: maxBytes)
    }
    public func replace(with items: [PasteboardItem]) throws {
        guard access.changeCount == (ownedCount ?? original.changeCount) else { throw ClipboardError.contextChanged }
        var total = 0
        for item in items { for data in item.representations.values {
            guard data.count <= maxBytes - total else { throw ClipboardError.tooLarge }
            total += data.count
        } }
        ownedCount = try access.write(items)
    }
    @discardableResult public func restoreIfOwned() -> Bool {
        guard let count = ownedCount else { return false }
        ownedCount = nil
        guard access.changeCount == count else { return false }
        do { _ = try access.write(original.items); return true }
        catch { return false }
    }
}
