import XCTest
import NecarambaCore
@testable import NecarambaMac

final class PermissionSettingsTests: XCTestCase {
    func testExplicitRequestOpensMatchingPrivacyPaneEveryTime() {
        for version in [12, 13, 27] {
        let base = version >= 13 ? "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" : "x-apple.systempreferences:com.apple.preference.security"
        for (kind, pane) in [(PermissionKind.listen, "Privacy_ListenEvent"), (.post, "Privacy_Accessibility"), (.ax, "Privacy_Accessibility")] {
            var actions: [String] = []
            let api = SystemPermissionAPI(requestAccess: { actions.append("request:\($0.rawValue)") }, openSettings: {
                actions.append($0.absoluteString); return true
            }, osMajorVersion: version)
            api.request(kind)
            api.request(kind)
            XCTAssertEqual(actions, ["request:\(kind.rawValue)", "\(base)?\(pane)", "request:\(kind.rawValue)", "\(base)?\(pane)"])
        }
    }
    }
    func testUnavailableDeepLinkFallsBackToPrivacySettings() {
        var urls: [String] = []
        let api = SystemPermissionAPI(requestAccess: { _ in }, openSettings: {
            urls.append($0.absoluteString); return urls.count > 1
        }, osMajorVersion: 13)
        api.request(.listen)
        XCTAssertEqual(urls, ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent", "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"])
    }
}
