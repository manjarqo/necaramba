import XCTest
import NecarambaCore
@testable import NecarambaMac
final class PreferencesControllerTests: XCTestCase {
 func testPersistenceAndSinglePublication() async throws {
  try await MainActor.run {
   let name = "NecarambaTests.\(UUID())"
   let defaults = UserDefaults(suiteName:name)!
   defer { defaults.removePersistentDomain(forName:name) }
   var values:[PreferencesSnapshot] = []
   let controller = PreferencesController(defaults:defaults) { values.append($0) }
   XCTAssertFalse(controller.snapshot.autoEnabled)
   try controller.setAuto(true)
   XCTAssertEqual(values.count,1)
   XCTAssertTrue(PreferencesController(defaults:defaults) { _ in }.snapshot.autoEnabled)
   XCTAssertThrowsError(try controller.setSelectedColor(25))
   XCTAssertEqual(controller.settings.selectedColor,0)
  }
 }
}
