import Foundation
import XCTest
@testable import NecarambaCore

final class PackedWordLexiconTests: XCTestCase {
    func testExactMembershipAndLanguageIsolation() throws {
        let lexicon = try PackedOpenLexicon(english: Data("a\nconnector\nground\nzoo\n".utf8), russian: Data("дела\nтоже\nёж\n".utf8))
        for word in ["a", "connector", "ground", "zoo"] { XCTAssertTrue(lexicon.contains(word, language: .english)) }
        for word in ["дела", "тоже", "ёж"] { XCTAssertTrue(lexicon.contains(word, language: .russian)) }
        for word in ["", "Ground", "groun", "grounded", "0", "zz", "тоже"] { XCTAssertFalse(lexicon.contains(word, language: .english)) }
        XCTAssertFalse(lexicon.contains("ground", language: .russian))
    }

    func testBinarySearchMatchesReferenceAcrossManyPrefixes() throws {
        let words = (0..<1024).map { value in
            "a" + String(UnicodeScalar(97 + value / 26 / 26)!) + String(UnicodeScalar(97 + (value / 26) % 26)!) + String(UnicodeScalar(97 + value % 26)!)
        }
        let lexicon = try PackedOpenLexicon(english: Data((words.joined(separator: "\n") + "\n").utf8), russian: Data("я\n".utf8))
        for word in words {
            XCTAssertTrue(lexicon.contains(word, language: .english))
            XCTAssertFalse(lexicon.contains(word + "a", language: .english))
            XCTAssertFalse(lexicon.contains(String(word.dropLast()), language: .english))
        }
    }

    func testMalformedPackedInputsFailClosed() {
        let russian = Data("привет\n".utf8)
        for text in ["", "a", "\n", "a\n\n", "b\na\n", "a\na\n", "A\n", "a1\n", "a b\n", "a\r\n", "привет\n", String(repeating: "a", count: 129) + "\n"] {
            XCTAssertThrowsError(try PackedOpenLexicon(english: Data(text.utf8), russian: russian), text)
        }
        XCTAssertThrowsError(try PackedOpenLexicon(english: Data([255, 10]), russian: russian))
        for text in ["hello\n", "Еж\n", "е\u{301}\n", "я\nа\n", "ё\nя\n"] {
            XCTAssertThrowsError(try PackedOpenLexicon(english: Data("a\n".utf8), russian: Data(text.utf8)), text)
        }
    }

    func testRejectsOversizedDataBeforeScan() {
        XCTAssertThrowsError(try PackedOpenLexicon(english: Data(repeating: 97, count: 64 * 1024 * 1024), russian: Data("я\n".utf8)))
    }
}
