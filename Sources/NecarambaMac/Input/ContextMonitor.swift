import AppKit
import ApplicationServices
import Carbon
import NecarambaCore

/// AX observation occurs on the main run loop, never in the event tap callback.
public final class ContextMonitor: ContextRefreshing {
  public let state = ContextState()
  public var onAvailableLayoutsChanged: (() -> Void)?
  public var onLayoutChanged: ((LayoutID?) -> Void)?
  private let layouts: LayoutAccess
  private let permissions: PermissionReading
  private let qualifies: (String, String) -> Bool
  private var observedFocusReader: ((ContextState) -> ContextToken?)?
  private let chromiumActivation = ChromiumAccessibilityActivation()
  private let focusScheduler = FocusRefreshScheduler()
  private var needsFocusRecovery = false
  private var overlayOwnsFocus = false
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
  /// Inject an authoritative reader for notification integration tests without AX/TCC access.
  convenience init(layouts: LayoutAccess, permissions: PermissionReading,
                   qualifies: @escaping (String, String) -> Bool,
                   observedFocusReader: @escaping (ContextState) -> ContextToken?) {
    self.init(layouts: layouts, permissions: permissions, qualifies: qualifies)
    self.observedFocusReader = observedFocusReader
  }

  func observeSelectedLayoutChanges(_ center: NotificationCenter) {
    let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    observe(center, name) { [weak self] in
      // TIS changes do not prove a field change. Reconcile synchronously with
      // safety hidden, preserving lineage only if AX confirms the same field.
      self?.refreshObservedFocus()
    }
  }
  func invalidateAndRequestRecovery(_ reason: InvalidationReason) {
    precondition(Thread.isMainThread)
    state.invalidate(reason)
    automaticToken = nil
    needsFocusRecovery = true
    if active { focusScheduler.requestRefresh() }
  }
  var recoveryPermitted: Bool {
    guard needsFocusRecovery else { return false }
    let permission = permissions.current()
    return permission.ax && !permission.secureInput
  }
  public func current() -> ContextToken? { state.current() }
  public func isSafe(_ token: ContextToken) -> Bool { state.isSafe(token) }
  /// Static, recorded compatibility remains mandatory for automatic correction.
  public func isAutomaticEligible(_ token: ContextToken) -> Bool {
    state.isSafe(token) && automaticToken == token
  }
  public static func supportsManualRole(_ role: String) -> Bool {
    // WebKit exposes text inputs with suggestions as combo boxes. The selection
    // reader separately proves readable selection or a bounded physical-input fallback.
    role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
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
        guard let self else { return }
        self.state.invalidate(.sessionLock)
        self.automaticToken = nil
        self.detach()
      }
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      observe(NSWorkspace.shared.notificationCenter, name) { [weak self] in self?.attach() }
    }
    let availableName = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
    observe(DistributedNotificationCenter.default(), availableName) { [weak self] in
      self?.invalidateAndRequestRecovery(.layoutChanged)
      self?.onAvailableLayoutsChanged?()
    }
    observeSelectedLayoutChanges(DistributedNotificationCenter.default())
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
    overlayOwnsFocus = false
    chromiumActivation.stop()
    focusScheduler.stop()
    needsFocusRecovery = false
    if let observer {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    observer = nil
    observedApp = nil
    lastElement = nil
    focusIdentity = nil
  }
  private func attach(activateAccessibility: Bool = true) {
    precondition(Thread.isMainThread)
    InputDiagnostics.event("context.invalidate.attach")
    state.invalidate(.focusChanged)
    detach()
    guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier
    else {
      needsFocusRecovery = true
      diagnose("context.attach.noApplication")
      startFocusRefresh(notificationsAvailable: false)
      return
    }
    switch bundleID {
    case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary":
      InputDiagnostics.event("context.application.chrome")
    case "com.readdle.SparkDesktop":
      InputDiagnostics.event("context.application.spark")
    case "com.vscodium":
      InputDiagnostics.event("context.application.vscodium")
    case "org.tabby":
      InputDiagnostics.event("context.application.tabby")
    case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
      InputDiagnostics.event("context.application.safari")
    default:
      InputDiagnostics.event("context.application.other")
    }
    let permission = permissions.current()
    if !permission.secureInput {
      state.update(
        pid: app.processIdentifier, bundleID: bundleID, focusID: nil, layout: layouts.current(),
        qualified: false)
    }
    guard permission.ax else {
      needsFocusRecovery = true
      diagnose("context.attach.noAXPermission")
      startFocusRefresh(notificationsAvailable: false)
      return
    }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.1)
    observedApp = element
    if activateAccessibility {
      chromiumActivation.start(bundleID: bundleID, activate: { [weak self] in
        guard let self, self.active, self.permissions.current().ax,
          !self.permissions.current().secureInput,
          NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        guard let attribute = ChromiumAccessibilityActivation.attribute(for: bundleID) else { return false }
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        InputDiagnostics.event(bundleID == "com.readdle.SparkDesktop" ? "context.spark.activation" : "context.chrome.activation", detail: Int(status.rawValue))
        return status == .success
      }, refresh: { [weak self] in
        guard let self, self.active,
          NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        InputDiagnostics.event("context.chrome.activationRefresh")
        if self.observer != nil {
          self.handleObservedFocusChange()
        } else {
          self.attachObserver(to: element, pid: app.processIdentifier)
        }
      })
    }
    attachObserver(to: element, pid: app.processIdentifier)
  }
  private func attachObserver(to element: AXUIElement, pid: pid_t) {
    guard permissions.current().ax else {
      needsFocusRecovery = true
      startFocusRefresh(notificationsAvailable: false)
      return
    }
    var created: AXObserver?
    let callback: AXObserverCallback = { _, _, _, refcon in
      guard let refcon else { return }
      let monitor = Unmanaged<ContextMonitor>.fromOpaque(refcon).takeUnretainedValue()
      InputDiagnostics.event("context.refresh.focusNotification")
      monitor.handleObservedFocusChange()
    }
    let createStatus = AXObserverCreate(pid, callback, &created)
    guard createStatus == .success, let created else {
      diagnose("context.attach.observerCreateFailed", detail: Int(createStatus.rawValue))
      startFocusRefresh(notificationsAvailable: false)
      return
    }
    let reference = Unmanaged.passUnretained(self).toOpaque()
    let addStatus = AXObserverAddNotification(
      created, element, kAXFocusedUIElementChangedNotification as CFString, reference)
    guard addStatus == .success else {
      diagnose("context.attach.observerNotificationFailed", detail: Int(addStatus.rawValue))
      startFocusRefresh(notificationsAvailable: false)
      return
    }
    observer = created
    observedApp = element
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    startFocusRefresh(notificationsAvailable: true)
  }
  private func startFocusRefresh(notificationsAvailable: Bool) {
    focusScheduler.start(notificationsAvailable: notificationsAvailable, needsRecovery: { [weak self] in
      guard let self, self.active else { return false }
      // Keep the obligation even while permission/security temporarily blocks AX.
      return self.needsFocusRecovery || self.overlayOwnsFocus
    }) { [weak self] in
      guard let self, self.active else { return }
      self.refreshObservedFocus()
    }
  }

  func handleObservedFocusChange() {
    precondition(Thread.isMainThread)
    // A notification can reflect an accessibility descendant or repeat the
    // current owner. Hide safety during the read, and invalidate only when the
    // authoritative owner changes or cannot be established. Keep this
    // synchronous so no cached token remains usable before reconciliation.
    refreshObservedFocus()
  }

  private func refreshObservedFocus() {
    ObservedFocusRefresh.perform(state: state, refresh: {
      if let reader = self.observedFocusReader { return reader(self.state) }
      return self.refresh()
    }, synchronizeLayout: {
      self.onLayoutChanged?(self.layouts.current())
    })
  }
  /// Explicit revalidation before an edit must be invoked on the main thread.
  @discardableResult public func refresh() -> ContextToken? {
    precondition(Thread.isMainThread)
    let began = ProcessInfo.processInfo.systemUptime
    let performanceBegan = InputPerformanceMetrics.nowNanos()
    defer { InputPerformanceMetrics.shared.record(.contextRefresh, durationNanos: InputPerformanceMetrics.nowNanos() - performanceBegan) }
    let hadFocus = state.publishedCurrent() != nil
    defer {
      if active { focusScheduler.updateRecovery() }
      let hasFocus = state.publishedCurrent() != nil
      if hadFocus != hasFocus {
        InputDiagnostics.event(hasFocus ? "context.focus.recovered" : "context.focus.lost")
      }
      let elapsed = ProcessInfo.processInfo.systemUptime - began
      if elapsed >= 0.1 {
        InputDiagnostics.event("context.refresh.slowMilliseconds", detail: Int(min(elapsed * 1000, 60_000)))
      }
    }
    automaticToken = nil
    needsFocusRecovery = false
    let permission = permissions.current()
    guard !permission.secureInput, permission.ax else {
      // Keep recovery pending; the timer checks permission/security locally
      // and performs no AX reads until these conditions permit them again.
      needsFocusRecovery = true
      diagnose("context.refresh.secureOrPermissionMissing")
      state.invalidate(.unknownInput)
      return nil
    }
    let resolved = AXFocusedElementResolver.system.resolve(
      deadline: ProcessInfo.processInfo.systemUptime + 0.1)
    guard let focus = resolved.focus else {
      needsFocusRecovery = true
      diagnose("context.refresh.systemFocusUnavailable", detail: Int(resolved.status.rawValue))
      state.invalidate(.unknownInput)
      return nil
    }
    let element = focus.element
    let bundleID = focus.bundleID
    // Search overlays can own keyboard focus without becoming the workspace's
    // frontmost app. Continue observing that app, but poll while the overlay owns
    // focus so its field changes and dismissal cannot leave a stale token.
    let overlay = focus.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier
    if overlay && !overlayOwnsFocus { InputDiagnostics.event("context.systemFocus.overlayOwner") }
    overlayOwnsFocus = overlay
    let role = stringAttribute(element, kAXRoleAttribute)
    if role == nil { needsFocusRecovery = true }
    let subrole = stringAttribute(element, kAXSubroleAttribute)
    let allowed =
      Self.supportsManualRole(role ?? "") && subrole != kAXSecureTextFieldSubrole
    let elementChanged = lastElement == nil || !CFEqual(lastElement, element)
    if elementChanged {
      InputDiagnostics.event("context.refresh.elementChanged", detail: lastElement == nil ? 0 : 1)
      focusIdentity = UUID().uuidString
      lastElement = element
    }
    let before = state.publishedCurrent()
    state.update(
      pid: focus.pid, bundleID: bundleID, focusID: focusIdentity,
      layout: layouts.current(), qualified: allowed)
    let token = state.publishedCurrent()
    if before != token {
      InputDiagnostics.event("context.refresh.beforeFocusEpoch", detail: before.map { Int(clamping: $0.focusEpoch) } ?? -1)
      InputDiagnostics.event("context.refresh.afterFocusEpoch", detail: token.map { Int(clamping: $0.focusEpoch) } ?? -1)
      InputDiagnostics.event("context.refresh.beforeLayoutEpoch", detail: before.map { Int(clamping: $0.layoutEpoch) } ?? -1)
      InputDiagnostics.event("context.refresh.afterLayoutEpoch", detail: token.map { Int(clamping: $0.layoutEpoch) } ?? -1)
      InputDiagnostics.event("context.refresh.focusIdentityChanged", detail: elementChanged ? 1 : 0)
    }
    let roleReason: String
    switch role {
    case nil: roleReason = "context.role.missing"
    case "AXWebArea": roleReason = "context.role.webarea"
    case kAXTextFieldRole:
      roleReason = subrole == "AXSearchField" ? "context.role.searchfield" : "context.role.textfield"
    case "AXComboBox": roleReason = "context.role.combobox"
    case "AXSearchField": roleReason = "context.role.searchfield"
    case "AXGroup": roleReason = "context.role.group"
    case "AXWindow": roleReason = "context.role.window"
    case "AXApplication": roleReason = "context.role.application"
    case "AXScrollArea": roleReason = "context.role.scrollarea"
    case "AXStaticText": roleReason = "context.role.statictext"
    case "AXUnknown": roleReason = "context.role.unknown"
    case "AXLayoutArea": roleReason = "context.role.layoutarea"
    case "AXLayoutItem": roleReason = "context.role.layoutitem"
    case "AXTextInput": roleReason = "context.role.textinput"
    case "AXList": roleReason = "context.role.list"
    case "AXRow": roleReason = "context.role.row"
    case "AXMenu": roleReason = "context.role.menu"
    case "AXMenuItem": roleReason = "context.role.menuitem"
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
