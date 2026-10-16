import AppKit
import ApplicationServices

struct AXFocusedElement {
  let element: AXUIElement
  let pid: pid_t
  let bundleID: String
}

struct AXFocusedElementResolver {
  static let system = AXFocusedElementResolver(focusedElement: { deadline in
    let remaining = deadline - ProcessInfo.processInfo.systemUptime
    guard remaining > 0 else { return (.cannotComplete, nil) }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, Float(min(0.05, remaining)))
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
    guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return (status == .success ? .illegalArgument : status, nil) }
    return (.success, unsafeBitCast(value, to: AXUIElement.self))
  }, processID: { element in
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success && pid > 0 ? pid : nil
  }, bundleID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
  keyboardOwner: { raw, deadline in AXKeyboardFocusOwner.system.resolve(raw, deadline: deadline) })

  var focusedElement: (TimeInterval) -> (AXError, AXUIElement?)
  var processID: (AXUIElement) -> pid_t?
  var bundleID: (pid_t) -> String?
  var keyboardOwner: (AXUIElement, TimeInterval) -> AXUIElement = { element, _ in element }

  func resolve(expectedPID: pid_t? = nil, deadline: TimeInterval) -> (status: AXError, focus: AXFocusedElement?) {
    let (status, element) = focusedElement(deadline)
    guard status == .success else { return (status, nil) }
    guard let element, let pid = processID(element), pid > 0,
      expectedPID == nil || expectedPID == pid,
      let bundle = bundleID(pid), !bundle.isEmpty else { return (.noValue, nil) }
    let owner = keyboardOwner(element, deadline)
    guard processID(owner) == pid else { return (.noValue, nil) }
    if !CFEqual(owner, element) {
      let (checkStatus, check) = focusedElement(deadline)
      guard checkStatus == .success, let check, CFEqual(check, element),
        CFEqual(keyboardOwner(element, deadline), owner) else { return (.cannotComplete, nil) }
      InputDiagnostics.event("context.focus.keyboardOwnerResolved")
    }
    return (.success, AXFocusedElement(element: owner, pid: pid, bundleID: bundle))
  }
}

/// Distinguishes a virtual AX focus target from its actual keyboard input owner.
struct AXKeyboardFocusOwner {
  static let system = AXKeyboardFocusOwner { element, key, deadline in
    let remaining = deadline - ProcessInfo.processInfo.systemUptime
    guard remaining > 0,
      AXUIElementSetMessagingTimeout(element, Float(min(0.02, remaining))) == .success else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
      ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
    return value
  }
  var attribute: (AXUIElement, String, TimeInterval) -> CFTypeRef?
  func resolve(_ raw: AXUIElement, deadline: TimeInterval) -> AXUIElement {
    guard let role = attribute(raw, kAXRoleAttribute, deadline) as? String,
      !ContextMonitor.supportsManualRole(role) else { return raw }
    if let value = attribute(raw, kAXFocusedUIElementAttribute, deadline),
      CFGetTypeID(value) == AXUIElementGetTypeID() {
      let owner = unsafeBitCast(value, to: AXUIElement.self)
      if !CFEqual(raw, owner),
        let ownerRole = attribute(owner, kAXRoleAttribute, deadline) as? String,
        ContextMonitor.supportsManualRole(ownerRole),
        let focused = attribute(owner, kAXFocusedAttribute, deadline),
        CFGetTypeID(focused) == CFBooleanGetTypeID(), CFEqual(focused, kCFBooleanTrue) {
        return owner
      }
    }
    // Chromium exposes a direct text-field ancestor for actual editable
    // descendants. This is not a lookup of prior focus or a completion sibling.
    guard nonSecure(raw, deadline: deadline),
      let value = attribute(raw, "AXEditableAncestor", deadline),
      CFGetTypeID(value) == AXUIElementGetTypeID() else { return raw }
    let owner = unsafeBitCast(value, to: AXUIElement.self)
    guard !CFEqual(raw, owner),
      let ownerRole = attribute(owner, kAXRoleAttribute, deadline) as? String,
      ContextMonitor.supportsManualRole(ownerRole), nonSecure(owner, deadline: deadline),
      let confirmed = attribute(raw, "AXEditableAncestor", deadline),
      CFGetTypeID(confirmed) == AXUIElementGetTypeID(), CFEqual(value, confirmed)
    else { return raw }
    // Outer resolution still verifies process identity and stable system focus.
    InputDiagnostics.event("context.focus.editableAncestorCandidate")
    return owner
  }
  private func nonSecure(_ element: AXUIElement, deadline: TimeInterval) -> Bool {
    guard let value = attribute(element, kAXSubroleAttribute, deadline) else { return true }
    guard let subrole = value as? String else { return false }
    return subrole != kAXSecureTextFieldSubrole
  }
}
