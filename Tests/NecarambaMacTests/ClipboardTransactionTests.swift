import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ClipboardTransactionTests: XCTestCase {
    func testUserCopyWinsOverRestoration() throws {
        let board = MemoryClipboard("before")
        let transaction = try ClipboardTransaction(access: board, maxBytes: 100)
        try transaction.replace(with: [plain("temporary")])
        _ = try board.write([plain("user-new")])
        XCTAssertFalse(transaction.restoreIfOwned())
        XCTAssertEqual(board.items, [plain("user-new")])
    }
    func testRestoresAllRepresentationsOnlyOnce() throws {
        let board = MemoryClipboard("before")
        board.items.append(PasteboardItem(representations: ["public.png": Data([1,2,3])]))
        let original = board.items
        let transaction = try ClipboardTransaction(access: board, maxBytes: 100)
        try transaction.replace(with: [plain("temporary")])
        XCTAssertTrue(transaction.restoreIfOwned())
        XCTAssertEqual(board.items, original)
        let count = board.changeCount
        XCTAssertFalse(transaction.restoreIfOwned())
        XCTAssertEqual(board.changeCount, count)
    }
    func testConcurrentCopyBeforeReplacementIsPreserved() throws {
        let board = MemoryClipboard("before")
        let transaction = try ClipboardTransaction(access: board, maxBytes: 100)
        _ = try board.write([plain("new")])
        XCTAssertThrowsError(try transaction.replace(with: [plain("temporary")]))
        XCTAssertEqual(board.items, [plain("new")])
    }
    func testOversizeDoesNotWrite() {
        let board = MemoryClipboard("too long")
        XCTAssertThrowsError(try ClipboardTransaction(access: board, maxBytes: 2))
        XCTAssertEqual(board.changeCount, 0)
    }
}
private func plain(_ string: String) -> PasteboardItem {
    PasteboardItem(representations: ["public.utf8-plain-text": Data(string.utf8)])
}
private final class MemoryClipboard: ClipboardAccess {
    var items: [PasteboardItem]
    var changeCount = 0
    init(_ text: String) { items = [plain(text)] }
    func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
        let size = items.flatMap { $0.representations.values }.reduce(0) { $0 + $1.count }
        guard size <= maxBytes else { throw ClipboardError.tooLarge }
        return PasteboardSnapshot(items: items, changeCount: changeCount)
    }
    func write(_ items: [PasteboardItem]) throws -> Int { self.items = items; changeCount += 1; return changeCount }
}
