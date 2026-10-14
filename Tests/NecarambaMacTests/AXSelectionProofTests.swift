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

  func testThreeExplicitProxyRepeatsKeepPhysicalLineageAndDeleteCurrentText() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    let original = word(token)
    var removed: [String] = []
    adapter.execute = { evidence, _, selected, preflight in
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      removed.append(evidence.text)
      return .committed
    }
    XCTAssertEqual(adapter.replaceTrackedSuffix(original, with: "длиннее "), .dispatched)
    for (current, replacement) in [("длиннее", "word "), ("word", "длиннее "), ("длиннее", "word ")] {
      let candidate = ManualRepeatCandidate(original: original, currentText: current,
        context: token, layout: .init(rawValue: current == "word" ? "US" : "RU"),
        delimiter: " ", fieldIdentity: reader.id)
      XCTAssertEqual(adapter.replaceRepeatedSuffix(candidate, with: replacement), .dispatched)
      XCTAssertEqual(candidate.original.events.map(\.text), ["w", "o", "r", "d"])
    }
    XCTAssertEqual(removed, ["word ", "длиннее ", "word ", "длиннее "])
  }

  func testProxyRepeatRejectsChangedContextAndMissingOrDifferentIdentity() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.execute = { _, _, _, _ in XCTFail("Stale repeat must not mutate"); return .committed }
    let changed = ContextToken(pid: token.pid, bundleID: token.bundleID,
      focusEpoch: token.focusEpoch + 1, layoutEpoch: token.layoutEpoch)
    for (context, identity) in [(changed, Optional(reader.id)), (token, nil), (token, Optional(UUID()))] {
      let candidate = ManualRepeatCandidate(original: word(token), currentText: "длиннее",
        context: context, layout: .init(rawValue: "RU"), delimiter: " ", fieldIdentity: identity)
      XCTAssertEqual(adapter.replaceRepeatedSuffix(candidate, with: "word "), .aborted)
    }
  }

  func testProxyRepeatPartialMutationIsUncertainWithoutRetry() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.execute = { _, _, _, _ in attempts += 1; return .uncertain }
    let candidate = ManualRepeatCandidate(original: word(token), currentText: "длиннее",
      context: token, layout: .init(rawValue: "RU"), delimiter: " ", fieldIdentity: reader.id)
    XCTAssertEqual(adapter.replaceRepeatedSuffix(candidate, with: "word "), .uncertain)
    XCTAssertEqual(attempts, 1)
  }

  func testOptionalMarkedMetadataRequiresDirectLayoutInAutomaticScope() {
    XCTAssertTrue(AXCompositionProof.permits(markedRange: nil, attributeUnavailable: true,
      manual: false, directKeyboardLayout: true, automaticBoundary: true))
    XCTAssertFalse(AXCompositionProof.permits(markedRange: nil, attributeUnavailable: true,
      manual: false, directKeyboardLayout: false, automaticBoundary: true))
    XCTAssertFalse(AXCompositionProof.permits(markedRange: CFRange(location: 0, length: 1),
      attributeUnavailable: false, manual: false, directKeyboardLayout: true,
      automaticBoundary: true))
  }

  func testAutomaticSpaceProxyDispatchesOnceWithCapturedGeneration() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.execute = { evidence, text, selected, preflight in
      XCTAssertEqual(evidence.inputGeneration, 1)
      XCTAssertEqual(evidence.text, "word ")
      XCTAssertEqual(text, "WORD ")
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      attempts += 1
      return .committed
    }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .dispatched)
    XCTAssertEqual(attempts, 1)
  }

  func testAutomaticReadableSuffixRequiresExactProofAndCommits() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = "A word "
    reader.range = NSRange(location: 7, length: 0)
    adapter.execute = { _, _, _, preflight in
      guard preflight() else { return .aborted }
      reader.value = "A WORD "
      return .committed
    }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .committed)
  }

  func testAutomaticSubsequentInputOrAbsentScopeNeverPosts() {
    for enabled in [false, true] {
      let (adapter, reader, token) = fixture(automatic: enabled)
      reader.value = ""
      reader.range = NSRange(location: 0, length: 0)
      adapter.inputGeneration = { enabled ? 2 : 1 }
      adapter.execute = { _, _, _, _ in XCTFail("Stale or unauthorized auto edit"); return .committed }
      XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .aborted)
    }
  }

  func testAutomaticRejectsSubmissionEarlyAndMismatchedBoundary() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.execute = { _, _, _, _ in XCTFail("Invalid boundary must not post"); return .committed }
    for delimiter in ["", "\n", "\r", "\t", "! "] {
      let original = word(token)
      let altered = BufferedWord(text: original.text, events: original.events,
        context: token, layout: original.layout, delimiter: delimiter)
      let candidate = AutomaticBoundaryCandidate(word: altered,
        boundary: autoCandidate(token).boundary, inputGeneration: 1)
      XCTAssertEqual(adapter.replaceAutomaticBoundary(candidate, with: "WORD" + delimiter), .aborted)
    }
    let wrong = InputEvent(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: .init(rawValue: "RU"), context: token, origin: .physical, text: " ", isRepeat: false)
    XCTAssertEqual(adapter.replaceAutomaticBoundary(.init(word: word(token), boundary: wrong,
      inputGeneration: 1), with: "WORD "), .aborted)
  }

  func testAutomaticFieldChangeOrInputBeforePostAborts() {
    for changeField in [false, true] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = ""
      reader.range = NSRange(location: 0, length: 0)
      var generation: UInt64 = 1
      adapter.inputGeneration = { generation }
      adapter.execute = { _, _, _, preflight in
        if changeField { reader.id = UUID() } else { generation += 1 }
        return preflight() ? .committed : .aborted
      }
      XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .aborted)
    }
  }

  func testAutomaticPartialMutationIsUncertainWithoutRetry() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.execute = { _, _, _, _ in attempts += 1; return .uncertain }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .uncertain)
    XCTAssertEqual(attempts, 1)
  }

  func testAutomaticReadableMismatchCannotFallBackToDestructiveProxyEdit() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = "A different "
    reader.range = NSRange(location: 12, length: 0)
    adapter.execute = { _, _, _, _ in XCTFail("Readable mismatch must not post"); return .committed }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .aborted)
  }

  func testAutomaticGenerationChangeAfterPostingIsUncertain() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var generation: UInt64 = 1
    adapter.inputGeneration = { generation }
    adapter.execute = { _, _, _, _ in generation += 1; return .committed }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(autoCandidate(token), with: "WORD "), .uncertain)
  }

  func testUntrustedAutomaticPrefixRejectsOpaqueAndEmbeddedWordWithoutPosting() {
    for value in ["", "url/word ", "prefixword ", "x@word "] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = value
      reader.range = NSRange(location: value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true)
      var posts = 0
      adapter.execute = { _, _, _, _ in posts += 1; return .aborted }
      XCTAssertEqual(adapter.replaceAutomaticBoundary(candidate, with: "WORD "), .aborted)
      XCTAssertEqual(posts, 0, value)
    }
  }

  func testUntrustedAutomaticPrefixAcceptsProvenFieldStartOrWhitespace() {
    for prefix in ["", "previous ", "🙂\n"] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = prefix + "word "
      reader.range = NSRange(location: reader.value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true)
      adapter.execute = { _, _, _, preflight in
        guard preflight() else { return .aborted }
        reader.value = prefix + "WORD "
        return .committed
      }
      XCTAssertEqual(adapter.replaceAutomaticBoundary(candidate, with: "WORD "), .committed)
    }
  }

  func testAutomaticWordStartProofCannotChangeBeforeDispatch() {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = " word "
    reader.range = NSRange(location: 6, length: 0)
    let original = autoCandidate(token)
    let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
      inputGeneration: 1, requiresWordStartProof: true)
    var reads = 0
    reader.onRead = {
      reads += 1
      if reads > 1 { reader.value = "/word " }
    }
    adapter.execute = { _, _, _, _ in
      XCTFail("Changed prefix must not be edited")
      return .aborted
    }
    XCTAssertEqual(adapter.replaceAutomaticBoundary(candidate, with: "WORD "), .aborted)
  }

  func testFreshOpaqueWordCanDispatchButReadableEmbeddedSuffixCannot() {
    for value in ["", "url/word "] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = value
      reader.range = NSRange(location: value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true, allowsOpaqueWordStart: true)
      var posts = 0
      adapter.execute = { _, _, _, preflight in
        guard preflight() else { return .aborted }
        posts += 1
        return .committed
      }
      XCTAssertEqual(adapter.replaceAutomaticBoundary(candidate, with: "WORD "),
        value.isEmpty ? .dispatched : .aborted)
      XCTAssertEqual(posts, value.isEmpty ? 1 : 0)
    }
  }

  private func autoCandidate(_ token: ContextToken) -> AutomaticBoundaryCandidate {
    .init(word: word(token), boundary: .init(kind: .down, keyCode: 49, modifiers: [],
      timestampNanos: 2, layout: .init(rawValue: "US"), context: token,
      origin: .physical, text: " ", isRepeat: false), inputGeneration: 1)
  }

  func testPostedSuffixDeletionAndInsertionPrefixesWaitForExactReadback() {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var attempts = 0
    adapter.execute = { _, _, _, _ in
      attempts += 1
      var states: [(String, Int)] = [("A wor Z", 5), ("A wo Z", 4),
        ("A w Z", 3), ("A  Z", 2), ("A W Z", 3), ("A WO Z", 4), ("A WORD Z", 6)]
      reader.onRead = {
        let state = states.removeFirst()
        reader.value = state.0
        reader.range = NSRange(location: state.1, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
    XCTAssertEqual(attempts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testPostedSelectedReplacementPrefixWaitsForExactReadback() {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.execute = { _, _, _, _ in
      var reads = 0
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A WO Z" : "A WORD Z"
        reader.range = NSRange(location: reads == 1 ? 4 : 6, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
  }

  func testIntermediateProofRejectsUnrelatedSurroundingsOrCaret() {
    for state in [("A wor Q", 5), ("B wor Z", 5), ("A wor Z", 1)] {
      var waits = 0
      let (adapter, reader, token) = fixture(wait: { _ in waits += 1 })
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      adapter.execute = { _, _, _, _ in
        reader.value = state.0
        reader.range = NSRange(location: state.1, length: 0)
        return .committed
      }
      XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
      XCTAssertEqual(waits, 0)
    }
  }

  func testIntermediateStateCannotCommitWithoutExactFinalReadback() {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var attempts = 0
    adapter.execute = { _, _, _, _ in
      attempts += 1
      reader.value = "A wo Z"
      reader.range = NSRange(location: 4, length: 0)
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
    XCTAssertEqual(attempts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testPostedIntermediateProgressCannotMoveBackwards() {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var reads = 0
    adapter.execute = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A wo Z" : "A wor Z"
        reader.range = NSRange(location: reads == 1 ? 4 : 5, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
    XCTAssertEqual(reads, 2)
  }

  func testTransportTimeoutWithPinnedOrUnknownIdentityWaitsForExactFinalProof() {
    for knownIdentity in [false, true] {
      let (adapter, reader, token) = fixture()
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      var reads = 0
      var posts = 0
      adapter.execute = { _, _, _, _ in
        posts += 1
        reader.onObservation = {
          reads += 1
          if reads == 1 {
            return .transient(identity: knownIdentity ? reader.id : nil,
              value: knownIdentity ? "A wo Z" : nil)
          }
          return .snapshot(.init(identity: reader.id, value: "A WORD Z",
            range: NSRange(location: 6, length: 0)))
        }
        return .committed
      }
      XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
      XCTAssertEqual(posts, 1)
      XCTAssertEqual(reads, 2)
    }
  }

  func testIndependentValueAndRangeProgressWaitsForExactFinalProof() {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    adapter.execute = { _, _, _, _ in
      var states = [("A wor Z", 4), ("A  Z", 6), ("A WORD Z", 6)]
      reader.onRead = {
        let state = states.removeFirst()
        reader.value = state.0
        reader.range = NSRange(location: state.1, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
  }

  func testKnownIdentityChangeRejectedSecurityOrUnrelatedPartialValueNeverRecover() {
    for kind in 0..<3 {
      let (adapter, reader, token) = fixture()
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      var reads = 0
      adapter.execute = { _, _, _, _ in
        reader.onObservation = {
          reads += 1
          if reads > 1 { return .snapshot(.init(identity: reader.id, value: "A WORD Z",
            range: NSRange(location: 6, length: 0))) }
          if kind == 0 { return .transient(identity: UUID(), value: nil) }
          if kind == 1 { return .rejected }
          return .transient(identity: reader.id, value: "B wo Z")
        }
        return .committed
      }
      XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
      XCTAssertEqual(reads, 1)
    }
  }

  func testPersistentTransportTimeoutIsBoundedAndNeverReposts() {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.execute = { _, _, _, _ in
      posts += 1
      reader.onObservation = { .transient(identity: nil, value: nil) }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .uncertain)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testNewerValueWithOlderCachedCaretWaitsForExactFinalProof() {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    adapter.execute = { _, _, _, _ in
      var reads = 0
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A WO Z" : "A WORD Z"
        reader.range = NSRange(location: reads == 1 ? 2 : 6, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
  }

  func testCaretCannotRegressAgainstItsOwnObservedProgress() {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var reads = 0
    adapter.execute = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A wor Z" : "A wo Z"
        reader.range = NSRange(location: reads == 1 ? 3 : 4, length: 0)
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "X"), .uncertain)
    XCTAssertEqual(reads, 2)
  }

  func testManualReadbackCanSettleAfterBrowserDelayBeyondOneHundredMilliseconds() {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(manual: true, now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.execute = { _, _, _, _ in
      posts += 1
      reader.onObservation = {
        if elapsed < 0.15 { return .transient(identity: reader.id, value: nil) }
        return .snapshot(.init(identity: reader.id, value: "A WORD Z", range: NSRange(location: 6, length: 0)))
      }
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.3)
  }
  func testReactiveOverlayReplacesProvenSuffixAsSelectionWithoutBackspaces() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, authorized in
      guard authorized() else { return .rejected }
      reader.range = NSRange(location: 2, length: 4)
      return .selected
    }
    adapter.execute = { posted, _, selected, preflight in
      XCTAssertTrue(selected)
      XCTAssertEqual(posted.mode, .selected)
      XCTAssertEqual(posted.location, 2)
      XCTAssertEqual(posted.length, 4)
      guard preflight() else { return .aborted }
      // A reactive search field changes its suggestion after each deletion;
      // a direct selected replacement preserves both surrounding substrings.
      reader.value = selected ? "A WORD Z" : "A woWORD Z"
      reader.range = NSRange(location: 6, length: 0)
      return .committed
    }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .committed)
  }

  func testRejectedOverlaySelectionNeverFallsBackToDeletion() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, _ in .rejected }
    var posts = 0
    adapter.execute = { _, _, _, _ in posts += 1; return .aborted }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .aborted)
    XCTAssertEqual(posts, 0)
  }

  func testOverlaySelectionMustBeReadBackExactlyBeforePosting() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, _ in
      reader.range = NSRange(location: 1, length: 5)
      return .selected
    }
    var posts = 0
    adapter.execute = { _, _, _, _ in posts += 1; return .aborted }
    XCTAssertEqual(adapter.replace(evidence, with: "WORD"), .aborted)
    XCTAssertEqual(posts, 0)
  }

  func testOverlayCaretWordReadsWholeTokenAndPreservesUTF16Offset() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.overlay = true
    reader.value = "🙂 first ghbdtn  "
    reader.range = NSRange(location: 17, length: 0)
    guard case .word(let evidence) = adapter.wordBeforeCaret(in: token) else {
      return XCTFail("Full visible word must be available")
    }
    XCTAssertEqual(evidence.text, "ghbdtn  ")
    XCTAssertEqual(evidence.location, 9)
    XCTAssertEqual(evidence.length, 8)
    XCTAssertEqual(evidence.mode, .suffix)
    XCTAssertEqual(evidence.identity, reader.id)
    XCTAssertEqual(evidence.inputGeneration, 1)
  }

  func testOverlayCaretWordRejectsMiddleOfWordAndEmptyProxy() {
    let (adapter, reader, token) = fixture(manual: true)
    reader.overlay = true
    for (text, caret) in [("ghbdtn", 3), ("", 0), ("  ", 2)] {
      reader.value = text
      reader.range = NSRange(location: caret, length: 0)
      guard case .unavailable = adapter.wordBeforeCaret(in: token) else {
        return XCTFail("Cannot prove a complete word")
      }
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
    manual: Bool = false, automatic: Bool = false,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) -> (AXSelectionAdapter, ProofReader, ContextToken) {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "a", layout: .init(rawValue: "US"), qualified: true)
    let reader = ProofReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { manual }, allowAutomaticBoundary: { automatic }, now: now, wait: wait)
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
private final class ProofReader: AXSelectionReading, AXSuffixSelectionPreparing {
  var overlay = false
  func requiresCaretWord(in token: ContextToken) -> Bool { overlay }
  var prepare: ((SelectionEvidence, AXTextSnapshot, () -> Bool) -> AXSuffixPreparation)?
  func prepareSuffix(_ evidence: SelectionEvidence, before: AXTextSnapshot,
    authorized: () -> Bool) -> AXSuffixPreparation {
    prepare?(evidence, before, authorized) ?? .notRequired
  }
  var id = UUID()
  var value = "A word Z"
  var range = NSRange(location: 2, length: 4)
  var onRead: () -> Void = {}
  var onObservation: (() -> AXSelectionObservation)?
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    if let onObservation { return onObservation() }
    return read(in: token).map(AXSelectionObservation.snapshot) ?? .rejected
  }
  func read(in token: ContextToken) -> AXTextSnapshot? {
    onRead()
    return .init(identity: id, value: value, range: range)
  }
}
