import AppKit
import NecarambaCore

/// Window appearance choice; `system` follows macOS and is the default.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
 case system, light, dark
 public var appearanceName: NSAppearance.Name? {
  switch self { case .system: return nil; case .light: return .aqua; case .dark: return .darkAqua }
 }
}

public enum PreferencesError: Error { case unsupportedVersion, invalidColor }
public struct StoredPreferencesV1: Codable, Equatable, Sendable {
 public let version: Int
 public let snapshot: PreferencesSnapshot
 public let selectedColor: Int
 public let loginPreferred: Bool
 public let diagnosticsOptIn: Bool
 public let themeMode: ThemeMode
 public init(snapshot: PreferencesSnapshot = .defaults, selectedColor: Int = 0, loginPreferred: Bool = false, diagnosticsOptIn: Bool = false, themeMode: ThemeMode = .system) {
  version = 1; self.snapshot = snapshot; self.selectedColor = selectedColor
  self.loginPreferred = loginPreferred; self.diagnosticsOptIn = diagnosticsOptIn; self.themeMode = themeMode
 }
 private enum CodingKeys: String, CodingKey { case version, snapshot, selectedColor, loginPreferred, diagnosticsOptIn, themeMode }
 /// Settings saved before the theme choice existed follow the system appearance.
 public init(from decoder: Decoder) throws {
  let c = try decoder.container(keyedBy: CodingKeys.self)
  version = try c.decode(Int.self, forKey: .version); snapshot = try c.decode(PreferencesSnapshot.self, forKey: .snapshot)
  selectedColor = try c.decode(Int.self, forKey: .selectedColor); loginPreferred = try c.decode(Bool.self, forKey: .loginPreferred)
  diagnosticsOptIn = try c.decode(Bool.self, forKey: .diagnosticsOptIn)
  themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
 }
 func with(snapshot: PreferencesSnapshot? = nil, selectedColor: Int? = nil, loginPreferred: Bool? = nil,
           diagnosticsOptIn: Bool? = nil, themeMode: ThemeMode? = nil) -> StoredPreferencesV1 {
  StoredPreferencesV1(snapshot: snapshot ?? self.snapshot, selectedColor: selectedColor ?? self.selectedColor,
   loginPreferred: loginPreferred ?? self.loginPreferred, diagnosticsOptIn: diagnosticsOptIn ?? self.diagnosticsOptIn,
   themeMode: themeMode ?? self.themeMode)
 }
 public func validate() throws {
  guard version == 1 else { throw PreferencesError.unsupportedVersion }
  guard (0..<25).contains(selectedColor) else { throw PreferencesError.invalidColor }
 }
}
@MainActor public final class PreferencesController {
 public private(set) var settings: StoredPreferencesV1
 public var snapshot: PreferencesSnapshot { settings.snapshot }
 public private(set) var recoveredInvalidStorage = false
 private let defaults: UserDefaults
 private var persist: ((Data) throws -> Void)?
 private let publish: (PreferencesSnapshot) -> Void
 public init(defaults: UserDefaults, publish: @escaping (PreferencesSnapshot) -> Void) {
  self.defaults = defaults; self.publish = publish; settings = StoredPreferencesV1()
  if let bytes = defaults.data(forKey:"preferences.v1") {
   do { let decoded = try JSONDecoder().decode(StoredPreferencesV1.self,from:bytes); try decoded.validate(); settings = decoded }
   catch { recoveredInvalidStorage = true }
  }
 }
 public convenience init(defaults: UserDefaults, storedData: Data?, persist: @escaping (Data) throws -> Void, publish: @escaping (PreferencesSnapshot) -> Void) throws {
  self.init(defaults:defaults,publish:publish)
  if let storedData { let decoded=try JSONDecoder().decode(StoredPreferencesV1.self,from:storedData); try decoded.validate(); settings=decoded }
  self.persist=persist
  if storedData == nil { try persist(JSONEncoder().encode(settings)) }
 }
 public func replace(_ value: PreferencesSnapshot) throws {
  try replaceSettings(settings.with(snapshot:value))
 }
 public func replaceSettings(_ value: StoredPreferencesV1) throws {
  try value.validate()
  let bytes = try JSONEncoder().encode(value)
  try persist?(bytes)
  adoptValidated(value, bytes:bytes)
 }
 /// The caller has already committed these exact bytes in the shared database transaction.
 public func adoptCommittedSettings(_ value:StoredPreferencesV1) throws {
  try value.validate(); adoptValidated(value,bytes:try JSONEncoder().encode(value))
 }
 private func adoptValidated(_ value:StoredPreferencesV1, bytes:Data) {
  defaults.set(bytes,forKey:"preferences.v1"); settings=value; publish(value.snapshot)
 }
 public func setAuto(_ value: Bool) throws {
  let s = snapshot
  try replace(PreferencesSnapshot(autoEnabled:value,typoEnabled:s.typoEnabled,yoEnabled:s.yoEnabled,singleShiftEnabled:s.singleShiftEnabled,optionEnabled:s.optionEnabled,splitShiftEnabled:s.splitShiftEnabled,plainPasteEnabled:s.plainPasteEnabled,soundEnabled:s.soundEnabled,layoutSwitchShortcut:s.layoutSwitchShortcut))
 }
 public func setSelectedColor(_ value: Int) throws {
  try replaceSettings(settings.with(selectedColor:value))
 }
 public func setLoginPreferred(_ value: Bool) throws {
  try replaceSettings(settings.with(loginPreferred:value))
 }
 public func setDiagnosticsOptIn(_ value: Bool) throws {
  try replaceSettings(settings.with(diagnosticsOptIn:value))
 }
 public func setThemeMode(_ value: ThemeMode) throws { try replaceSettings(settings.with(themeMode:value)) }
 public func exportPreferences() throws -> Data { try JSONEncoder().encode(settings) }
 public func importPreferences(_ bytes: Data) throws { try replaceSettings(JSONDecoder().decode(StoredPreferencesV1.self,from:bytes)) }
}
