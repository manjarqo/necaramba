import NecarambaCore
import XCTest

@testable import NecarambaMac

final class NativeInputControllerTests: XCTestCase {
  func testInstallCompletionFollowsActualRuntimeVersion() {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    let done = expectation(description: "installed")
    controller.install(.init(modelVersion: 42)) { version in
      XCTAssertEqual(version, 42)
      XCTAssertEqual(controller.runtime.installedModelVersion, 42)
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    wait(for: [done], timeout: 2)
  }
  func testUnsupportedControllerManualActionAborts() {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    XCTAssertEqual(controller.manualCorrection(), .aborted)
  }
}

private final class FacadeContext: ContextRefreshing {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
  func refresh() -> ContextToken? { token }
}
private final class FacadePermissions: PermissionReading {
  func current() -> PermissionState {
    .init(listen: true, post: true, ax: true, secureInput: false)
  }
  func request(_ kind: PermissionKind) { XCTFail("No permission request allowed") }
}
private final class FacadeSelection: SelectionAccess {
  var reads = 0
  func selected(in token: ContextToken) -> SelectionEvidence? {
    reads += 1
    return nil
  }
  func suffix(_ text: String, in token: ContextToken) -> SelectionEvidence? { nil }
  func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult {
    XCTFail("Unexpected mutation")
    return .uncertain
  }
}
private final class FacadeClipboard: ClipboardAccess {
  var reads = 0
  var changeCount: Int { 0 }
  func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
    reads += 1
    return .init(items: [], changeCount: 0)
  }
  func write(_ items: [PasteboardItem]) throws -> Int {
    XCTFail("Unexpected clipboard write")
    return 0
  }
}
extension NativeInputControllerTests {
  func testPlainPasteUsesCapturedFocusInsteadOfCurrentFocus() {
    let context = FacadeContext()
    let selection = FacadeSelection()
    let clipboard = FacadeClipboard()
    let controller = NativeInputController(
      permissions: FacadePermissions(), editingContext: context, selectionAccess: selection)
    let original = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    XCTAssertEqual(controller.plainPaste(in: original, clipboard: clipboard), .aborted)
    XCTAssertEqual(selection.reads, 0)
    XCTAssertEqual(clipboard.reads, 0)
  }
}
