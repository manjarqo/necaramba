import Foundation
import NecarambaCore

public final class SelectionAdapter {
  private let selection: SelectionAccess
  public init(selection: SelectionAccess) { self.selection = selection }
  public func convert(in token: ContextToken, transform: (String) -> String?) -> ApplyResult {
    guard let evidence = selection.selected(in: token), !evidence.text.isEmpty,
      evidence.text.utf8.count <= 1024 * 1024, let converted = transform(evidence.text),
      converted != evidence.text, converted.utf8.count <= 1024 * 1024
    else { return .aborted }
    return selection.replace(evidence, with: converted)
  }
  public func plainPaste(
    in token: ContextToken, clipboard: ClipboardAccess, maxBytes: Int = 1024 * 1024
  ) -> ApplyResult {
    guard let evidence = selection.selected(in: token),
      let snapshot = try? clipboard.snapshot(maxBytes: maxBytes),
      let data = snapshot.items.first?.representations["public.utf8-plain-text"],
      let text = String(data: data, encoding: .utf8), !text.isEmpty, text.utf8.count <= 1024 * 1024
    else { return .aborted }
    // Direct AX insertion leaves every pasteboard representation and generation untouched.
    guard clipboard.changeCount == snapshot.changeCount else { return .aborted }
    return selection.replace(evidence, with: text)
  }
}
