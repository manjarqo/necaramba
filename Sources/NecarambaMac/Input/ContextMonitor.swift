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
  private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var active = false

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
    else { return }
    let permission = permissions.current()
    if !permission.secureInput {
      state.update(
        pid: app.processIdentifier, bundleID: bundleID, focusID: nil, layout: layouts.current(),
        qualified: false)
    }
    guard permission.ax else { return }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.1)
    var created: AXObserver?
    let callback: AXObserverCallback = { _, _, _, refcon in
      guard let refcon else { return }
      let monitor = Unmanaged<ContextMonitor>.fromOpaque(refcon).takeUnretainedValue()
      monitor.state.invalidate(.focusChanged)
      monitor.refresh()
    }
    guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created
    else { return }
    let reference = Unmanaged.passUnretained(self).toOpaque()
    guard
      AXObserverAddNotification(
        created, element, kAXFocusedUIElementChangedNotification as CFString, reference) == .success
    else { return }
    observer = created
    observedApp = element
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    refresh()
  }
  /// Explicit revalidation before an edit must be invoked on the main thread.
  @discardableResult public func refresh() -> ContextToken? {
    precondition(Thread.isMainThread)
    let permission = permissions.current()
    guard !permission.secureInput, let app = NSWorkspace.shared.frontmostApplication,
      let bundleID = app.bundleIdentifier
    else {
      state.invalidate(.unknownInput)
      return nil
    }
    guard permission.ax, let observedApp else {
      state.update(
        pid: app.processIdentifier, bundleID: bundleID, focusID: nil, layout: layouts.current(),
        qualified: false)
      return nil
    }
    var observedPID: pid_t = 0
    guard AXUIElementGetPid(observedApp, &observedPID) == .success,
      observedPID == app.processIdentifier
    else {
      state.invalidate(.focusChanged)
      return nil
    }
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(observedApp, kAXFocusedUIElementAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      state.invalidate(.unknownInput)
      return nil
    }
    let element = unsafeBitCast(value, to: AXUIElement.self)
    let role = stringAttribute(element, kAXRoleAttribute)
    let subrole = stringAttribute(element, kAXSubroleAttribute)
    let allowed =
      (role == kAXTextFieldRole || role == kAXTextAreaRole)
      && subrole != kAXSecureTextFieldSubrole && qualifies(bundleID, role ?? "")
    if lastElement == nil || !CFEqual(lastElement, element) {
      focusIdentity = UUID().uuidString
      lastElement = element
    }
    state.update(
      pid: app.processIdentifier, bundleID: bundleID, focusID: focusIdentity,
      layout: layouts.current(), qualified: allowed)
    return state.current()
  }
  private func stringAttribute(_ element: AXUIElement, _ key: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }
}
