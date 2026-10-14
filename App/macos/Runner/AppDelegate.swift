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
      let applicationServices = try ApplicationServices(directory: directory, defaults: defaults,
        permissions: PermissionMonitor(), loginBackend: SystemLoginBackend(mainBundleID: id, defaults: defaults),
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
      let input = NativeInputController(preferences: applicationServices.preferences.snapshot)
      self.input = input
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
      applicationServices.runtimeRunning = input.start()
      let lifecycle = LifecycleController(runtime: input); lifecycle.start(); self.lifecycle = lifecycle
      let delivery = ApplicationDeliveryServices(application:applicationServices,configuration:.init(bundleID:id))
      self.delivery=delivery
      applicationServices.externalCommand = { [weak delivery] method,arguments in
        guard let delivery else { throw NativeCommandFailure("unavailable") }
        return try await delivery.execute(method,arguments:arguments)
      }
      deliveryTask=Task { [weak self] in
        await delivery.start(bundle:.main,root:directory.appendingPathComponent("RulePackages")) { snapshot,onInstalled in self?.input?.install(snapshot,onInstalled:onInstalled) }
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
      // Login launch stays in the menu bar; explicit launches open settings.
      let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
      if !loginLaunch && !ProcessInfo.processInfo.arguments.contains("--background") { openSettings() }
    } catch {
      let alert = NSAlert(); alert.messageText = "Necaramba could not open its local data"
      alert.informativeText = "Existing data has been preserved. Close the app and inspect the local data directory before retrying."
      alert.runModal(); NSApp.terminate(nil)
    }
  }
  private func publishRulePolicies() {
    guard let services, let input else { return }
    do {
      input.updateWordPolicies(Set(try services.rules.words().map(\.normalized)))
      input.updateAppPolicies(Dictionary(uniqueKeysWithValues:try services.rules.apps().map { ($0.bundleID, $0.mode == .allow ? AppOverride.allow : .deny) }))
    } catch { services.modelState = "failed" }
  }
  func applicationWillTerminate(_ notification: Notification) { deliveryTask?.cancel(); delivery?.stop(); lifecycle?.stop(); input?.stop() }
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
  func applicationDidBecomeActive(_ notification: Notification) {
    services?.login.refresh(); services?.runtimeRunning = input?.start() ?? false; coordinator?.publishChange()
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
    if permissions.secureInput || !permissions.listen || !permissions.post {
      let warning = NSMenuItem(title: permissions.secureInput ? text("Secure Input is active","Защищённый ввод активен") : text("Permissions required","Требуются разрешения"), action: #selector(openSettings), keyEquivalent: "")
      warning.target = self; menu.addItem(warning)
    }
    menu.addItem(.separator())
    let quit = NSMenuItem(title: text("Quit","Завершить"), action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
    item?.menu = menu
  }
}
