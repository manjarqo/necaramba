import XCTest
import NecarambaCore
@testable import NecarambaMac

final class PermissionTests: XCTestCase {
    func testPostPermissionAndFocusAreRequiredForEditing() {
        let missingPost = PermissionState(listen: true, post: false, ax: true, secureInput: false)
        XCTAssertFalse(CapabilityRegistry.evaluate(missingPost, supportsFocus: true).auto)
        XCTAssertFalse(CapabilityRegistry.evaluate(missingPost, supportsFocus: true).manual)
        let allowed = PermissionState(listen: true, post: true, ax: false, secureInput: false)
        XCTAssertFalse(CapabilityRegistry.evaluate(allowed, supportsFocus: false).auto)
        XCTAssertTrue(CapabilityRegistry.evaluate(allowed, supportsFocus: true).manual)
    }
    func testSecureInputOverridesAllPermissions() {
        let permissions = PermissionState(listen: true, post: true, ax: true, secureInput: true)
        let capabilities = CapabilityRegistry.evaluate(permissions, supportsFocus: true)
        XCTAssertFalse(capabilities.auto)
        XCTAssertFalse(capabilities.selection)
        XCTAssertEqual(capabilities.reason, .secureInput)
    }
    func testReadingNeverRequestsPermissionsAndDoesNotCacheGrants() {
        let api = PermissionAPIStub()
        let monitor = PermissionMonitor(api: api)
        XCTAssertTrue(monitor.current().post)
        api.post = false
        XCTAssertFalse(monitor.current().post)
        XCTAssertEqual(api.requested, [])
        monitor.request(.listen)
        XCTAssertEqual(api.requested, [.listen])
    }
}

private final class PermissionAPIStub: PermissionAPI {
    var post = true
    var requested: [PermissionKind] = []
    func listenAllowed() -> Bool { true }
    func postAllowed() -> Bool { post }
    func axAllowed() -> Bool { true }
    func secureInputEnabled() -> Bool { false }
    func request(_ kind: PermissionKind) { requested.append(kind) }
}
