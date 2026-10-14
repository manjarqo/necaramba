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
  }, bundleID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })

  var focusedElement: (TimeInterval) -> (AXError, AXUIElement?)
  var processID: (AXUIElement) -> pid_t?
  var bundleID: (pid_t) -> String?

  func resolve(expectedPID: pid_t? = nil, deadline: TimeInterval) -> (status: AXError, focus: AXFocusedElement?) {
    let (status, element) = focusedElement(deadline)
    guard status == .success else { return (status, nil) }
    guard let element, let pid = processID(element), pid > 0,
      expectedPID == nil || expectedPID == pid,
      let bundle = bundleID(pid), !bundle.isEmpty else { return (.noValue, nil) }
    return (.success, AXFocusedElement(element: element, pid: pid, bundleID: bundle))
  }
}
