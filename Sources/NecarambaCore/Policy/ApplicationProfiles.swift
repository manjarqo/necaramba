import Foundation

/// How a Chromium/Gecko/Electron application is asked to build its accessibility tree.
public enum AccessibilityActivation: String, Sendable, Equatable { case manual, enhanced }

/// Data-driven compatibility facts for one exact application bundle identifier.
public struct ApplicationProfile: Sendable, Equatable {
  public let bundleID: String
  public let accessibilityActivation: AccessibilityActivation?
  /// Its xterm helper textarea transports terminal input (never terminal text).
  public let terminalProxyHost: Bool
  /// Browser editors that need a temporary Space before suffix deletion.
  public let temporarySpace: Bool
  /// A native terminal: its selection is output, so clipboard replacement is unsafe.
  public let nativeTerminal: Bool
  public init(bundleID: String, accessibilityActivation: AccessibilityActivation? = nil,
              terminalProxyHost: Bool = false, temporarySpace: Bool = false, nativeTerminal: Bool = false) {
    self.bundleID = bundleID; self.accessibilityActivation = accessibilityActivation
    self.terminalProxyHost = terminalProxyHost; self.temporarySpace = temporarySpace
    self.nativeTerminal = nativeTerminal
  }
}

public struct ApplicationProfiles: Sendable, Equatable {
  public static let maximumSize = 256 * 1024
  private let byBundle: [String: ApplicationProfile]
  public var all: [ApplicationProfile] { byBundle.values.sorted { $0.bundleID < $1.bundleID } }
  public init(_ profiles: [ApplicationProfile]) {
    byBundle = Dictionary(profiles.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
  }
  public func profile(for bundleID: String) -> ApplicationProfile? { byBundle[bundleID] }

  /// Strict schema 1: exact keys, bounded sizes, unique exact bundle identifiers.
  public init(json data: Data) throws {
    guard data.count <= Self.maximumSize else { throw RuleVerificationError.invalidPayload }
    try StrictRuleJSON.validate(data)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(root.keys) == ["schemaVersion", "profiles"], (root["schemaVersion"] as? Int) == 1,
      let rows = root["profiles"] as? [[String: Any]], rows.count <= 1024
    else { throw RuleVerificationError.invalidPayload }
    let fields: Set<String> = ["bundleID", "accessibilityActivation", "terminalProxyHost", "temporarySpace", "nativeTerminal"]
    var profiles: [ApplicationProfile] = []
    var seen = Set<String>()
    for row in rows {
      guard Set(row.keys) == fields, let bundleID = row["bundleID"] as? String,
        bundleID.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$", options: .regularExpression) != nil,
        seen.insert(bundleID).inserted,
        let proxy = row["terminalProxyHost"] as? Bool, let space = row["temporarySpace"] as? Bool,
        let terminal = row["nativeTerminal"] as? Bool
      else { throw RuleVerificationError.invalidPayload }
      let activation: AccessibilityActivation?
      switch row["accessibilityActivation"] {
      case is NSNull: activation = nil
      case let value as String:
        guard let parsed = AccessibilityActivation(rawValue: value) else { throw RuleVerificationError.invalidPayload }
        activation = parsed
      default: throw RuleVerificationError.invalidPayload
      }
      profiles.append(.init(bundleID: bundleID, accessibilityActivation: activation,
        terminalProxyHost: proxy, temporarySpace: space, nativeTerminal: terminal))
    }
    self.init(profiles)
  }

  /// Used when no verified profiles are packaged; equals Resources/Rules/application-profiles-v1.json.
  public static let builtIn = ApplicationProfiles(
    ["com.readdle.SparkDesktop", "com.vscodium"].map { ApplicationProfile(bundleID: $0, accessibilityActivation: .manual) }
    + ["org.tabby", "com.stablyai.orca"].map {
      ApplicationProfile(bundleID: $0, accessibilityActivation: .manual, terminalProxyHost: true) }
    + [ApplicationProfile(bundleID: "app.zen-browser.zen", accessibilityActivation: .enhanced)]
    + ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"].map {
      ApplicationProfile(bundleID: $0, accessibilityActivation: .enhanced, temporarySpace: true) }
    + ["com.apple.Safari", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly"].map {
      ApplicationProfile(bundleID: $0, temporarySpace: true) }
    + ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
       "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper"].map {
      ApplicationProfile(bundleID: $0, nativeTerminal: true) })
}
