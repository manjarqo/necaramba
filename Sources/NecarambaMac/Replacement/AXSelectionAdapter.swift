import AppKit
import ApplicationServices
import Carbon
import NecarambaCore

public struct AXTextSnapshot {
  public let identity: UUID
  public let value: String
  public let range: NSRange
  public init(identity: UUID, value: String, range: NSRange) {
    self.identity = identity
    self.value = value
    self.range = range
  }
}
public protocol AXSelectionReading: AnyObject {
  func read(in token: ContextToken) -> AXTextSnapshot?
}
/// Direct system proof. This reader performs no mutations and is called only outside the tap.
public final class SystemAXSelectionReader: AXSelectionReading {
  private let context: ContextAccess
  private let qualifies: (String, String) -> Bool
  private var retained: (id: UUID, element: AXUIElement)?
  public init(context: ContextAccess, qualifies: @escaping (String, String) -> Bool) {
    self.context = context
    self.qualifies = qualifies
  }
  public func read(in token: ContextToken) -> AXTextSnapshot? {
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
    if retained == nil || !CFEqual(retained!.element, element) { retained = (UUID(), element) }
    return AXTextSnapshot(
      identity: retained!.id, value: text,
      range: NSRange(location: range.location, length: range.length))
  }

}
/// Selection mode, identity, context and generation are frozen when evidence is first read.
public final class AXSelectionAdapter: SelectionAccess {
  public typealias Mutation = (SelectionEvidence, String, Bool, () -> Bool) -> ApplyResult
  public var execute: Mutation?
  public var inputGeneration: (() -> UInt64)?
  private let context: ContextAccess
  private let reader: AXSelectionReading
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    reader: AXSelectionReading? = nil
  ) {
    self.context = context
    self.reader = reader ?? SystemAXSelectionReader(context: context, qualifies: qualifies)
  }
  private func snapshot(_ token: ContextToken, generation: UInt64) -> AXTextSnapshot? {
    guard inputGeneration?() == generation, context.isSafe(token),
      let value = reader.read(in: token),
      value.value.utf8.count <= 1024 * 1024, value.range.location >= 0, value.range.length >= 0,
      value.range.location <= value.value.utf16.count,
      value.range.length <= value.value.utf16.count - value.range.location,
      inputGeneration?() == generation, context.isSafe(token)
    else { return nil }
    return value
  }
  public func selected(in token: ContextToken) -> SelectionEvidence? {
    guard let generation = inputGeneration?(), let value = snapshot(token, generation: generation)
    else { return nil }
    return .init(
      context: token, text: (value.value as NSString).substring(with: value.range),
      location: value.range.location, length: value.range.length, identity: value.identity,
      inputGeneration: generation, mode: .selected)
  }
  public func suffix(_ text: String, in token: ContextToken) -> SelectionEvidence? {
    guard let generation = inputGeneration?(), let value = snapshot(token, generation: generation),
      value.range.length == 0, value.range.location >= text.utf16.count
    else { return nil }
    let range = NSRange(location: value.range.location - text.utf16.count, length: text.utf16.count)
    guard (value.value as NSString).substring(with: range) == text else { return nil }
    return .init(
      context: token, text: text, location: range.location, length: range.length,
      identity: value.identity, inputGeneration: generation, mode: .suffix)
  }
  public func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult {
    guard evidence.text.utf8.count <= 1024 * 1024, text.utf8.count <= 1024 * 1024,
      let identity = evidence.identity, let generation = evidence.inputGeneration,
      let mode = evidence.mode, let execute
    else { return .aborted }
    let selected = mode == .selected
    let range = NSRange(location: evidence.location, length: evidence.length)
    let observedRange =
      selected ? range : NSRange(location: evidence.location + evidence.length, length: 0)
    func valid() -> Bool {
      guard let current = snapshot(evidence.context, generation: generation),
        current.identity == identity,
        current.range == observedRange, range.location >= 0, range.length >= 0,
        range.location <= current.value.utf16.count,
        range.length <= current.value.utf16.count - range.location
      else { return false }
      return (current.value as NSString).substring(with: range) == evidence.text
    }
    guard valid() else { return .aborted }
    let result = execute(evidence, text, selected, valid)
    guard result == .committed else { return result }
    guard let after = snapshot(evidence.context, generation: generation),
      after.identity == identity,
      after.range == NSRange(location: evidence.location + text.utf16.count, length: 0),
      evidence.location + text.utf16.count <= after.value.utf16.count,
      (after.value as NSString).substring(
        with: NSRange(location: evidence.location, length: text.utf16.count)) == text
    else { return .uncertain }
    return .committed
  }
}
