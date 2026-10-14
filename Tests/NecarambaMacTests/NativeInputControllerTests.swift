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
