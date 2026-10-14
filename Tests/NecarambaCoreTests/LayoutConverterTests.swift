import XCTest
@testable import NecarambaCore
final class LayoutConverterTests: XCTestCase {
    func testGraphemesAndCase() {
        let map = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
        XCTAssertEqual(LayoutConverter.convert("Ghbdtn🙂e\u{301}", mapping: map), "Привет🙂e\u{301}")
    }
    func testPhysicalConversionRequiresExplicitMapAndNeverUsesEventText() {
        let source = LayoutID(rawValue: "fixture.us"), target = LayoutID(rawValue: "fixture.ru")
        let context = ContextToken(pid: 1, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
        let event = InputEvent(kind: .down, keyCode: 5, modifiers: [.shift], timestampNanos: 1, layout: source, context: context, origin: .physical, text: "WRONG", isRepeat: false)
        XCTAssertNil(LayoutConverter.convert(keys: [event], to: target, mappings: []))
        let physical = PhysicalLayoutMapping(source: source, target: target, entries: [.init(keyCode: 5, modifiers: [.shift], text: "П")])
        XCTAssertEqual(LayoutConverter.convert(keys: [event], to: target, physicalMappings: [physical]), "П")
    }
    func testUppercaseFallbackRequiresSingleGrapheme() {
        XCTAssertEqual(LayoutConverter.convert("A", mapping: .init(source: .init(rawValue: "a"), target: .init(rawValue: "b"), pairs: ["a":"xy"])), "A")
    }
}
