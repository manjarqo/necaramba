import AppKit
import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ClipboardSelectionTransactionTests: XCTestCase {
  func testObservedCopyGenerationIsRestoredOnlyWhileUnchanged() throws {
    for interfered in [false, true] {
      let clipboard = FakeClipboard(text: "user")
      let transaction = try ClipboardTransaction(access: clipboard)
      clipboard.simulateCopy("ghbdtn")
      transaction.observeExternalWrite(clipboard.changeCount)
      if interfered { clipboard.simulateCopy("newer") }
      XCTAssertEqual(transaction.restoreIfOwned(), !interfered)
      XCTAssertEqual(clipboard.text, interfered ? "newer" : "user")
    }
  }

  func testPromisedTextIsProvidedOnDemandOnPrivatePasteboard() throws {
    let pasteboard = NSPasteboard(name: .init("necaramba.test." + UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let clipboard = SystemClipboard(pasteboard: pasteboard)
    var provided = 0
    let count = try clipboard.writePromisedText("привет") { provided += 1 }
    XCTAssertEqual(count, pasteboard.changeCount)
    XCTAssertEqual(provided, 0, "Nothing is materialized before a reader asks")
    XCTAssertEqual(pasteboard.string(forType: .string), "привет")
    XCTAssertEqual(provided, 1)
  }
}

@MainActor final class ClipboardSelectionConverterTests: XCTestCase {
  private let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)

  private func run(_ clipboard: FakeClipboard, _ shortcuts: FakeShortcuts,
                   valid: @escaping () -> Bool = { true }) async -> (ClipboardSelectionOutcome, [String]) {
    var clock: UInt64 = 0
    var prepared: [String] = []
    let converter = ClipboardSelectionConverter(clipboard: clipboard, shortcuts: shortcuts,
      now: { clock }, sleep: { clock += $0; await Task.yield() })
    let outcome = await converter.convert(in: token, generation: 1, valid: valid) { copied in
      prepared.append(copied)
      return copied == "ghbdtn vbh" ? ("привет мир", self.token) : nil
    }
    return (outcome, prepared)
  }

  func testNoSelectionLeavesClipboardUntouchedAndNeverPastes() async {
    let clipboard = FakeClipboard(text: "user")
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: nil)
    let (outcome, prepared) = await run(clipboard, shortcuts)
    XCTAssertEqual(outcome, .noSelection)
    XCTAssertEqual(shortcuts.posted, [.copy])
    XCTAssertEqual(clipboard.writes, 0)
    XCTAssertEqual(clipboard.text, "user")
    XCTAssertTrue(prepared.isEmpty)
  }

  func testSingleLineSelectionIsPastedThenOriginalClipboardRestored() async {
    let clipboard = FakeClipboard(text: "user")
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: "ghbdtn vbh")
    let (outcome, prepared) = await run(clipboard, shortcuts)
    XCTAssertEqual(outcome, .dispatched)
    XCTAssertEqual(prepared, ["ghbdtn vbh"])
    XCTAssertEqual(shortcuts.posted, [.copy, .paste])
    XCTAssertEqual(shortcuts.pasted, ["привет мир"])
    XCTAssertEqual(clipboard.text, "user", "Every original representation is restored")
  }

  func testMultiLineOrLineCopySelectionIsRejectedAndRestored() async {
    for copied in ["ghbdtn\nvbh", "whole line\n", String(repeating: "a", count: 1025)] {
      let clipboard = FakeClipboard(text: "user")
      let shortcuts = FakeShortcuts(clipboard: clipboard, selection: copied)
      let (outcome, prepared) = await run(clipboard, shortcuts)
      XCTAssertEqual(outcome, .rejected)
      XCTAssertEqual(shortcuts.posted, [.copy])
      XCTAssertTrue(prepared.isEmpty)
      XCTAssertEqual(clipboard.text, "user")
    }
  }

  func testUnsupportedClipboardContentIsNeverTouched() async {
    let clipboard = FakeClipboard(text: "user")
    clipboard.unsupported = true
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: "ghbdtn vbh")
    let (outcome, _) = await run(clipboard, shortcuts)
    XCTAssertEqual(outcome, .aborted)
    XCTAssertTrue(shortcuts.posted.isEmpty, "No copy is attempted when the clipboard cannot be restored")
  }

  func testUnconsumedPasteIsUncertainButStillRestored() async {
    let clipboard = FakeClipboard(text: "user")
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: "ghbdtn vbh")
    shortcuts.consumesPaste = false
    let (outcome, _) = await run(clipboard, shortcuts)
    XCTAssertEqual(outcome, .uncertain)
    XCTAssertEqual(clipboard.text, "user")
  }

  func testNewerClipboardWriterWinsOverRestoration() async {
    let clipboard = FakeClipboard(text: "user")
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: "ghbdtn vbh")
    shortcuts.afterPaste = { clipboard.simulateCopy("someone else") }
    let (outcome, _) = await run(clipboard, shortcuts)
    XCTAssertEqual(outcome, .dispatched)
    XCTAssertEqual(clipboard.text, "someone else")
  }

  func testInputDuringConversionAbortsBeforePasting() async {
    let clipboard = FakeClipboard(text: "user")
    let shortcuts = FakeShortcuts(clipboard: clipboard, selection: "ghbdtn vbh")
    var stillValid = true
    shortcuts.afterCopy = { stillValid = false }
    let (outcome, _) = await run(clipboard, shortcuts, valid: { stillValid })
    XCTAssertEqual(outcome, .aborted)
    XCTAssertEqual(shortcuts.posted, [.copy])
    XCTAssertEqual(clipboard.text, "user")
  }
}

final class FakeClipboard: ClipboardAccess, PromisedTextWriting {
  private(set) var changeCount = 1
  private var items: [PasteboardItem]
  private var promise: (text: String, provided: () -> Void)?
  var unsupported = false
  private(set) var writes = 0
  init(text: String) { items = [Self.item(text)] }
  static func item(_ text: String) -> PasteboardItem {
    .init(representations: ["public.utf8-plain-text": Data(text.utf8), "public.rtf": Data("{rtf}".utf8)])
  }
  var text: String? {
    if let promise { return promise.text }
    return items.first?.representations["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) }
  }
  func simulateCopy(_ text: String) { promise = nil; items = [Self.item(text)]; changeCount += 1 }
  func readPromised() -> String? {
    guard let promise else { return nil }
    promise.provided()
    return promise.text
  }
  func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
    if unsupported { throw ClipboardError.unsupportedRepresentation }
    guard promise == nil else { throw ClipboardError.unsupportedRepresentation }
    return .init(items: items, changeCount: changeCount)
  }
  func write(_ items: [PasteboardItem]) throws -> Int {
    writes += 1; promise = nil; self.items = items; changeCount += 1; return changeCount
  }
  func writePromisedText(_ text: String, onProvided: @escaping () -> Void) throws -> Int {
    writes += 1; items = []; promise = (text, onProvided); changeCount += 1; return changeCount
  }
}

@MainActor final class FakeShortcuts: CommandShortcutPosting {
  let clipboard: FakeClipboard
  let selection: String?
  var consumesPaste = true
  var afterCopy: () -> Void = {}
  var afterPaste: () -> Void = {}
  private(set) var posted: [CommandShortcut] = []
  private(set) var pasted: [String] = []
  init(clipboard: FakeClipboard, selection: String?) { self.clipboard = clipboard; self.selection = selection }
  func post(_ shortcut: CommandShortcut, in context: ContextToken, generation: UInt64) async -> Bool {
    posted.append(shortcut)
    switch shortcut {
    case .copy:
      if let selection { clipboard.simulateCopy(selection) }
      afterCopy()
    case .paste:
      if consumesPaste, let text = clipboard.readPromised() { pasted.append(text) }
      afterPaste()
    }
    return true
  }
}
