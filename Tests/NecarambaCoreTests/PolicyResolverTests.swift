import XCTest
@testable import NecarambaCore
final class PolicyResolverTests: XCTestCase {
    func testAllPriorityCombinations() {
        for secure in [false, true] { for listen in [false, true] { for post in [false, true] { for supported in [false, true] { for auto in [false, true] { for profile in [false, true] { for override in [nil, AppOverride.allow, AppOverride.deny] {
            let d = PolicyResolver.resolve(.init(preferences: .init(autoEnabled: auto), appOverride: override, profileAllowsAuto: profile, secureInput: secure, canListen: listen, canPost: post, supportedContext: supported))
            let safe = !secure && listen && post && supported
            XCTAssertEqual(d.manualAllowed, safe)
            XCTAssertEqual(d.autoAllowed, safe && (override == .allow || (override == nil && profile && auto)))
        } } } } } } }
    }
    func testSafetyReasonPrecedence() {
        let d = PolicyResolver.resolve(.init(preferences: .defaults, appOverride: .allow, profileAllowsAuto: true, secureInput: true, canListen: false, canPost: false, supportedContext: false))
        XCTAssertEqual(d.reason, .secureInput)
    }
}
