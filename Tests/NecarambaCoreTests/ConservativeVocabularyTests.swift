import XCTest
@testable import NecarambaCore

final class ConservativeVocabularyTests: XCTestCase {
    func testCommonConversationWordsConvertAndCorrectWordsStayUnchanged() {
        let source = LayoutID(rawValue: "US"), target = LayoutID(rawValue: "RU")
        let mapping = LayoutMapping(source: source, target: target,
            pairs: ["r":"к", "f":"а", "l":"д", "t":"е", "k":"л", "x":"ч", "v":"м"])
        let snapshot = ConservativeVocabulary.augment(.init(modelVersion: 1, mappings: [mapping]))
        let engine = LinguisticEngine(snapshot: snapshot)
        let context = ContextToken(pid: 1, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
        for (input, expected) in [("rfr", "как"), ("ltkf", "дела"), ("xtv", "чем")] {
            let word = BufferedWord(text: input, events: [], context: context, layout: source, delimiter: " ")
            guard case .replace(let result) = engine.decide(word: word, preferences: .defaults, excludedWords: []) else {
                XCTFail("Common word must be available: \(expected)"); continue
            }
            XCTAssertEqual(result.replacement, expected)
            XCTAssertEqual(engine.decide(word: word, preferences: .defaults, excludedWords: [expected]), .unchanged(.excludedWord))
        }
        for text in ["как", "дела", "чем", "занимаешься", "hello", "the", "you"] {
            let word = BufferedWord(text: text, events: [], context: context, layout: target, delimiter: " ")
            XCTAssertEqual(engine.decide(word: word, preferences: .defaults, excludedWords: []), .unchanged(.correct))
        }
    }
    func testAugmentationPreservesPackageRulesAndDoesNotDuplicateLexemes() {
        let lexeme = Lexeme(word: "как", language: .russian, frequencyBand: 7)
        let snapshot = RuleSnapshot(modelVersion: 9, lexicon: [lexeme], protectedTokens: ["rfr"])
        let augmented = ConservativeVocabulary.augment(snapshot)
        XCTAssertEqual(augmented.lexicon.filter { $0.word == "как" }, [lexeme])
        XCTAssertEqual(augmented.protectedTokens, ["rfr"])
        XCTAssertEqual(augmented.modelVersion, 9)
        XCTAssertEqual(ConservativeVocabulary.augment(augmented), augmented)
    }
}
