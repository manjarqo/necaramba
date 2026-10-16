import XCTest
import CryptoKit
@testable import NecarambaCore

final class ApplicationProfilesTests: XCTestCase {
  private let sample = #"{"profiles":[{"accessibilityActivation":"manual","bundleID":"com.stablyai.orca","nativeTerminal":false,"temporarySpace":false,"terminalProxyHost":true}],"schemaVersion":1}"#

  func testStrictProfilesParseKnownFieldsOnly() throws {
    let profiles = try ApplicationProfiles(json: Data(sample.utf8))
    let orca = try XCTUnwrap(profiles.profile(for: "com.stablyai.orca"))
    XCTAssertEqual(orca.accessibilityActivation, .manual)
    XCTAssertTrue(orca.terminalProxyHost)
    XCTAssertNil(profiles.profile(for: "com.stablyai.orca.helper"))
    let invalid = [
      sample.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#),
      sample.replacingOccurrences(of: #""temporarySpace":false"#, with: #""temporarySpace":false,"script":"x""#),
      sample.replacingOccurrences(of: #""manual""#, with: #""everything""#),
      sample.replacingOccurrences(of: "com.stablyai.orca", with: "bad id/../x"),
      sample.replacingOccurrences(of: #"[{"#, with: #"[{"accessibilityActivation":null,"bundleID":"com.stablyai.orca","nativeTerminal":false,"temporarySpace":false,"terminalProxyHost":true},{"#),
      #"{"profiles":[],"schemaVersion":1,"schemaVersion":1}"#,
    ]
    for json in invalid { XCTAssertThrowsError(try ApplicationProfiles(json: Data(json.utf8)), json) }
  }

  func testBuiltInProfilesMatchTheFormerHardCodedApplications() {
    let profiles = ApplicationProfiles.builtIn
    for bundle in ["com.readdle.SparkDesktop", "com.vscodium", "org.tabby", "com.stablyai.orca"] {
      XCTAssertEqual(profiles.profile(for: bundle)?.accessibilityActivation, .manual, bundle)
    }
    for bundle in ["app.zen-browser.zen", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"] {
      XCTAssertEqual(profiles.profile(for: bundle)?.accessibilityActivation, .enhanced, bundle)
    }
    XCTAssertEqual(Set(profiles.all.filter(\.terminalProxyHost).map(\.bundleID)), ["org.tabby", "com.stablyai.orca"])
    XCTAssertEqual(Set(profiles.all.filter(\.temporarySpace).map(\.bundleID)), ["com.apple.Safari", "com.google.Chrome",
      "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.brave.Browser",
      "com.brave.Browser.beta", "com.brave.Browser.nightly"])
    XCTAssertTrue(profiles.profile(for: "com.apple.Terminal")?.nativeTerminal == true)
  }

  func testProfilesSignatureIsBoundToTheRulePackageKeyAndDomain() throws {
    let key = Curve25519.Signing.PrivateKey()
    let manifest = try canonicalManifest(.init(schemaVersion: 1, modelVersion: 1, minimumAppVersion: "1.0.0",
      payloadSize: 1, payloadSHA256: String(repeating: "0", count: 64), keyID: "owner"))
    let profiles = Data(sample.utf8)
    let digest = Data(SHA256.hash(data: profiles))
    let signature = try key.signature(for: Data("NecarambaAppProfiles-v1\0".utf8) + digest)
    let verifier = RulePackageVerifier(trustedKeys: ["owner": key.publicKey.rawRepresentation], appVersion: "1.0.0")
    XCTAssertEqual(try verifier.verifyProfiles(manifest: manifest, profiles: profiles, signature: signature)
      .profile(for: "com.stablyai.orca")?.terminalProxyHost, true)
    let ruleDomain = try key.signature(for: Data("NecarambaRules-v1\0".utf8) + digest)
    XCTAssertThrowsError(try verifier.verifyProfiles(manifest: manifest, profiles: profiles, signature: ruleDomain))
    var tampered = profiles; tampered[tampered.count - 2] = UInt8(ascii: "2")
    XCTAssertThrowsError(try verifier.verifyProfiles(manifest: manifest, profiles: tampered, signature: signature))
    let stranger = RulePackageVerifier(trustedKeys: ["owner": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation], appVersion: "1.0.0")
    XCTAssertThrowsError(try stranger.verifyProfiles(manifest: manifest, profiles: profiles, signature: signature))
  }
}
