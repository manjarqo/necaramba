import Foundation
import NecarambaCore

public enum ClipboardSelectionOutcome: Equatable, Sendable {
  /// Copy changed nothing: the field has no selection; the clipboard was not written.
  case noSelection
  /// The copied text is not a single bounded line (for example an editor's line copy).
  case rejected
  case aborted
  /// Paste was posted and its data requested; acceptance by the field is unverified.
  case dispatched
  /// Paste was posted but no reader requested its data before the deadline.
  case uncertain
}

public protocol ClipboardSelectionConverting: AnyObject {
  @MainActor func convert(in token: ContextToken, generation: UInt64, valid: @escaping () -> Bool,
    prepare: (String) async -> (text: String, context: ContextToken)?) async -> ClipboardSelectionOutcome
}

/// Converts a selection that Accessibility cannot read through Copy and Paste.
/// Every original pasteboard representation is restored unless a newer writer
/// replaced it; content that cannot be restored is never touched.
@MainActor public final class ClipboardSelectionConverter: ClipboardSelectionConverting {
  private let clipboard: ClipboardAccess & PromisedTextWriting
  private let shortcuts: CommandShortcutPosting
  private let now: () -> UInt64
  private let sleep: (UInt64) async -> Void
  static let copyTimeoutNanos: UInt64 = 250_000_000
  // Clipboard managers may also request promised data; keep it for a short hold.
  static let minimumHoldNanos: UInt64 = 150_000_000
  static let pasteTimeoutNanos: UInt64 = 1_000_000_000
  static let pollNanos: UInt64 = 10_000_000

  public init(clipboard: ClipboardAccess & PromisedTextWriting, shortcuts: CommandShortcutPosting,
              now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
              sleep: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }) {
    self.clipboard = clipboard; self.shortcuts = shortcuts; self.now = now; self.sleep = sleep
  }

  public func convert(in token: ContextToken, generation: UInt64, valid: @escaping () -> Bool,
                      prepare: (String) async -> (text: String, context: ContextToken)?) async -> ClipboardSelectionOutcome {
    guard valid(), let transaction = try? ClipboardTransaction(access: clipboard, maxBytes: 1024 * 1024)
    else { return .aborted }
    let before = clipboard.changeCount
    guard await shortcuts.post(.copy, in: token, generation: generation) else { return .aborted }
    let copyStarted = now()
    while clipboard.changeCount == before, now() - copyStarted < Self.copyTimeoutNanos, valid() {
      await sleep(Self.pollNanos)
    }
    guard clipboard.changeCount != before else { return valid() ? .noSelection : .aborted }
    transaction.observeExternalWrite(clipboard.changeCount)
    guard let copied = try? clipboard.snapshot(maxBytes: 1024 * 1024),
      let data = copied.items.first?.representations["public.utf8-plain-text"],
      let text = String(data: data, encoding: .utf8)
    else { transaction.restoreIfOwned(); return .rejected }
    guard !text.isEmpty, text.count <= 1024, !text.contains(where: { $0 == "\n" || $0 == "\r" })
    else { transaction.restoreIfOwned(); return .rejected }
    // Preparation may select the target layout; paste uses the refreshed context.
    guard valid(), let prepared = await prepare(text), prepared.text != text, valid()
    else { transaction.restoreIfOwned(); return .aborted }
    var provided = false
    do { try transaction.replacePromised(text: prepared.text) { provided = true } }
    catch { transaction.restoreIfOwned(); return .aborted }
    guard valid(), await shortcuts.post(.paste, in: prepared.context, generation: generation)
    else { transaction.restoreIfOwned(); return .aborted }
    let pasted = now()
    while !(provided && now() - pasted >= Self.minimumHoldNanos), now() - pasted < Self.pasteTimeoutNanos {
      await sleep(Self.pollNanos)
    }
    transaction.restoreIfOwned()
    return provided ? .dispatched : .uncertain
  }
}
