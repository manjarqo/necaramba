import CoreFoundation
import NecarambaCore
import XCTest

@testable import NecarambaMac

final class AXSelectionProofTests: XCTestCase {
  func testMissingOptionalMarkedRangeAllowedOnlyForExplicitManualDirectLayout() {
    XCTAssertTrue(AXCompositionProof.permits(
      markedRange: nil, attributeUnavailable: true, manual: true, directKeyboardLayout: true))
    for flags in [(false, true), (true, false), (false, false)] {
      XCTAssertFalse(AXCompositionProof.permits(
        markedRange: nil, attributeUnavailable: true, manual: flags.0,
        directKeyboardLayout: flags.1))
    }
    XCTAssertFalse(AXCompositionProof.permits(
      markedRange: nil, attributeUnavailable: false, manual: true, directKeyboardLayout: true))
  }

  func testPresentMarkedOrMalformedRangeRejectedEvenInManualMode() {
    for range in [CFRange(location: 0, length: 1), CFRange(location: 0, length: -1),
                  CFRange(location: -2, length: 0)] {
      XCTAssertFalse(AXCompositionProof.permits(
        markedRange: range, attributeUnavailable: false, manual: true,
        directKeyboardLayout: true))
    }
    XCTAssertTrue(AXCompositionProof.permits(
      markedRange: CFRange(location: 0, length: 0), attributeUnavailable: false,
      manual: false, directKeyboardLayout: false))
  }

  func testSelectedToCollapsedChangeAbortsBeforeAnyPost() {
    assertModeRace(first: NSRange(location: 2, length: 4), second: NSRange(location: 6, length: 0))
  }
  func testCollapsedToSelectedChangeAbortsBeforeAnyPost() {
    assertModeRace(first: NSRange(location: 6, length: 0), second: NSRange(location: 2, length: 4))
  }
  func testDelayedReadbackCommitsOnlyAfterTargetConsumesPostedKeys() {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    var reads = 0
    adapter.execute = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        if reads == 3 {
          reader.value = "A WORD Z"
          reader.range = NSRange(location: 6, length: 0)
        }
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
  }

  func testMatchingReplacementWithChangedSurroundingTextIsUncertain() {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.execute = { _, _, _, _ in
      reader.value = "B WORD Z"
      reader.range = NSRange(location: 6, length: 0)
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
  }

  func testReadbackTimeoutNeverRepeatsMutation() {
    var elapsed: TimeInterval = 0
    let (adapter, _, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.execute = { _, _, _, _ in posts += 1; return .committed }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testGenerationChangeDuringDelayedReadbackStopsImmediately() {
    var elapsed: TimeInterval = 0
    var generation: UInt64 = 1
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    adapter.inputGeneration = { generation }
    let evidence = adapter.selected(in: token)!
    adapter.execute = { _, _, _, _ in
      reader.onRead = { generation = 2 }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
    XCTAssertEqual(elapsed, 0)
  }

  func testIdentityChangeDuringReadbackIsUncertain() {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.execute = { _, _, _, _ in
      reader.id = UUID()
      reader.value = "A WORD Z"
      reader.range = NSRange(location: 6, length: 0)
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
  }

  func testTrackedManualSuffixOnEmptyProxyIsDispatchedWithoutClaimingVerification() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var posts = 0
    adapter.execute = { evidence, replacement, selected, preflight in
      XCTAssertEqual(evidence.text, "word ")
      XCTAssertEqual(replacement, "WORD ")
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      posts += 1
      return .committed
    }
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token), with: "WORD "), .dispatched)
    XCTAssertEqual(posts, 1)
  }

  func testTrackedSuffixRejectsReadableFieldsAutomaticModeAndUntrustedEvents() {
    let (adapter, reader, token) = fixture(manual: true)
    adapter.execute = { _, _, _, _ in XCTFail("Must not post"); return .committed }
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token), with: "WORD "), .aborted)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token, origin: .foreignSynthetic), with: "WORD "), .aborted)
    let (automatic, empty, other) = fixture()
    empty.value = ""
    empty.range = NSRange(location: 0, length: 0)
    automatic.execute = { _, _, _, _ in XCTFail("Must not post"); return .committed }
    XCTAssertEqual(automatic.replaceTrackedSuffix(word(other), with: "WORD "), .aborted)
  }

  func testTrackedProxyChangeBeforeDestructionAborts() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.execute = { _, _, _, preflight in
      reader.id = UUID()
      return preflight() ? .committed : .aborted
    }
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token), with: "WORD "), .aborted)
  }

  func testTrackedPartialMutationRemainsUncertainAndIsNeverRetried() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var posts = 0
    adapter.execute = { _, _, _, _ in posts += 1; return .uncertain }
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token), with: "WORD "), .uncertain)
    XCTAssertEqual(posts, 1)
  }

  func testDeadlineOverrunCannotCommitEvenMatchingReadback() {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    adapter.execute = { _, _, _, _ in
      reader.onRead = {
        elapsed = 0.101
        reader.value = "A WORD Z"
        reader.range = NSRange(location: 6, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
  }

  func testTrackedReadableResultStillDoesNotProveOriginalSuffix() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.execute = { _, _, _, _ in
      reader.value = "WORD "
      reader.range = NSRange(location: 5, length: 0)
      return .committed
    }
    XCTAssertEqual(adapter.replaceTrackedSuffix(word(token), with: "WORD "), .dispatched)
  }

  func testTrackedSubmissionDelimitersAbortWithoutPosting() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.execute = { _, _, _, _ in XCTFail("Submission must never be replayed"); return .committed }
    let original = word(token)
    for delimiter in ["\n", "\r", "\t", "!\n", " \r", "?\t"] {
      let submitted = BufferedWord(text: original.text, events: original.events,
        context: original.context, layout: original.layout, delimiter: delimiter)
      XCTAssertEqual(adapter.replaceTrackedSuffix(submitted, with: "WORD" + delimiter), .aborted)
    }
  }

  private func word(_ token: ContextToken, origin: EventOrigin = .physical) -> BufferedWord {
    let layout = LayoutID(rawValue: "US")
    let events = "word".map { character in
      InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
        layout: layout, context: token, origin: origin, text: String(character), isRepeat: false)
    }
    return .init(text: "word", events: events, context: token, layout: layout, delimiter: " ")
  }

  private func fixture(
    manual: Bool = false,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) -> (AXSelectionAdapter, ProofReader, ContextToken) {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "a", layout: .init(rawValue: "US"), qualified: true)
    let reader = ProofReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { manual }, now: now, wait: wait)
    adapter.inputGeneration = { 1 }
    return (adapter, reader, context.current()!)
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
  var id = UUID()
  var value = "A word Z"
  var range = NSRange(location: 2, length: 4)
  var onRead: () -> Void = {}
  func read(in token: ContextToken) -> AXTextSnapshot? {
    onRead()
    return .init(identity: id, value: value, range: range)
  }
}
