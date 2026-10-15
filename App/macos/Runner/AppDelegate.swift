import Cocoa
import FlutterMacOS
import NecarambaCore
import NecarambaMac

@main
struct NecarambaMain {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var item: NSStatusItem?
  private var settingsWindow: MainFlutterWindow?
  private var services: ApplicationServices?
  private var input: NativeInputController?
  private var permissionRuntime: PermissionRuntimeController?
  private var delivery: ApplicationDeliveryServices?
  private var deliveryTask: Task<Void,Never>?
  private var lifecycle: LifecycleController?
  private var coordinator: NativeCommandCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let id = Bundle.main.bundleIdentifier ?? "local.necaramba.app"
      let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(id, isDirectory: true)
      let defaults = UserDefaults.standard
      let permissions = PermissionMonitor()
      let applicationServices = try ApplicationComposition.make(directory: directory, defaults: defaults,
        permissions: permissions, loginBackend: SystemLoginBackend(mainBundleID: id, defaults: defaults),
        onPreferences: { [weak self] snapshot in self?.services?.sound.setEnabled(snapshot.soundEnabled); self?.input?.updatePreferences(snapshot) },
        defaultSoundURL: Bundle.main.url(forResource: "correction", withExtension: "wav"))
      services = applicationServices
      applicationServices.sound.setEnabled(applicationServices.preferences.snapshot.soundEnabled)
      let bridge = NativeCommandCoordinator(snapshot: { [weak applicationServices] in applicationServices?.snapshot() ?? [:] },
        execute: { [weak applicationServices] method, arguments in
          guard let applicationServices else { throw NativeCommandFailure("unavailable") }
          return try await applicationServices.execute(method, arguments: arguments)
        })
      coordinator = bridge
      let input = NativeInputController(permissions: permissions, preferences: applicationServices.preferences.snapshot,
        conservativeAutomaticEnabled: true)
      self.input = input
      applicationServices.runtimeIsRunning = { [weak input] in input?.runtime.isRunning ?? false }
      input.onAutomaticReadinessChanged = { [weak applicationServices, weak bridge] ready in
        applicationServices?.automaticReady = ready
        bridge?.publishChange()
      }
      if let modelURL = Bundle.main.url(forResource: "LocalPatternModel", withExtension: "json") {
        input.installLocalModel(url: modelURL) { [weak applicationServices, weak bridge] result in
          switch result {
          case .success(let version):
            applicationServices?.additionalCorrectionsAvailable = true
            NSLog("Necaramba local pattern model installed: %@", version)
          case .failure:
            applicationServices?.additionalCorrectionsAvailable = false
            NSLog("Necaramba local pattern model could not be loaded")
          }
          bridge?.publishChange()
        }
      } else if let resources = Bundle.main.resourceURL,
                FileManager.default.fileExists(atPath: resources.appendingPathComponent("OpenModel/manifest.json").path) {
        input.installOpenModel(directory: resources.appendingPathComponent("OpenModel")) { [weak applicationServices, weak bridge] result in
          switch result {
          case .success(let version):
            applicationServices?.additionalCorrectionsAvailable = true
            NSLog("Necaramba open model installed: %@", version)
          case .failure:
            applicationServices?.additionalCorrectionsAvailable = false
            NSLog("Necaramba open model could not be loaded")
          }
          bridge?.publishChange()
        }
      }
      input.onToggleAuto = { [weak self] in self?.toggleAuto() }
      input.onCommitted = { [weak applicationServices,weak bridge] id,kind in
        guard let applicationServices else { return }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd"
        do {
          try applicationServices.statistics.recordCommitted(id:id,kind:kind,day:formatter.string(from:Date()))
          applicationServices.sound.playCorrection(committedID:id)
          bridge?.publishChange()
        } catch { NSSound.beep() }
      }
      applicationServices.onRulesChanged = { [weak self] in self?.publishRulePolicies() }
      applicationServices.onChanged = { [weak bridge] in bridge?.publishChange() }
      publishRulePolicies()
      let permissionRuntime = PermissionRuntimeController(permissions: permissions,
        start: { [weak input] in input?.start() ?? false }, stop: { [weak input] in input?.stop() },
        isRunning: { [weak input] in input?.runtime.isRunning ?? false })
      self.permissionRuntime = permissionRuntime
      applicationServices.onRefreshCapabilities = { [weak applicationServices, weak permissionRuntime] in
        applicationServices?.runtimeRunning = permissionRuntime?.refresh() ?? false
      }
      applicationServices.onRefreshCapabilities?()
      let lifecycle = LifecycleController(runtime: input); lifecycle.start(); self.lifecycle = lifecycle
      let delivery = ApplicationDeliveryServices(application:applicationServices,configuration:.init(bundleID:id))
      self.delivery=delivery
      applicationServices.externalCommand = { [weak delivery] method,arguments in
        guard let delivery else { throw NativeCommandFailure("unavailable") }
        return try await delivery.execute(method,arguments:arguments)
      }
      deliveryTask=Task { [weak self] in
        await delivery.start(bundle:.main,root:directory.appendingPathComponent("RulePackages")) { snapshot,onInstalled in
          // The local conversational supplement does not modify the signed package or
          // assert that its broad release-quality gate passed.
          self?.input?.install(ConservativeVocabulary.augment(snapshot),onInstalled:onInstalled)
        }
      }
      bridge.onStateChanged = { [weak self] state in
        self?.settingsWindow?.publish(state)
        self?.updateMenu()
      }
      item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item?.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Necaramba")
      updateMenu()
      let appMenu = NSMenu()
      let root = NSMenuItem(); let menu = NSMenu()
      let settings = NSMenuItem(title: text("Settings…","Настройки…"), action:#selector(openSettings), keyEquivalent:",");settings.target=self;menu.addItem(settings);menu.addItem(.separator())
      let quit = NSMenuItem(title: text("Quit Necaramba","Завершить Necaramba"), action: #selector(quitApp), keyEquivalent: "q"); quit.target = self
      menu.addItem(quit); root.submenu = menu; appMenu.addItem(root)
      let windowItem=NSMenuItem(); let windowMenu=NSMenu(title:text("Window","Окно"))
      windowMenu.addItem(withTitle:text("Close","Закрыть"),action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
      windowItem.submenu=windowMenu;appMenu.addItem(windowItem);NSApp.windowsMenu=windowMenu;NSApp.mainMenu=appMenu
      // Missing permissions need onboarding even after a background/login launch.
      let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
      let access = permissions.current()
      if !access.listen || !access.post || !access.ax ||
         (!loginLaunch && !ProcessInfo.processInfo.arguments.contains("--background")) { openSettings() }
    } catch {
      let alert = NSAlert(); alert.messageText = "Necaramba could not open its local data"
      alert.informativeText = "Existing data has been preserved. Close the app and inspect the local data directory before retrying."
      alert.runModal(); NSApp.terminate(nil)
    }
  }
  private func publishRulePolicies() {
    guard let services, let input else { return }
    do {
      input.updateWordPolicies(try services.rules.runtimeWordExclusions())
      input.updateAppPolicies(Dictionary(uniqueKeysWithValues:try services.rules.apps().map { ($0.bundleID, $0.mode == .allow ? AppOverride.allow : .deny) }))
    } catch { services.modelState = "failed" }
  }
  func applicationWillTerminate(_ notification: Notification) { deliveryTask?.cancel(); delivery?.stop(); lifecycle?.stop(); input?.stop(); InputPerformanceReport.flush() }
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
  func applicationDidBecomeActive(_ notification: Notification) {
    services?.login.refresh(); services?.onRefreshCapabilities?(); coordinator?.publishChange()
  }
  @objc private func openSettings() {
    guard let services, let coordinator else { return }
    if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
    let window = MainFlutterWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Necaramba"; window.minSize = NSSize(width: 700, height: 520)
    window.isReleasedWhenClosed = false
    window.attach(services: services, coordinator: coordinator)
    window.onClose = { [weak self] in self?.delivery?.cancelPendingShare(); self?.settingsWindow = nil }
    settingsWindow = window
    window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func toggleAuto() {
    guard let services else { return }
    do { try services.preferences.setAuto(!services.preferences.snapshot.autoEnabled); coordinator?.publishChange() }
    catch { NSSound.beep() }
  }
  @objc private func quitApp() { NSApp.terminate(nil) }
  private func text(_ english:String,_ russian:String)->String { Locale.preferredLanguages.first?.hasPrefix("ru") == true ? russian : english }
  private func updateMenu() {
    guard let services else { return }
    let menu = NSMenu()
    let open = NSMenuItem(title: "Necaramba…", action: #selector(openSettings), keyEquivalent: ","); open.target = self
    menu.addItem(open)
    let auto = NSMenuItem(title: text("Automatic correction","Автоматическая коррекция"), action: #selector(toggleAuto), keyEquivalent: ""); auto.target = self
    auto.state = services.preferences.snapshot.autoEnabled ? .on : .off; menu.addItem(auto)
    let permissions = services.permissions.current()
    if permissions.secureInput || !permissions.listen || !permissions.post || !permissions.ax {
      let warning = NSMenuItem(title: permissions.secureInput ? text("Secure Input is active","Защищённый ввод активен") : text("Permissions required","Требуются разрешения"), action: #selector(openSettings), keyEquivalent: "")
      warning.target = self; menu.addItem(warning)
    }
    menu.addItem(.separator())
    let quit = NSMenuItem(title: text("Quit","Завершить"), action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
    item?.menu = menu
  }
}
