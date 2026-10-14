import NecarambaCore
import XCTest

@testable import NecarambaMac

final class AXSelectionProofTests: XCTestCase {
  func testSelectedToCollapsedChangeAbortsBeforeAnyPost() {
    assertModeRace(first: NSRange(location: 2, length: 4), second: NSRange(location: 6, length: 0))
  }
  func testCollapsedToSelectedChangeAbortsBeforeAnyPost() {
    assertModeRace(first: NSRange(location: 6, length: 0), second: NSRange(location: 2, length: 4))
  }
  private func assertModeRace(first: NSRange, second: NSRange) {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "a", layout: .init(rawValue: "US"), qualified: true)
    let reader = ProofReader()
    reader.range = first
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader)
    adapter.inputGeneration = { 1 }
    let evidence =
      first.length == 0
      ? adapter.suffix("word", in: context.current()!)! : adapter.selected(in: context.current()!)!
    var posts = 0
    adapter.execute = { _, _, _, preflight in
      reader.range = second
      guard preflight() else { return .aborted }
      posts += 1
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .aborted)
    XCTAssertEqual(posts, 0)
  }
  func testGenerationCapturedBeforeInitialAXRead() {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "a", layout: .init(rawValue: "US"), qualified: true)
    let reader = ProofReader()
    var generation: UInt64 = 1
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader)
    adapter.inputGeneration = { generation }
    reader.onRead = { generation += 1 }
    XCTAssertNil(adapter.selected(in: context.current()!))
  }
}
private final class ProofReader: AXSelectionReading {
  let id = UUID()
  var range = NSRange(location: 2, length: 4)
  var onRead: () -> Void = {}
  func read(in token: ContextToken) -> AXTextSnapshot? {
    onRead()
    return .init(identity: id, value: "A word Z", range: range)
  }
}
