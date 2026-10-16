import XCTest
import ApplicationServices
import NecarambaCore
@testable import NecarambaMac

@MainActor final class OpaquePhysicalSuffixTests: XCTestCase {
  func testOpaqueManualDispatchUsesPhysicalCountWithoutInventingSelection() async {
    let (adapter, reader, word) = fixture()
    var posts = 0
    adapter.executePhysicalAsync = { mutation, text, valid in
      XCTAssertTrue(valid())
      XCTAssertEqual(mutation.deleteCount, 4)
      XCTAssertEqual(text, "WORD")
      posts += 1
      return .committed
    }
    let result = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(adapter.opaqueFocus(in: word.context)?.identity, reader.identity)
  }
  func testChangedOpaqueIdentityAbortsBeforePosting() async {
    let (adapter, reader, word) = fixture()
    adapter.executePhysicalAsync = { _, _, valid in
      reader.identity = UUID()
      return valid() ? .committed : .aborted
    }
    let result = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(result, .aborted)
  }
  func testOpaqueUncertainDispatchNeverRetries() async {
    let (adapter, _, word) = fixture()
    var posts = 0
    adapter.executePhysicalAsync = { _, _, _ in posts += 1; return .uncertain }
    let result = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(result, .uncertain)
    XCTAssertEqual(posts, 1)
  }
  func testOpaqueClassificationRejectsTimeoutMalformedSelectedAndNonempty() {
    XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
      rangeStatus: .noValue, range: nil, directLayout: false))
    XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
      rangeStatus: .noValue, range: nil, authorized: false))
    XCTAssertEqual(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
      rangeStatus: .attributeUnsupported, range: nil), .unavailable)
    XCTAssertEqual(AXOpaqueMetadata.selection(valueStatus: .success, value: "",
      rangeStatus: .noValue, range: nil), .unavailable)
    XCTAssertEqual(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
      rangeStatus: .success, range: CFRange(location: 8, length: 0)), .collapsed)
    for status: AXError in [.cannotComplete, .failure, .success] {
      XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: status, value: nil,
        rangeStatus: .noValue, range: nil))
      XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
        rangeStatus: status, range: nil))
    }
    XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: .success, value: "other",
      rangeStatus: .noValue, range: nil))
    XCTAssertNil(AXOpaqueMetadata.selection(valueStatus: .noValue, value: nil,
      rangeStatus: .success, range: CFRange(location: 0, length: 2)))
  }
  func testOpaqueForeignEventsAndGenerationChangeRejectWithoutPosting() async {
    let (adapter, _, word) = fixture()
    var posts = 0
    adapter.executePhysicalAsync = { _, _, valid in
      adapter.inputGeneration = { 2 }
      guard valid() else { return .aborted }
      posts += 1; return .committed
    }
    let changed = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(changed, .aborted)
    XCTAssertEqual(posts, 0)
    let foreign = word.events.map { InputEvent(kind: .down, keyCode: $0.keyCode, modifiers: [],
      timestampNanos: 1, layout: word.layout, context: word.context, origin: .foreignSynthetic,
      text: $0.text, isRepeat: false) }
    let untrusted = BufferedWord(text: word.text, events: foreign, context: word.context,
      layout: word.layout, delimiter: "")
    let result = await adapter.replaceTrackedSuffixAsync(untrusted, with: "WORD")
    XCTAssertEqual(result, .aborted)
    XCTAssertEqual(posts, 0)
  }
  func testOpaqueAutomaticSpaceBoundaryTrustsCaptureButNotSecureInput() async {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: layout, qualified: true)
    let token = context.current()!
    let reader = OpaqueReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowAutomaticBoundary: { true })
    adapter.inputGeneration = { 1 }
    let events = "word".map { InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
      layout: layout, context: token, origin: .physical, text: String($0), isRepeat: false) }
    let word = BufferedWord(text: "word", events: events, context: token, layout: layout, delimiter: " ")
    let boundary = InputEvent(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: layout, context: token, origin: .physical, text: " ", isRepeat: false)
    var posts = 0
    adapter.executePhysicalAsync = { mutation, _, valid in
      guard valid() else { return .aborted }
      XCTAssertEqual(mutation.deleteCount, 5)
      posts += 1; return .committed
    }
    let result = await adapter.replaceAutomaticBoundaryAsync(.init(word: word, boundary: boundary,
      inputGeneration: 1), with: "WORD ")
    XCTAssertEqual(result, .dispatched)
    // An unproven word start is trusted from capture in a field without text.
    let unproven = await adapter.replaceAutomaticBoundaryAsync(.init(word: word, boundary: boundary,
      inputGeneration: 1, requiresWordStartProof: true), with: "WORD ")
    XCTAssertEqual(unproven, .dispatched)
    XCTAssertEqual(posts, 2)
    context.invalidate(.secureInput)
    let secure = await adapter.replaceAutomaticBoundaryAsync(.init(word: word, boundary: boundary,
      inputGeneration: 1), with: "WORD ")
    XCTAssertEqual(secure, .aborted)
    XCTAssertEqual(posts, 2)
  }
  func testRepeatedOpaqueSuffixUsesRetainedIdentityAndCurrentLength() async {
    let (adapter, reader, word) = fixture()
    let candidate = ManualRepeatCandidate(original: word, currentText: "longer", context: word.context,
      layout: word.layout, delimiter: "", fieldIdentity: reader.identity)
    var posts = 0
    adapter.executePhysicalAsync = { mutation, text, valid in
      XCTAssertTrue(valid())
      XCTAssertEqual(mutation.focus.identity, reader.identity)
      XCTAssertEqual(mutation.deleteCount, 6)
      XCTAssertEqual(text, "word")
      posts += 1; return .committed
    }
    let result = await adapter.replaceRepeatedSuffixAsync(candidate, with: "word")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(posts, 1)
  }
  func testRepeatedOpaqueSuffixRejectsMissingOrStaleIdentity() async {
    let (adapter, reader, word) = fixture()
    var posts = 0
    adapter.executePhysicalAsync = { _, _, _ in posts += 1; return .committed }
    for identity: UUID? in [nil, UUID()] {
      XCTAssertNotEqual(identity, reader.identity)
      let candidate = ManualRepeatCandidate(original: word, currentText: "longer", context: word.context,
        layout: word.layout, delimiter: "", fieldIdentity: identity)
      let result = await adapter.replaceRepeatedSuffixAsync(candidate, with: "word")
      XCTAssertEqual(result, .aborted)
    }
    XCTAssertEqual(posts, 0)
  }
  func testCancellationAfterOpaqueDispatchIsUncertainAndNeverReposts() async {
    let (adapter, _, word) = fixture()
    var resume: CheckedContinuation<ApplyResult, Never>?
    var posts = 0
    let started = expectation(description: "physical batch dispatched")
    adapter.executePhysicalAsync = { _, _, _ in
      posts += 1
      return await withCheckedContinuation { resume = $0; started.fulfill() }
    }
    let task = Task { @MainActor in await adapter.replaceTrackedSuffixAsync(word, with: "WORD") }
    await fulfillment(of: [started], timeout: 1)
    task.cancel()
    guard let resume else { return XCTFail("Dispatch did not suspend") }
    resume.resume(returning: .committed)
    let result = await task.value
    XCTAssertEqual(result, .uncertain)
    XCTAssertEqual(posts, 1)
  }
  func testDispatchRecordIsBoundToContextGenerationAndClearedOnFailure() async {
    let (adapter, reader, word) = fixture()
    adapter.executePhysicalAsync = { _, _, _ in .committed }
    let result = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(adapter.dispatchedSuffix(in: word.context, inputGeneration: 1)?.focus.identity, reader.identity)
    XCTAssertNil(adapter.dispatchedSuffix(in: word.context, inputGeneration: 2))
    let other = ContextToken(pid: word.context.pid, bundleID: word.context.bundleID,
      focusEpoch: word.context.focusEpoch + 1, layoutEpoch: word.context.layoutEpoch)
    XCTAssertNil(adapter.dispatchedSuffix(in: other, inputGeneration: 1))
    adapter.executePhysicalAsync = { _, _, _ in .uncertain }
    let uncertain = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(uncertain, .uncertain)
    XCTAssertNil(adapter.dispatchedSuffix(in: word.context, inputGeneration: 1))
  }
  func testEmptyProxyDispatchRecordsTheActualFocusedIdentity() async {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: layout, qualified: true)
    let token = context.current()!
    let reader = EmptyDispatchReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { true })
    adapter.inputGeneration = { 1 }
    adapter.executeAsync = { _, _, _, valid in valid() ? .committed : .aborted }
    let events = "word".map { InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
      layout: layout, context: token, origin: .physical, text: String($0), isRepeat: false) }
    let word = BufferedWord(text: "word", events: events, context: token, layout: layout, delimiter: "")
    let result = await adapter.replaceTrackedSuffixAsync(word, with: "WORD")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(adapter.dispatchedSuffix(in: token, inputGeneration: 1)?.focus.identity, reader.identity)
  }
  private func fixture() -> (AXSelectionAdapter, OpaqueReader, BufferedWord) {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(pid: 42, bundleID: "test", focusID: "field", layout: layout, qualified: true)
    let token = context.current()!
    let reader = OpaqueReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { true })
    adapter.inputGeneration = { 1 }
    let events = "word".map { InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
      layout: layout, context: token, origin: .physical, text: String($0), isRepeat: false) }
    return (adapter, reader, .init(text: "word", events: events, context: token, layout: layout, delimiter: ""))
  }
}
private final class OpaqueReader: AXSelectionReading {
  var identity = UUID()
  func read(in token: ContextToken) -> AXTextSnapshot? { nil }
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    .opaque(.init(context: token, identity: identity))
  }
}

private final class EmptyDispatchReader: AXSelectionReading {
  let identity = UUID()
  func read(in token: ContextToken) -> AXTextSnapshot? {
    .init(identity: identity, value: "", range: NSRange(location: 0, length: 0))
  }
}
