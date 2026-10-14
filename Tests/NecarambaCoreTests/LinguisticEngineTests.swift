import XCTest
@testable import NecarambaCore
final class LinguisticEngineTests: XCTestCase {
    func word(_ text: String, layout: String = "US") -> BufferedWord {
        .init(text: text, events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: .init(rawValue: layout), delimiter: " ")
    }
    func replacement(_ decision: LinguisticDecision) -> Correction? {
        if case .replace(let value) = decision { return value }; return nil
    }
    func testSelectionLayoutKnownTargetUnknownSource() {
        let m = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
        let e = LinguisticEngine(snapshot: .init(modelVersion: 7, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 5)], mappings: [m]))
        XCTAssertEqual(replacement(e.decide(word: word("Ghbdtn"), preferences: .defaults, excludedWords: []))?.replacement, "Привет")
        XCTAssertEqual(e.decide(word: word("ghbdtn"), preferences: .defaults, excludedWords: ["ПРИВЕТ"]), .unchanged(.excludedWord))
    }
    func testExactTypoYoAndCase() {
        let e = LinguisticEngine(snapshot: .init(modelVersion: 1, lexicon: [.init(word: "the", language: .english, frequencyBand: 5), .init(word: "ёлка", language: .russian, frequencyBand: 5)], typos: [.init(source: "teh", target: "the", caseSensitive: false)], yoRules: [.init(source: "елка", target: "ёлка", caseSensitive: false)]))
        XCTAssertEqual(replacement(e.decide(word: word("Teh"), preferences: .defaults, excludedWords: []))?.replacement, "The")
        XCTAssertEqual(replacement(e.decide(word: word("елка", layout: "RU"), preferences: .defaults, excludedWords: []))?.replacement, "ёлка")
        XCTAssertEqual(e.decide(word: word("елка"), preferences: .defaults, excludedWords: ["ЕЛКА"]), .unchanged(.excludedWord))
        XCTAssertEqual(e.decide(word: word("teh"), preferences: .init(typoEnabled: false), excludedWords: []), .unchanged(.ambiguous))
    }
    func testConflictingRulesAndUnknownWordsAbstain() {
        let e = LinguisticEngine(snapshot: .init(modelVersion: 1, yoRules: [.init(source: "все", target: "всё", caseSensitive: false), .init(source: "все", target: "все", caseSensitive: false)]))
        XCTAssertEqual(e.decide(word: word("все"), preferences: .defaults, excludedWords: []), .unchanged(.ambiguous))
        XCTAssertEqual(e.decide(word: word("unknown"), preferences: .defaults, excludedWords: []), .unchanged(.ambiguous))
    }
    func testProtectedAndDoubleCaps() {
        let e = LinguisticEngine(snapshot: .init(modelVersion: 1, lexicon: [.init(word: "hello", language: .english, frequencyBand: 4)], protectedTokens: ["все"]))
        for text in ["API", "https://a.ru", "a@b.ru", "/tmp/a", "hello2", "fooBar", "все", "aб"] {
            XCTAssertEqual(e.decide(word: word(text), preferences: .defaults, excludedWords: []), .unchanged(.protectedToken))
        }
        XCTAssertEqual(replacement(e.decide(word: word("HEllo"), preferences: .defaults, excludedWords: []))?.replacement, "Hello")
    }
    func testNFCAndBothKnownAbstain() {
        let m = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["a":"я"])
        let e = LinguisticEngine(snapshot: .init(modelVersion: 1, lexicon: [.init(word: "a", language: .english, frequencyBand: 1), .init(word: "я", language: .russian, frequencyBand: 1), .init(word: "é", language: .english, frequencyBand: 1)], mappings: [m]))
        XCTAssertEqual(e.decide(word: word("a"), preferences: .defaults, excludedWords: []), .unchanged(.ambiguous))
        XCTAssertEqual(e.decide(word: word("e\u{301}"), preferences: .defaults, excludedWords: []), .unchanged(.correct))
    }
}
extension LinguisticEngineTests {
    func testPhysicalWordUsesKeyCodesAndIntermediateExcludedWord() {
        let map = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
        let model = RuleSnapshot(modelVersion: 1, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1), .init(word: "hi", language: .english, frequencyBand: 1)], typos: [.init(source: "привет", target: "hi", caseSensitive: false)], mappings: [map])
        let e = LinguisticEngine(snapshot: model)
        let w = word("ghbdtn")
        let keys: [UInt16] = [5, 4, 11, 2, 17, 45]
        let events = keys.map { InputEvent(kind: .down, keyCode: $0, modifiers: [], timestampNanos: 1, layout: w.layout, context: w.context, origin: .physical, text: "ignored", isRepeat: false) }
        let typed = BufferedWord(text: w.text, events: events, context: w.context, layout: w.layout, delimiter: w.delimiter)
        XCTAssertEqual(replacement(e.decide(word: typed, preferences: .defaults, excludedWords: []))?.replacement, "hi")
        XCTAssertEqual(e.decide(word: typed, preferences: .defaults, excludedWords: ["привет"]), .unchanged(.excludedWord))
    }
}
extension LinguisticEngineTests {
    func testConfirmedCapsLockLayoutCandidatePreservesUppercase() {
        let map = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
        let e = LinguisticEngine(snapshot: .init(modelVersion: 1, lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)], mappings: [map]))
        let w = word("GHBDTN")
        let keys: [UInt16] = [5, 4, 11, 2, 17, 45]
        let events = keys.map { InputEvent(kind: .down, keyCode: $0, modifiers: [.capsLock], timestampNanos: 1, layout: w.layout, context: w.context, origin: .physical, text: nil, isRepeat: false) }
        XCTAssertEqual(replacement(e.decide(word: .init(text: w.text, events: events, context: w.context, layout: w.layout, delimiter: " "), preferences: .defaults, excludedWords: []))?.replacement, "ПРИВЕТ")
    }
}
