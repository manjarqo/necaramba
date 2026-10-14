import XCTest

@testable import NecarambaCore

final class RuleValidationTests: XCTestCase {
  func testUnicodeAndBoundaries() throws {
    XCTAssertEqual(try RuleValidation.word("  E\u{301}cole  ").original, "École")
    XCTAssertEqual(
      try RuleValidation.word("Straße").normalized, try RuleValidation.word("STRASSE").normalized)
    XCTAssertNoThrow(try RuleValidation.word(String(repeating: "👩‍💻", count: 20)))
    for value in ["", String(repeating: "a", count: 21), "a=b", "a%b", "12-3", "a\u{0}", "a\nb"] {
      XCTAssertThrowsError(try RuleValidation.word(value))
    }
    XCTAssertNoThrow(try RuleValidation.word("a123"))
  }
}
