import AppKit
import ApplicationServices
import Carbon
import NecarambaCore

/// Reads proof outside the tap. Mutation is delegated to a bounded tap-executor key batch.
/// No AX setter or whole-value rewrite exists in this adapter.
public final class AXSelectionAdapter: SelectionAccess {
  public typealias Mutation = (SelectionEvidence, String, Bool, () -> Bool) -> ApplyResult
  public var execute: Mutation?
  public var inputGeneration: (() -> UInt64)?
  private let context: ContextAccess
  private let qualifies: (String, String) -> Bool
  private var retained: (id: UUID, element: AXUIElement)?
  public init(context: ContextAccess, qualifies: @escaping (String, String) -> Bool) {
    self.context = context
    self.qualifies = qualifies
  }
  private struct State {
    let element: AXUIElement
    let value: String
    let range: NSRange
  }
  private func state(_ token: ContextToken) -> State? {
    precondition(Thread.isMainThread)
    guard !IsSecureEventInputEnabled(), context.isSafe(token),
      NSWorkspace.shared.frontmostApplication?.processIdentifier == token.pid
    else { return nil }
    let app = AXUIElementCreateApplication(token.pid)
    AXUIElementSetMessagingTimeout(app, 0.05)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    let element = unsafeBitCast(focused, to: AXUIElement.self)
    func attribute(_ name: String) -> CFTypeRef? {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
      }
      return value
    }
    guard let role = attribute(kAXRoleAttribute) as? String, qualifies(token.bundleID, role),
      attribute(kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
      let text = attribute(kAXValueAttribute) as? String, text.utf8.count <= 1024 * 1024,
      let raw = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    // A missing composition signal is uncertainty, not evidence of inactive composition.
    guard let marked = attribute("AXMarkedTextRange"), CFGetTypeID(marked) == AXValueGetTypeID()
    else { return nil }
    var markedRange = CFRange()
    guard AXValueGetValue(unsafeBitCast(marked, to: AXValue.self), .cfRange, &markedRange),
      markedRange.length == 0
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0,
      range.location <= text.utf16.count, range.length <= text.utf16.count - range.location
    else { return nil }
    return State(
      element: element, value: text, range: NSRange(location: range.location, length: range.length))
  }
  private func evidence(_ current: State, range: NSRange, token: ContextToken) -> SelectionEvidence
  {
    let id = UUID()
    retained = (id, current.element)
    return .init(
      context: token, text: (current.value as NSString).substring(with: range),
      location: range.location, length: range.length, identity: id)
  }
  public func selected(in token: ContextToken) -> SelectionEvidence? {
    guard let current = state(token) else { return nil }
    return evidence(current, range: current.range, token: token)
  }
  public func suffix(_ text: String, in token: ContextToken) -> SelectionEvidence? {
    guard let current = state(token), current.range.length == 0,
      current.range.location >= text.utf16.count
    else { return nil }
    let range = NSRange(
      location: current.range.location - text.utf16.count, length: text.utf16.count)
    guard (current.value as NSString).substring(with: range) == text else { return nil }
    return evidence(current, range: range, token: token)
  }
  public func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult {
    guard evidence.text.utf8.count <= 1024 * 1024, text.utf8.count <= 1024 * 1024,
      let retained, retained.id == evidence.identity, let execute, let inputGeneration
    else { return .aborted }
    var selected = false
    func valid() -> Bool {
      guard let current = state(evidence.context), CFEqual(current.element, retained.element),
        evidence.location >= 0, evidence.length >= 0,
        evidence.location <= current.value.utf16.count,
        evidence.length <= current.value.utf16.count - evidence.location
      else { return false }
      let range = NSRange(location: evidence.location, length: evidence.length)
      selected = current.range == range
      return (current.value as NSString).substring(with: range) == evidence.text
        && (selected
          || (current.range.length == 0 && current.range.location == range.location + range.length))
    }
    guard valid() else { return .aborted }
    let generation = inputGeneration()
    let result = execute(evidence, text, selected, valid)
    guard result == .committed else { return result }
    guard inputGeneration() == generation, let after = state(evidence.context),
      CFEqual(after.element, retained.element),
      after.range == NSRange(location: evidence.location + text.utf16.count, length: 0),
      evidence.location + text.utf16.count <= after.value.utf16.count,
      (after.value as NSString).substring(
        with: NSRange(location: evidence.location, length: text.utf16.count)) == text,
      inputGeneration() == generation
    else { return .uncertain }
    return .committed
  }
}
