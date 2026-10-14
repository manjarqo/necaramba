import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class PermissionRuntimeControllerTests: XCTestCase {
    func testPermissionTransitionsRestartRuntimeButFocusAndSecureInputDoNot() {
        let permissions = RuntimePermissions()
        var actions: [String] = []
        let controller = PermissionRuntimeController(permissions: permissions,
            start: { actions.append("start"); return true }, stop: { actions.append("stop") }, isRunning: { true })
        XCTAssertTrue(controller.refresh())
        XCTAssertTrue(controller.refresh())
        permissions.state = .init(listen: true, post: true, ax: false, secureInput: false)
        XCTAssertTrue(controller.refresh())
        permissions.state = .init(listen: true, post: true, ax: true, secureInput: false)
        XCTAssertTrue(controller.refresh())
        permissions.state = .init(listen: true, post: true, ax: true, secureInput: true)
        XCTAssertTrue(controller.refresh())
        permissions.state = .init(listen: false, post: true, ax: true, secureInput: true)
        XCTAssertTrue(controller.refresh())
        XCTAssertEqual(actions, ["start", "stop", "start", "stop", "start", "stop", "start"])
        XCTAssertEqual(permissions.requests, [])
    }
    func testIndependentTapFailureRestartsEvenWithUnchangedPermissions() {
        let permissions = RuntimePermissions()
        var running = false
        var actions: [String] = []
        let controller = PermissionRuntimeController(permissions: permissions,
            start: { actions.append("start"); running = true; return true },
            stop: { actions.append("stop"); running = false }, isRunning: { running })
        XCTAssertTrue(controller.refresh())
        running = false // The OS stopped the tap without changing TCC grants.
        XCTAssertTrue(controller.refresh())
        XCTAssertTrue(running)
        XCTAssertEqual(actions, ["start", "stop", "start"])
    }
    func testFailedRestartReportsStoppedAndAllowsRetryWithoutPermissionChange() {
        let permissions = RuntimePermissions()
        var canStart = true
        let controller = PermissionRuntimeController(permissions: permissions, start: { canStart }, stop: {}, isRunning: { canStart })
        XCTAssertTrue(controller.refresh())
        canStart = false
        permissions.state = .init(listen: true, post: true, ax: true, secureInput: false)
        XCTAssertFalse(controller.refresh())
        canStart = true
        XCTAssertTrue(controller.refresh())
    }
}
private final class RuntimePermissions: PermissionReading {
    var state = PermissionState(listen: true, post: false, ax: false, secureInput: false)
    var requests: [PermissionKind] = []
    func current() -> PermissionState { state }
    func request(_ kind: PermissionKind) { requests.append(kind) }
}
