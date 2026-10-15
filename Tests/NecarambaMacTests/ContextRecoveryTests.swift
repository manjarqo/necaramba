import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ContextRecoveryTests: XCTestCase {
  func testExternalInvalidationRequestsRecoveryWithoutRevivingOldEvidence() {
    let permissions = RecoveryPermissions()
    let monitor = ContextMonitor(layouts: RecoveryLayouts(), permissions: permissions, qualifies: { _, _ in true })
    monitor.state.update(pid: 42, bundleID: "test", focusID: "field", layout: .init(rawValue: "RU"), qualified: true)
    let old = monitor.current()!
    XCTAssertFalse(monitor.recoveryPermitted)
    monitor.invalidateAndRequestRecovery(.unknownInput)
    XCTAssertNil(monitor.current())
    XCTAssertNil(monitor.state.gestureContext())
    XCTAssertFalse(monitor.isSafe(old))
    XCTAssertTrue(monitor.recoveryPermitted)
    permissions.state = .init(listen: true, post: true, ax: true, secureInput: true)
    XCTAssertFalse(monitor.recoveryPermitted)
    permissions.state = .init(listen: true, post: true, ax: false, secureInput: false)
    XCTAssertFalse(monitor.recoveryPermitted)
    permissions.state = .init(listen: true, post: true, ax: true, secureInput: false)
    XCTAssertTrue(monitor.recoveryPermitted)
    XCTAssertNil(monitor.current(), "Permission recovery must not resurrect invalidated evidence")
    monitor.stop()
    XCTAssertFalse(monitor.recoveryPermitted)
  }
}
private final class RecoveryPermissions: PermissionReading {
  var state = PermissionState(listen: true, post: true, ax: true, secureInput: false)
  func current() -> PermissionState { state }
  func request(_ kind: PermissionKind) { XCTFail("Must not request permissions") }
}
private final class RecoveryLayouts: LayoutAccess {
  func current() -> LayoutID? { .init(rawValue: "RU") }
  func supported() -> [LayoutID] { [.init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool { XCTFail("Must not switch layouts"); return false }
}
