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
   XCTAssertEqual(controller.snapshot, .defaults)
   try controller.setAuto(true)
   XCTAssertEqual(values.count,1)
   XCTAssertTrue(PreferencesController(defaults:defaults) { _ in }.snapshot.autoEnabled)
   XCTAssertThrowsError(try controller.setSelectedColor(25))
   XCTAssertEqual(controller.settings.selectedColor,0)
  }
 }
 func testCorruptStorageAndInvalidArchiveDoNotPublish() async throws {
  try await MainActor.run {
   let name="NecarambaTests.\(UUID())"; let defaults=UserDefaults(suiteName:name)!
   defer { defaults.removePersistentDomain(forName:name) }
   defaults.set(Data("invalid".utf8),forKey:"preferences.v1")
   var publications=0
   let controller=PreferencesController(defaults:defaults) { _ in publications+=1 }
   XCTAssertTrue(controller.recoveredInvalidStorage)
   XCTAssertEqual(controller.snapshot,.defaults)
   XCTAssertThrowsError(try controller.replaceSettings(StoredPreferencesV1(selectedColor:25)))
   XCTAssertEqual(publications,0)
   try controller.replace(PreferencesSnapshot(autoEnabled:false,typoEnabled:false))
   let archive=try controller.exportPreferences()
   try controller.importPreferences(archive)
   XCTAssertEqual(publications,2)
   XCTAssertFalse(controller.snapshot.typoEnabled)
  }
 }

}
