import AppKit
import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ThemeModeTests: XCTestCase {
  func testStoredPreferencesWithoutThemeFollowTheSystem() throws {
    let legacy = try JSONEncoder().encode(StoredPreferencesV1(selectedColor: 3))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
    object.removeValue(forKey: "themeMode")
    let decoded = try JSONDecoder().decode(StoredPreferencesV1.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(decoded.themeMode, .system)
    XCTAssertEqual(decoded.selectedColor, 3)
    XCTAssertEqual(StoredPreferencesV1().themeMode, .system)
  }

  func testThemeModeMapsToWindowAppearance() {
    XCTAssertNil(ThemeMode.system.appearanceName)
    XCTAssertEqual(ThemeMode.light.appearanceName, .aqua)
    XCTAssertEqual(ThemeMode.dark.appearanceName, .darkAqua)
    XCTAssertNil(ThemeMode(rawValue: "sepia"))
  }

  func testThemeModePersistsAndIsPublishedInAppearance() async throws {
    try await MainActor.run {
      let name = "NecarambaTests.\(UUID())"
      let defaults = UserDefaults(suiteName: name)!
      defer { defaults.removePersistentDomain(forName: name) }
      let controller = PreferencesController(defaults: defaults) { _ in }
      try controller.setThemeMode(.dark)
      XCTAssertEqual(PreferencesController(defaults: defaults) { _ in }.settings.themeMode, .dark)
      try controller.setSelectedColor(4)
      XCTAssertEqual(controller.settings.themeMode, .dark, "Other appearance edits keep the theme")
      try controller.setLoginPreferred(true)
      XCTAssertEqual(controller.settings.themeMode, .dark)
    }
  }

  @MainActor func testSetThemeModeCommandPersistsAndRejectsUnknownModes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let domain = "test.necaramba." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
    let app = try ApplicationServices(directory: directory, defaults: defaults,
      permissions: ThemePermissions(), loginBackend: ThemeLogin(), onPreferences: { _ in })
    XCTAssertEqual((app.snapshot()["appearance"] as? [String: Any])?["themeMode"] as? String, "system")
    _ = try await app.execute("setThemeMode", arguments: ["mode": "dark"])
    XCTAssertEqual((app.snapshot()["appearance"] as? [String: Any])?["themeMode"] as? String, "dark")
    do { _ = try await app.execute("setThemeMode", arguments: ["mode": "sepia"]); XCTFail() } catch {}
    let reopened = try ApplicationServices(directory: directory, defaults: defaults,
      permissions: ThemePermissions(), loginBackend: ThemeLogin(), onPreferences: { _ in })
    XCTAssertEqual((reopened.snapshot()["appearance"] as? [String: Any])?["themeMode"] as? String, "dark")
  }

  @MainActor func testCoordinatorAcceptsThemeCommand() {
    XCTAssertTrue(NativeCommandCoordinator.isAllowed("setThemeMode"))
  }
}

private final class ThemePermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: false, post: false, ax: false, secureInput: false) }
  func request(_ kind: PermissionKind) {}
}
private struct ThemeLogin: LoginBackend {
  func status() -> LoginStatus { .disabled }
  func setEnabled(_ value: Bool) throws {}
}
