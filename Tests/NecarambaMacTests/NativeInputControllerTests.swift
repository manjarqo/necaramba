import XCTest
import NecarambaCore
@testable import NecarambaMac
final class NativeInputControllerTests:XCTestCase {
 func testUnsupportedControllerManualActionAborts() {
  let controller=NativeInputController(profiles:CapabilityProfiles())
  XCTAssertEqual(controller.manualCorrection(),.aborted)
 }
}
