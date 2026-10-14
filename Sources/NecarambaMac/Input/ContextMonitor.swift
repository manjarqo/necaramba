import AppKit
import ApplicationServices
import Carbon
import NecarambaCore

/// AX observation occurs on the main run loop, never in the event tap callback.
public final class ContextMonitor: ContextRefreshing {
  public let state = ContextState()
  public var onLayoutChanged: ((LayoutID?) -> Void)?
  private let layouts: LayoutAccess
  private let permissions: PermissionReading
  private let qualifies: (String, String) -> Bool
  private var observer: AXObserver?
  private var observedApp: AXUIElement?
  private var lastElement: AXUIElement?
  private var focusIdentity: String?
  private var automaticToken: ContextToken?
  private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var active = false
  private var lastDiagnostic: String?
  private func diagnose(_ event: String, detail: Int = 0) {
    let key = event + ":" + String(detail)
    guard lastDiagnostic != key else { return }
    lastDiagnostic = key
    InputDiagnostics.event(event, detail: detail)
  }

  public init(
    layouts: LayoutAccess, permissions: PermissionReading,
    qualifies: @escaping (String, String) -> Bool
  ) {
    self.layouts = layouts
    self.permissions = permissions
    self.qualifies = qualifies
  }
  public func current() -> ContextToken? { state.current() }
  public func isSafe(_ token: ContextToken) -> Bool { state.isSafe(token) }
  /// Static, recorded compatibility remains mandatory for automatic correction.
  public func isAutomaticEligible(_ token: ContextToken) -> Bool {
    state.isSafe(token) && automaticToken == token
  }
  public static func supportsManualRole(_ role: String) -> Bool {
    role == kAXTextFieldRole || role == kAXTextAreaRole
  }
  public func start() {
    precondition(Thread.isMainThread)
    guard !active else { return }
    active = true
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) {
      [weak self] in self?.attach()
    }
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
    {
      observe(NSWorkspace.shared.notificationCenter, name) { [weak self] in
        self?.state.invalidate(.sessionLock)
      }
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      observe(NSWorkspace.shared.notificationCenter, name) { [weak self] in self?.attach() }
    }
    let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    observe(DistributedNotificationCenter.default(), name) { [weak self] in
      self?.refresh()
      self?.onLayoutChanged?(self?.layouts.current())
    }
    attach()
  }
  public func stop() {
    precondition(Thread.isMainThread)
    detach()
    for (center, token) in tokens { center.removeObserver(token) }
    tokens.removeAll()
    active = false
    state.invalidate(.unknownInput)
  }
  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
    tokens.append((center, token))
  }
  private func detach() {
    if let observer {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    observer = nil
    observedApp = nil
    lastElement = nil
    focusIdentity = nil
  }
  private func attach() {
    precondition(Thread.isMainThread)
    state.invalidate(.focusChanged)
    detach()
    guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier
    else { diagnose("context.attach.noApplication"); return }
    let permission = permissions.current()
    if !permission.secureInput {
      state.update(
        pid: app.processIdentifier, bundleID: bundleID, focusID: nil, layout: layouts.current(),
        qualified: false)
    }
    guard permission.ax else { diagnose("context.attach.noAXPermission"); return }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.1)
    var created: AXObserver?
    let callback: AXObserverCallback = { _, _, _, refcon in
      guard let refcon else { return }
      let monitor = Unmanaged<ContextMonitor>.fromOpaque(refcon).takeUnretainedValue()
      monitor.state.invalidate(.focusChanged)
      monitor.refresh()
    }
    let createStatus = AXObserverCreate(app.processIdentifier, callback, &created)
    guard createStatus == .success, let created else {
      diagnose("context.attach.observerCreateFailed", detail: Int(createStatus.rawValue))
      return
    }
    let reference = Unmanaged.passUnretained(self).toOpaque()
    let addStatus = AXObserverAddNotification(
      created, element, kAXFocusedUIElementChangedNotification as CFString, reference)
    guard addStatus == .success else {
      diagnose("context.attach.observerNotificationFailed", detail: Int(addStatus.rawValue))
      return
    }
    observer = created
    observedApp = element
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    refresh()
  }
  /// Explicit revalidation before an edit must be invoked on the main thread.
  @discardableResult public func refresh() -> ContextToken? {
    precondition(Thread.isMainThread)
    automaticToken = nil
    let permission = permissions.current()
    guard !permission.secureInput, let app = NSWorkspace.shared.frontmostApplication,
      let bundleID = app.bundleIdentifier
    else {
      diagnose("context.refresh.secureOrApplicationMissing", detail: permission.secureInput ? 1 : 0)
      state.invalidate(.unknownInput)
      return nil
    }
    guard permission.ax, let observedApp else {
      diagnose("context.refresh.permissionOrObserverMissing", detail: permission.ax ? 1 : 0)
      state.update(
        pid: app.processIdentifier, bundleID: bundleID, focusID: nil, layout: layouts.current(),
        qualified: false)
      return nil
    }
    var observedPID: pid_t = 0
    guard AXUIElementGetPid(observedApp, &observedPID) == .success,
      observedPID == app.processIdentifier
    else {
      diagnose("context.refresh.observedProcessMismatch")
      state.invalidate(.focusChanged)
      return nil
    }
    var value: CFTypeRef?
    let focusedStatus = AXUIElementCopyAttributeValue(
      observedApp, kAXFocusedUIElementAttribute as CFString, &value)
    guard focusedStatus == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      diagnose("context.refresh.focusUnavailable", detail: Int(focusedStatus.rawValue))
      state.invalidate(.unknownInput)
      return nil
    }
    let element = unsafeBitCast(value, to: AXUIElement.self)
    let role = stringAttribute(element, kAXRoleAttribute)
    let subrole = stringAttribute(element, kAXSubroleAttribute)
    let allowed =
      Self.supportsManualRole(role ?? "") && subrole != kAXSecureTextFieldSubrole
    if lastElement == nil || !CFEqual(lastElement, element) {
      focusIdentity = UUID().uuidString
      lastElement = element
    }
    state.update(
      pid: app.processIdentifier, bundleID: bundleID, focusID: focusIdentity,
      layout: layouts.current(), qualified: allowed)
    let token = state.current()
    let roleReason: String
    switch role {
    case nil: roleReason = "context.role.missing"
    case "AXWebArea": roleReason = "context.role.webarea"
    case kAXTextFieldRole: roleReason = "context.role.textfield"
    case kAXTextAreaRole: roleReason = "context.role.textarea"
    default: roleReason = "context.role.other"
    }
    // Bit 0: editable token; bit 1: secure field. Role itself is a static code only.
    diagnose(roleReason, detail: (token == nil ? 0 : 1) | (subrole == kAXSecureTextFieldSubrole ? 2 : 0))
    if allowed && qualifies(bundleID, role ?? "") { automaticToken = token }
    return token
  }
  private func stringAttribute(_ element: AXUIElement, _ key: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }
}
