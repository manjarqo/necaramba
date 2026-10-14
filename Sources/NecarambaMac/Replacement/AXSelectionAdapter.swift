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
  func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot?
}
extension AXSelectionReading {
  public func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot? {
    read(in: token)
  }
}
/// Direct system proof. This reader performs no mutations and is called only outside the tap.
public final class SystemAXSelectionReader: AXSelectionReading {
  private let context: ContextAccess
  private let qualifies: (String, String) -> Bool
  private let allowMissingMarkedTextRange: () -> Bool
  private var retained: (id: UUID, element: AXUIElement)?
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    allowMissingMarkedTextRange: @escaping () -> Bool = { false }
  ) {
    self.context = context
    self.qualifies = qualifies
    self.allowMissingMarkedTextRange = allowMissingMarkedTextRange
  }
  public func read(in token: ContextToken) -> AXTextSnapshot? {
    read(in: token, deadline: ProcessInfo.processInfo.systemUptime + 0.1)
  }
  public func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot? {
    precondition(Thread.isMainThread)
    func trace(_ reason: String, detail: Int = 0) {
      if allowMissingMarkedTextRange() { InputDiagnostics.event(reason, detail: detail) }
    }
    func budget(_ element: AXUIElement) -> Bool {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { trace("ax.readDeadlineExceeded"); return false }
      return AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining))) == .success
    }
    guard !IsSecureEventInputEnabled(), context.isSafe(token),
      NSWorkspace.shared.frontmostApplication?.processIdentifier == token.pid
    else { trace("ax.unsafeContext"); return nil }
    let app = AXUIElementCreateApplication(token.pid)
    guard budget(app) else { return nil }
    var focused: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
      app, kAXFocusedUIElementAttribute as CFString, &focused)
    trace("ax.readFocus", detail: Int(focusStatus.rawValue))
    guard focusStatus == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { trace("ax.invalidFocus"); return nil }
    let element = unsafeBitCast(focused, to: AXUIElement.self)
    func readAttribute(_ name: String) -> (AXError, CFTypeRef?) {
      guard budget(element) else { return (.cannotComplete, nil) }
      var value: CFTypeRef?
      let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
      switch name {
      case kAXRoleAttribute: trace("ax.readRole", detail: Int(status.rawValue))
      case kAXSubroleAttribute: trace("ax.readSubrole", detail: Int(status.rawValue))
      case kAXValueAttribute: trace("ax.readValue", detail: Int(status.rawValue))
      case kAXSelectedTextRangeAttribute: trace("ax.readSelectedRange", detail: Int(status.rawValue))
      case "AXMarkedTextRange": trace("ax.readMarkedRange", detail: Int(status.rawValue))
      default: break
      }
      return (status, value)
    }
    func attribute(_ name: String) -> CFTypeRef? {
      let (status, value) = readAttribute(name)
      return status == .success ? value : nil
    }
    guard let role = attribute(kAXRoleAttribute) as? String, qualifies(token.bundleID, role),
      attribute(kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
      let text = attribute(kAXValueAttribute) as? String, text.utf8.count <= 1024 * 1024,
      let raw = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID()
    else { trace("ax.invalidFieldMetadata"); return nil }
    let (markedStatus, marked) = readAttribute("AXMarkedTextRange")
    var markedRange: CFRange?
    if markedStatus == .success {
      guard let marked, CFGetTypeID(marked) == AXValueGetTypeID()
      else { trace("ax.malformedMarkedRange"); return nil }
      var decoded = CFRange()
      guard AXValueGetValue(unsafeBitCast(marked, to: AXValue.self), .cfRange, &decoded)
      else { trace("ax.malformedMarkedRange"); return nil }
      markedRange = decoded
    }
    let directLayout = Self.isDirectKeyboardLayout()
    trace("ax.compositionDirectLayout", detail: directLayout ? 1 : 0)
    guard AXCompositionProof.permits(
      markedRange: markedRange,
      attributeUnavailable: markedStatus == .attributeUnsupported || markedStatus == .noValue,
      manual: allowMissingMarkedTextRange(), directKeyboardLayout: directLayout)
    else { trace("ax.compositionRejected"); return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0,
      range.location <= text.utf16.count, range.length <= text.utf16.count - range.location
    else { trace("ax.malformedSelectedRange"); return nil }
    guard ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
    if retained == nil || !CFEqual(retained!.element, element) { retained = (UUID(), element) }
    return AXTextSnapshot(
      identity: retained!.id, value: text,
      range: NSRange(location: range.location, length: range.length))
  }

  private static func isDirectKeyboardLayout() -> Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
    else { return false }
    let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
    return type == kTISTypeKeyboardLayout
  }
}
/// Selection mode, identity, context and generation are frozen when evidence is first read.
public final class AXSelectionAdapter: SelectionAccess {
  public typealias Mutation = (SelectionEvidence, String, Bool, () -> Bool) -> ApplyResult
  public var execute: Mutation?
  public var inputGeneration: (() -> UInt64)?
  private let context: ContextAccess
  private let reader: AXSelectionReading
  private let manualCommandActive: () -> Bool
  private let now: () -> TimeInterval
  private let wait: (TimeInterval) -> Void
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    reader: AXSelectionReading? = nil,
    allowMissingMarkedTextRange: @escaping () -> Bool = { false },
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) {
    self.context = context
    self.reader = reader ?? SystemAXSelectionReader(
      context: context, qualifies: qualifies, allowMissingMarkedTextRange: allowMissingMarkedTextRange)
    self.manualCommandActive = allowMissingMarkedTextRange
    self.now = now
    self.wait = wait
  }
  private func snapshot(
    _ token: ContextToken, generation: UInt64, deadline: TimeInterval? = nil
  ) -> AXTextSnapshot? {
    guard inputGeneration?() == generation, context.isSafe(token),
      let value = deadline.map({ reader.read(in: token, deadline: $0) }) ?? reader.read(in: token),
      value.value.utf8.count <= 1024 * 1024, value.range.location >= 0, value.range.length >= 0,
      value.range.location <= value.value.utf16.count,
      value.range.length <= value.value.utf16.count - value.range.location,
      inputGeneration?() == generation, context.isSafe(token)
    else { return nil }
    return value
  }
  private func trace(_ reason: String, detail: Int = 0) {
    if manualCommandActive() { InputDiagnostics.event(reason, detail: detail) }
  }
  private func traceMutation(_ result: ApplyResult) {
    switch result {
    case .committed: trace("ax.mutation.committed")
    case .dispatched: trace("ax.mutation.dispatched")
    case .aborted: trace("ax.mutation.aborted")
    case .uncertain: trace("ax.mutation.uncertain")
    }
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
    var before: AXTextSnapshot?
    func valid() -> Bool {
      guard let current = snapshot(evidence.context, generation: generation),
        current.identity == identity,
        current.range == observedRange, range.location >= 0, range.length >= 0,
        range.location <= current.value.utf16.count,
        range.length <= current.value.utf16.count - range.location
      else { return false }
      guard (current.value as NSString).substring(with: range) == evidence.text,
        before == nil || before?.value == current.value
      else { return false }
      before = current
      return true
    }
    guard valid(), let before else { return .aborted }
    let expectedValue = (before.value as NSString).replacingCharacters(in: range, with: text)
    let expectedRange = NSRange(location: evidence.location + text.utf16.count, length: 0)
    trace("ax.execute.begin")
    let result = execute(evidence, text, selected, valid)
    traceMutation(result)
    guard result == .committed else { return result }
    // Posting is asynchronous. Read only: never repeat a mutation or attempt rollback.
    // Sleep outside the tap without pumping the UI runloop (which could reenter commands).
    let deadline = now() + 0.1
    for _ in 0..<21 {
      guard now() < deadline,
        let after = snapshot(evidence.context, generation: generation, deadline: deadline),
        now() <= deadline, after.identity == identity
      else { return .uncertain }
      if after.value == expectedValue && after.range == expectedRange { return .committed }
      // Only the unchanged pre-post state is safe to wait on. Partial or unrelated edits
      // are uncertain, even if a later read might happen to match the desired output.
      guard after.value == before.value, after.range == before.range else { return .uncertain }
      let remaining = deadline - now()
      guard remaining > 0 else { return .uncertain }
      wait(min(0.005, remaining))
    }
    return .uncertain
  }
}

/// Missing marked-text metadata is not proof that composition is inactive.
/// Explicit manual commands may accept it for a direct keyboard layout only;
/// this does not establish absence of dead-key state. Automatic correction stays strict.
enum AXCompositionProof {
  static func permits(
    markedRange: CFRange?, attributeUnavailable: Bool, manual: Bool, directKeyboardLayout: Bool
  ) -> Bool {
    guard let markedRange else {
      return attributeUnavailable && manual && directKeyboardLayout
    }
    return markedRange.length == 0 && markedRange.location >= -1
  }
}

extension AXSelectionAdapter: ManualTrackedSuffixReplacing {
  public func replaceTrackedSuffix(_ word: BufferedWord, with text: String) -> ApplyResult {
    // Some terminal widgets expose only an empty AX input proxy. An explicit command
    // may use physically tracked input there, but AX cannot prove the real suffix.
    // Dispatch is deliberately distinct from a verified edit (no undo/statistics).
    let original = word.text + word.delimiter
    guard manualCommandActive(), !word.text.isEmpty, !word.events.isEmpty,
      word.events.count <= 128, original.count <= 128, original.utf16.count <= 512,
      !text.isEmpty, text.count <= 128, text.utf16.count <= 512,
      word.events.allSatisfy({
        $0.origin == .physical && $0.kind == .down && $0.context == word.context
          && $0.layout == word.layout && $0.modifiers.isSubset(of: [.shift, .capsLock])
          && $0.text?.count == 1
      }), word.events.compactMap(\.text).joined() == word.text,
      word.delimiter.allSatisfy({ "!? ".contains($0) })
    else { trace("ax.tracked.physicalProofRejected"); return .aborted }
    guard let generation = inputGeneration?() else {
      trace("ax.tracked.generationMissing"); return .aborted
    }
    guard let before = snapshot(word.context, generation: generation) else {
      trace("ax.tracked.snapshotMissing"); return .aborted
    }
    trace("ax.tracked.nonemptyValue", detail: before.value.isEmpty ? 0 : 1)
    trace("ax.tracked.rangeZero", detail: before.range == NSRange(location: 0, length: 0) ? 1 : 0)
    guard before.value.isEmpty, before.range == NSRange(location: 0, length: 0) else { return .aborted }
    guard let execute else { trace("ax.tracked.executeMissing"); return .aborted }
    func valid() -> Bool {
      guard manualCommandActive(), let current = snapshot(word.context, generation: generation)
      else { return false }
      return current.identity == before.identity && current.value.isEmpty
        && current.range == NSRange(location: 0, length: 0)
    }
    let evidence = SelectionEvidence(
      context: word.context, text: original, location: 0, length: original.utf16.count,
      identity: before.identity, inputGeneration: generation, mode: .suffix)
    guard valid() else { trace("ax.tracked.preflightRejected"); return .aborted }
    trace("ax.tracked.execute.begin")
    let result = execute(evidence, text, false, valid)
    traceMutation(result)
    guard result == .committed else { return result }
    guard let after = snapshot(word.context, generation: generation),
      after.identity == before.identity
    else { return .uncertain }
    if after.value == text && after.range == NSRange(location: text.utf16.count, length: 0) {
      // Even exact output cannot retrospectively prove the original invisible suffix.
      return .dispatched
    }
    return after.value.isEmpty && after.range == NSRange(location: 0, length: 0)
      ? .dispatched : .uncertain
  }
}
