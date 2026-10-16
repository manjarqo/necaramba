import XCTest
import NecarambaCore
@testable import NecarambaMac

final class PhysicalReplayMappingTests: XCTestCase {
  private let en = LayoutID(rawValue: "en")
  private var tables: CapturedLayoutTables {
    .init(layouts: [.init(id: en, entries: [
      .init(keyCode: 4, modifiers: [], text: "h"),
      .init(keyCode: 4, modifiers: [.shift], text: "H"),
      .init(keyCode: 49, modifiers: [], text: " "),
      .init(keyCode: 36, modifiers: [], text: "\n"),
      .init(keyCode: 48, modifiers: [], text: "\t"),
      .init(keyCode: 4, modifiers: [.capsLock], text: "H"),
    ])])
  }
  func testCompletePrintableReplayUsesTargetKeysAndMinimalModifiers() {
    let keys = tables.replayKeys(for: "hH ", in: en)
    XCTAssertEqual(keys?.map(\.keyCode), [4, 4, 49])
    XCTAssertEqual(keys?.map(\.modifiers), [[], [.shift], []])
  }
  func testNavigationKeyCannotMasqueradeAsPrintableCharacter() {
    let unsafe = CapturedLayoutTables(layouts: [.init(id: en, entries: [
      .init(keyCode: 115, modifiers: [], text: "a"),
      .init(keyCode: 122, modifiers: [], text: "b"),
    ])])
    XCTAssertNil(unsafe.replayKeys(for: "a", in: en))
    XCTAssertNil(unsafe.replayKeys(for: "b", in: en))
  }
  func testUnmappedOrActionableCharacterRejectsEntireReplay() {
    for text in ["hello", "h\n", "h\t", "h\u{00a0}", ""] {
      XCTAssertNil(tables.replayKeys(for: text, in: en))
    }
    XCTAssertNil(tables.replayKeys(for: "h", in: LayoutID(rawValue: "missing")))
  }
}
