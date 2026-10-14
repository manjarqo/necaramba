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

extension LayoutConverterTests {
    func testExplicitANSIAlphabetPhysicalMappingAndUnsupportedModifiers() {
        let us = LayoutID(rawValue: "US"), ru = LayoutID(rawValue: "RU")
        let map = LayoutMapping(source: us, target: ru, pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
        let context = ContextToken(pid: 1, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
        let keys: [UInt16] = [5, 4, 11, 2, 17, 45]
        let events = keys.map { InputEvent(kind: .down, keyCode: $0, modifiers: [], timestampNanos: 1, layout: us, context: context, origin: .physical, text: "not used", isRepeat: false) }
        XCTAssertEqual(LayoutConverter.convert(keys: events, to: ru, mappings: [map]), "привет")
        let option = InputEvent(kind: .down, keyCode: 5, modifiers: [.option], timestampNanos: 1, layout: us, context: context, origin: .physical, text: "g", isRepeat: false)
        XCTAssertNil(LayoutConverter.convert(keys: [option], to: ru, mappings: [map]))
    }
}
