import Foundation
import NecarambaCore

public enum PreferencesError: Error { case unsupportedVersion, invalidColor }
public struct StoredPreferencesV1: Codable, Equatable, Sendable {
 public let version: Int
 public let snapshot: PreferencesSnapshot
 public let selectedColor: Int
 public let loginPreferred: Bool
 public let diagnosticsOptIn: Bool
 public init(snapshot: PreferencesSnapshot = .defaults, selectedColor: Int = 0, loginPreferred: Bool = false, diagnosticsOptIn: Bool = false) {
  version = 1; self.snapshot = snapshot; self.selectedColor = selectedColor
  self.loginPreferred = loginPreferred; self.diagnosticsOptIn = diagnosticsOptIn
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
  try replaceSettings(StoredPreferencesV1(snapshot:value,selectedColor:settings.selectedColor,loginPreferred:settings.loginPreferred,diagnosticsOptIn:settings.diagnosticsOptIn))
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
  try replaceSettings(StoredPreferencesV1(snapshot:snapshot,selectedColor:value,loginPreferred:settings.loginPreferred,diagnosticsOptIn:settings.diagnosticsOptIn))
 }
 public func setLoginPreferred(_ value: Bool) throws {
  try replaceSettings(StoredPreferencesV1(snapshot:snapshot,selectedColor:settings.selectedColor,loginPreferred:value,diagnosticsOptIn:settings.diagnosticsOptIn))
 }
 public func setDiagnosticsOptIn(_ value: Bool) throws {
  try replaceSettings(StoredPreferencesV1(snapshot:snapshot,selectedColor:settings.selectedColor,loginPreferred:settings.loginPreferred,diagnosticsOptIn:value))
 }
 public func exportPreferences() throws -> Data { try JSONEncoder().encode(settings) }
 public func importPreferences(_ bytes: Data) throws { try replaceSettings(JSONDecoder().decode(StoredPreferencesV1.self,from:bytes)) }
}
