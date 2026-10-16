import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ApplicationProfileRegistryTests: XCTestCase {
  override func tearDown() {
    ApplicationProfileRegistry.shared.install(.builtIn)
    super.tearDown()
  }

  func testInstalledProfilesDriveEveryCompatibilityDecision() {
    XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: "com.example.electron"))
    ApplicationProfileRegistry.shared.install(.init([
      .init(bundleID: "com.example.electron", accessibilityActivation: .manual, terminalProxyHost: true),
      .init(bundleID: "com.example.browser", accessibilityActivation: .enhanced, temporarySpace: true),
      .init(bundleID: "com.example.terminal", nativeTerminal: true),
    ]))
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.example.electron"), "AXManualAccessibility")
    XCTAssertEqual(ChromiumAccessibilityActivation.attribute(for: "com.example.browser"), "AXEnhancedUserInterface")
    XCTAssertTrue(AXTerminalProxyMetadata.isHost("com.example.electron"))
    XCTAssertTrue(ReplacementEventSequence.usesTemporarySpace(bundleID: "com.example.browser", selected: false))
    XCTAssertFalse(ReplacementEventSequence.usesTemporarySpace(bundleID: "com.example.browser", selected: true))
    XCTAssertTrue(NativeInputController.isNativeTerminal("com.example.terminal"))
    // Replaced data no longer carries the former built-in applications.
    XCTAssertNil(ChromiumAccessibilityActivation.attribute(for: "com.stablyai.orca"))
    XCTAssertFalse(AXTerminalProxyMetadata.isHost("org.tabby"))
    XCTAssertFalse(NativeInputController.isNativeTerminal("com.apple.Terminal"))
  }

  func testDevelopmentPackageSignsTheRepositoryProfiles() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let package = root.appendingPathComponent("App/macos/Runner/Release/BundledRules/Development")
    let encoded = try JSONDecoder().decode([String: String].self,
      from: Data(contentsOf: package.appendingPathComponent("DevelopmentTrustedRuleKeys.json")))
    let keys = encoded.compactMapValues { Data(base64Encoded: $0) }
    let verifier = RulePackageVerifier(trustedKeys: keys, appVersion: "1.0.0")
    let profiles = try verifier.verifyProfiles(
      manifest: Data(contentsOf: package.appendingPathComponent("manifest.json")),
      profiles: Data(contentsOf: root.appendingPathComponent("Resources/Rules/application-profiles-v1.json")),
      signature: Data(contentsOf: package.appendingPathComponent("profiles.signature.ed25519")))
    XCTAssertEqual(profiles, .builtIn)
  }

  func testPackagedProfilesFileEqualsTheBuiltInFallback() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/Rules/application-profiles-v1.json"))
    XCTAssertEqual(try ApplicationProfiles(json: data), .builtIn)
  }
}
