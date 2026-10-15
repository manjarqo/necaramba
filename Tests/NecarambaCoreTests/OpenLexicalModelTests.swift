import Foundation
import XCTest
@testable import NecarambaCore

final class OpenLexicalModelTests: XCTestCase {
    private func data(version: String = "open-1", schema: Int = 1,
                      languages: [String: [String]] = ["en": ["ground", "connector"], "ru": ["тоже", "переключилось", "ёж"]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "version": version, "languages": languages])
    }

    func testSnapshotReplacesVocabularyAndRetainsBasePolicies() throws {
        let model = try OpenLexicalModel(data: data())
        let mapping = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["q": "й"])
        let rule = ReplacementRule(source: "teh", target: "the", caseSensitive: false)
        let base = RuleSnapshot(modelVersion: 42, lexicon: [.init(word: "obsolete", language: .english, frequencyBand: 9)],
                                typos: [rule], yoRules: [rule], protectedTokens: ["API"], mappings: [mapping])
        let snapshot = model.snapshot(replacingLexiconIn: base)
        XCTAssertEqual(model.version, "open-1")
        XCTAssertEqual(snapshot.modelVersion, 42)
        XCTAssertEqual(Set(snapshot.lexicon.map(\.word)), ["ground", "connector", "тоже", "переключилось", "ёж"])
        XCTAssertTrue(snapshot.lexicon.allSatisfy { $0.frequencyBand == 1 })
        XCTAssertEqual(snapshot.lexicon.filter { $0.language == .english }.count, 2)
        XCTAssertEqual(snapshot.typos, base.typos)
        XCTAssertEqual(snapshot.yoRules, base.yoRules)
        XCTAssertEqual(snapshot.protectedTokens, base.protectedTokens)
        XCTAssertEqual(snapshot.mappings, base.mappings)
    }

    func testInvalidHeadersAndLanguageSetsAreRejected() throws {
        XCTAssertThrowsError(try OpenLexicalModel(data: data(schema: 2)))
        for version in ["", " ", String(repeating: "a", count: 65), "open\n1"] {
            XCTAssertThrowsError(try OpenLexicalModel(data: data(version: version)))
        }
        for languages in [["en": ["hello"]], ["en": ["hello"], "ru": []], ["en": ["hello"], "ru": ["привет"], "fr": ["bonjour"]]] {
            XCTAssertThrowsError(try OpenLexicalModel(data: data(languages: languages)))
        }
    }

    func testInvalidLexemesAndDuplicatesAreRejected() throws {
        for word in ["", "Ground", "two words", "version1", "hello!", "привет", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try OpenLexicalModel(data: data(languages: ["en": [word], "ru": ["привет"]])))
        }
        for word in ["Привет", "hello", "ёё-ё", "е\u{301}"] {
            XCTAssertThrowsError(try OpenLexicalModel(data: data(languages: ["en": ["hello"], "ru": [word]])))
        }
        XCTAssertThrowsError(try OpenLexicalModel(data: data(languages: ["en": ["hello", "hello"], "ru": ["привет"]])))
        XCTAssertThrowsError(try OpenLexicalModel(data: Data("{}".utf8)))
    }

    func testWordCountLimitIsRejected() throws {
        let oversized = try data(languages: ["en": Array(repeating: "a", count: OpenLexicalModel.maximumWordCount), "ru": ["я"]])
        XCTAssertThrowsError(try OpenLexicalModel(data: oversized)) { error in
            guard case OpenLexicalModel.ValidationError.invalidLexicon = error else {
                return XCTFail("Expected word-count validation error, got \(error)")
            }
        }
    }

    func testSizeLimitBeforeDecoding() {
        XCTAssertThrowsError(try OpenLexicalModel(data: Data(repeating: 32, count: 64 * 1024 * 1024 + 1)))
    }
}
