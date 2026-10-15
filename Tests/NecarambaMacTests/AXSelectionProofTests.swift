import AppKit
import CoreFoundation
import NecarambaCore
import XCTest

@testable import NecarambaMac

@MainActor final class AXSelectionProofTests: XCTestCase {
  func testMissingOptionalMarkedRangeAllowedOnlyForExplicitManualDirectLayout() async {
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

  func testPresentMarkedOrMalformedRangeRejectedEvenInManualMode() async {
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

  func testSelectedToCollapsedChangeAbortsBeforeAnyPost() async {
    await assertModeRace(first: NSRange(location: 2, length: 4), second: NSRange(location: 6, length: 0))
  }
  func testCollapsedToSelectedChangeAbortsBeforeAnyPost() async {
    await assertModeRace(first: NSRange(location: 6, length: 0), second: NSRange(location: 2, length: 4))
  }
  func testDelayedReadbackCommitsOnlyAfterTargetConsumesPostedKeys() async {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    var reads = 0
    adapter.executeAsync = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        if reads == 3 {
          reader.value = "A WORD Z"
          reader.range = NSRange(location: 6, length: 0)
        }
      }
      return .committed
    }
    let asyncResult1 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult1, .committed)
  }

  func testMatchingReplacementWithChangedSurroundingTextIsUncertain() async {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.executeAsync = { _, _, _, _ in
      reader.value = "B WORD Z"
      reader.range = NSRange(location: 6, length: 0)
      return .committed
    }
    let asyncResult2 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult2, .uncertain)
  }

  func testReadbackTimeoutNeverRepeatsMutation() async {
    var elapsed: TimeInterval = 0
    let (adapter, _, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in posts += 1; return .committed }
    let asyncResult3 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult3, .uncertain)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testGenerationChangeDuringDelayedReadbackStopsImmediately() async {
    var elapsed: TimeInterval = 0
    var generation: UInt64 = 1
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    adapter.inputGeneration = { generation }
    let evidence = adapter.selected(in: token)!
    adapter.executeAsync = { _, _, _, _ in
      reader.onRead = { generation = 2 }
      return .committed
    }
    let asyncResult4 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult4, .uncertain)
    XCTAssertEqual(elapsed, 0)
  }

  func testIdentityChangeDuringReadbackIsUncertain() async {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.executeAsync = { _, _, _, _ in
      reader.id = UUID()
      reader.value = "A WORD Z"
      reader.range = NSRange(location: 6, length: 0)
      return .committed
    }
    let asyncResult5 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult5, .uncertain)
  }

  func testTrackedManualSuffixOnEmptyProxyIsDispatchedWithoutClaimingVerification() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var posts = 0
    adapter.executeAsync = { evidence, replacement, selected, preflight in
      XCTAssertEqual(evidence.text, "word ")
      XCTAssertEqual(replacement, "WORD ")
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      posts += 1
      return .committed
    }
    let asyncResult6 = await adapter.replaceTrackedSuffixAsync(word(token), with: "WORD ")
    XCTAssertEqual(asyncResult6, .dispatched)
    XCTAssertEqual(posts, 1)
  }

  func testTrackedSuffixRejectsReadableFieldsAutomaticModeAndUntrustedEvents() async {
    let (adapter, reader, token) = fixture(manual: true)
    adapter.executeAsync = { _, _, _, _ in XCTFail("Must not post"); return .committed }
    let asyncResult7 = await adapter.replaceTrackedSuffixAsync(word(token), with: "WORD ")
    XCTAssertEqual(asyncResult7, .aborted)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    let asyncResult8 = await adapter.replaceTrackedSuffixAsync(word(token, origin: .foreignSynthetic), with: "WORD ")
    XCTAssertEqual(asyncResult8, .aborted)
    let (automatic, empty, other) = fixture()
    empty.value = ""
    empty.range = NSRange(location: 0, length: 0)
    automatic.executeAsync = { _, _, _, _ in XCTFail("Must not post"); return .committed }
    let asyncResult9 = await automatic.replaceTrackedSuffixAsync(word(other), with: "WORD ")
    XCTAssertEqual(asyncResult9, .aborted)
  }

  func testTrackedProxyChangeBeforeDestructionAborts() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.executeAsync = { _, _, _, preflight in
      reader.id = UUID()
      return preflight() ? .committed : .aborted
    }
    let asyncResult10 = await adapter.replaceTrackedSuffixAsync(word(token), with: "WORD ")
    XCTAssertEqual(asyncResult10, .aborted)
  }

  func testTrackedPartialMutationRemainsUncertainAndIsNeverRetried() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in posts += 1; return .uncertain }
    let asyncResult11 = await adapter.replaceTrackedSuffixAsync(word(token), with: "WORD ")
    XCTAssertEqual(asyncResult11, .uncertain)
    XCTAssertEqual(posts, 1)
  }

  func testDeadlineOverrunCannotCommitEvenMatchingReadback() async {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    adapter.executeAsync = { _, _, _, _ in
      reader.onRead = {
        elapsed = 0.101
        reader.value = "A WORD Z"
        reader.range = NSRange(location: 6, length: 0)
      }
      return .committed
    }
    let asyncResult12 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult12, .uncertain)
  }

  func testTrackedReadableResultStillDoesNotProveOriginalSuffix() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.executeAsync = { _, _, _, _ in
      reader.value = "WORD "
      reader.range = NSRange(location: 5, length: 0)
      return .committed
    }
    let asyncResult13 = await adapter.replaceTrackedSuffixAsync(word(token), with: "WORD ")
    XCTAssertEqual(asyncResult13, .dispatched)
  }

  func testTrackedSubmissionDelimitersAbortWithoutPosting() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.executeAsync = { _, _, _, _ in XCTFail("Submission must never be replayed"); return .committed }
    let original = word(token)
    for delimiter in ["\n", "\r", "\t", "!\n", " \r", "?\t"] {
      let submitted = BufferedWord(text: original.text, events: original.events,
        context: original.context, layout: original.layout, delimiter: delimiter)
      let asyncResult14 = await adapter.replaceTrackedSuffixAsync(submitted, with: "WORD" + delimiter)
      XCTAssertEqual(asyncResult14, .aborted)
    }
  }

  func testThreeExplicitProxyRepeatsKeepPhysicalLineageAndDeleteCurrentText() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    let original = word(token)
    var removed: [String] = []
    adapter.executeAsync = { evidence, _, selected, preflight in
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      removed.append(evidence.text)
      return .committed
    }
    let asyncResult15 = await adapter.replaceTrackedSuffixAsync(original, with: "длиннее ")
    XCTAssertEqual(asyncResult15, .dispatched)
    for (current, replacement) in [("длиннее", "word "), ("word", "длиннее "), ("длиннее", "word ")] {
      let candidate = ManualRepeatCandidate(original: original, currentText: current,
        context: token, layout: .init(rawValue: current == "word" ? "US" : "RU"),
        delimiter: " ", fieldIdentity: reader.id)
      let asyncResult16 = await adapter.replaceRepeatedSuffixAsync(candidate, with: replacement)
      XCTAssertEqual(asyncResult16, .dispatched)
      XCTAssertEqual(candidate.original.events.map(\.text), ["w", "o", "r", "d"])
    }
    XCTAssertEqual(removed, ["word ", "длиннее ", "word ", "длиннее "])
  }

  func testProxyRepeatRejectsChangedContextAndMissingOrDifferentIdentity() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.executeAsync = { _, _, _, _ in XCTFail("Stale repeat must not mutate"); return .committed }
    let changed = ContextToken(pid: token.pid, bundleID: token.bundleID,
      focusEpoch: token.focusEpoch + 1, layoutEpoch: token.layoutEpoch)
    for (context, identity) in [(changed, Optional(reader.id)), (token, nil), (token, Optional(UUID()))] {
      let candidate = ManualRepeatCandidate(original: word(token), currentText: "длиннее",
        context: context, layout: .init(rawValue: "RU"), delimiter: " ", fieldIdentity: identity)
      let asyncResult17 = await adapter.replaceRepeatedSuffixAsync(candidate, with: "word ")
      XCTAssertEqual(asyncResult17, .aborted)
    }
  }

  func testProxyRepeatPartialMutationIsUncertainWithoutRetry() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.executeAsync = { _, _, _, _ in attempts += 1; return .uncertain }
    let candidate = ManualRepeatCandidate(original: word(token), currentText: "длиннее",
      context: token, layout: .init(rawValue: "RU"), delimiter: " ", fieldIdentity: reader.id)
    let asyncResult18 = await adapter.replaceRepeatedSuffixAsync(candidate, with: "word ")
    XCTAssertEqual(asyncResult18, .uncertain)
    XCTAssertEqual(attempts, 1)
  }

  func testOptionalMarkedMetadataRequiresDirectLayoutInAutomaticScope() async {
    XCTAssertTrue(AXCompositionProof.permits(markedRange: nil, attributeUnavailable: true,
      manual: false, directKeyboardLayout: true, automaticBoundary: true))
    XCTAssertFalse(AXCompositionProof.permits(markedRange: nil, attributeUnavailable: true,
      manual: false, directKeyboardLayout: false, automaticBoundary: true))
    XCTAssertFalse(AXCompositionProof.permits(markedRange: CFRange(location: 0, length: 1),
      attributeUnavailable: false, manual: false, directKeyboardLayout: true,
      automaticBoundary: true))
  }

  func testAutomaticSpaceProxyDispatchesOnceWithCapturedGeneration() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.executeAsync = { evidence, text, selected, preflight in
      XCTAssertEqual(evidence.inputGeneration, 1)
      XCTAssertEqual(evidence.text, "word ")
      XCTAssertEqual(text, "WORD ")
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      attempts += 1
      return .committed
    }
    let asyncResult19 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult19, .dispatched)
    XCTAssertEqual(attempts, 1)
  }

  func testAutomaticReadableSuffixRequiresExactProofAndCommits() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = "A word "
    reader.range = NSRange(location: 7, length: 0)
    adapter.executeAsync = { _, _, _, preflight in
      guard preflight() else { return .aborted }
      reader.value = "A WORD "
      return .committed
    }
    let asyncResult20 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult20, .committed)
  }

  func testSparkAutomaticPreservesObservedNonbreakingSpace() async {
    let (adapter, reader, token) = fixture(automatic: true, bundleID: "com.readdle.SparkDesktop")
    reader.value = "A word\u{00a0}"
    reader.range = NSRange(location: 7, length: 0)
    var posts = 0
    adapter.executeAsync = { evidence, replacement, selected, preflight in
      XCTAssertEqual(evidence.text, "word\u{00a0}")
      XCTAssertEqual(replacement, "WORD\u{00a0}")
      XCTAssertFalse(selected)
      guard preflight() else { return .aborted }
      posts += 1
      reader.value = "A " + replacement
      return .committed
    }
    let asyncResult21 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult21, .committed)
    XCTAssertEqual(posts, 1)
  }

  func testSparkAutomaticDoesNotNormalizeLettersOrOtherWhitespace() async {
    for (bundle, suffix) in [("test", "word\u{00a0}"),
      ("com.readdle.SparkDesktop", "wOrd\u{00a0}"),
      ("com.readdle.SparkDesktop", "word\t"),
      ("com.readdle.SparkDesktop", "word\u{2009}")] {
      let (adapter, reader, token) = fixture(automatic: true, bundleID: bundle)
      reader.value = suffix
      reader.range = NSRange(location: suffix.utf16.count, length: 0)
      adapter.executeAsync = { _, _, _, _ in XCTFail("Unproven suffix must not post"); return .committed }
      let asyncResult22 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
      XCTAssertEqual(asyncResult22, .aborted)
    }
  }

  func testSparkNonbreakingSpaceStillRequiresExactPreflightAndReadback() async {
    for mutateBeforePosting in [true, false] {
      let (adapter, reader, token) = fixture(automatic: true, bundleID: "com.readdle.SparkDesktop")
      reader.value = "A word\u{00a0}"
      reader.range = NSRange(location: 7, length: 0)
      var attempts = 0
      adapter.executeAsync = { _, _, _, preflight in
        attempts += 1
        if mutateBeforePosting { reader.value = "B word\u{00a0}" }
        guard preflight() else { return .aborted }
        // An editor rewriting NBSP back to ASCII is not exact confirmation.
        reader.value = "A WORD "
        return .committed
      }
      let asyncResult23 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
      XCTAssertEqual(asyncResult23,
        mutateBeforePosting ? .aborted : .uncertain)
      XCTAssertEqual(attempts, 1)
    }
  }

  func testSparkRequestsWholeCaretWordEvenWhenItIsFrontmost() async {
    let context = ContextState()
    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    context.update(pid: frontPID, bundleID: "com.readdle.SparkDesktop", focusID: "a",
      layout: .init(rawValue: "US"), qualified: true)
    let reader = SystemAXSelectionReader(context: context, qualifies: { _, _ in true })
    XCTAssertTrue(reader.requiresCaretWord(in: context.current()!))
  }

  func testManualCaretWordAndSelectionPreserveNonbreakingSpace() async {
    for selected in [false, true] {
      let (adapter, reader, token) = fixture(manual: true, bundleID: "com.readdle.SparkDesktop")
      reader.overlay = true
      reader.value = "🙂 ghbdtn\u{00a0}"
      reader.range = selected ? NSRange(location: 3, length: 7) : NSRange(location: 10, length: 0)
      let evidence: SelectionEvidence
      if selected {
        guard let selection = adapter.selected(in: token) else { return XCTFail("Missing selection") }
        evidence = selection
      } else {
        guard case .word(let word) = adapter.wordBeforeCaret(in: token) else { return XCTFail("Missing word") }
        evidence = word
      }
      XCTAssertEqual(evidence.text, "ghbdtn\u{00a0}")
      XCTAssertEqual(evidence.location, 3)
      adapter.executeAsync = { _, replacement, isSelected, preflight in
        XCTAssertEqual(isSelected, selected)
        guard preflight() else { return .aborted }
        reader.value = "🙂 " + replacement
        reader.range = NSRange(location: 10, length: 0)
        return .committed
      }
      let asyncResult24 = await adapter.replaceAsync(evidence, with: "привет\u{00a0}")
      XCTAssertEqual(asyncResult24, .committed)
    }
  }

  func testAutomaticSubsequentInputOrAbsentScopeNeverPosts() async {
    for enabled in [false, true] {
      let (adapter, reader, token) = fixture(automatic: enabled)
      reader.value = ""
      reader.range = NSRange(location: 0, length: 0)
      adapter.inputGeneration = { enabled ? 2 : 1 }
      adapter.executeAsync = { _, _, _, _ in XCTFail("Stale or unauthorized auto edit"); return .committed }
      let asyncResult25 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
      XCTAssertEqual(asyncResult25, .aborted)
    }
  }

  func testAutomaticRejectsSubmissionEarlyAndMismatchedBoundary() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    adapter.executeAsync = { _, _, _, _ in XCTFail("Invalid boundary must not post"); return .committed }
    for delimiter in ["", "\n", "\r", "\t", "! "] {
      let original = word(token)
      let altered = BufferedWord(text: original.text, events: original.events,
        context: token, layout: original.layout, delimiter: delimiter)
      let candidate = AutomaticBoundaryCandidate(word: altered,
        boundary: autoCandidate(token).boundary, inputGeneration: 1)
      let asyncResult26 = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD" + delimiter)
      XCTAssertEqual(asyncResult26, .aborted)
    }
    let wrong = InputEvent(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: .init(rawValue: "RU"), context: token, origin: .physical, text: " ", isRepeat: false)
    let asyncResult27 = await adapter.replaceAutomaticBoundaryAsync(.init(word: word(token), boundary: wrong,
      inputGeneration: 1), with: "WORD ")
    XCTAssertEqual(asyncResult27, .aborted)
  }

  func testAutomaticFieldChangeOrInputBeforePostAborts() async {
    for changeField in [false, true] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = ""
      reader.range = NSRange(location: 0, length: 0)
      var generation: UInt64 = 1
      adapter.inputGeneration = { generation }
      adapter.executeAsync = { _, _, _, preflight in
        if changeField { reader.id = UUID() } else { generation += 1 }
        return preflight() ? .committed : .aborted
      }
      let asyncResult28 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
      XCTAssertEqual(asyncResult28, .aborted)
    }
  }

  func testAutomaticPartialMutationIsUncertainWithoutRetry() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var attempts = 0
    adapter.executeAsync = { _, _, _, _ in attempts += 1; return .uncertain }
    let asyncResult29 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult29, .uncertain)
    XCTAssertEqual(attempts, 1)
  }

  func testAutomaticReadableMismatchCannotFallBackToDestructiveProxyEdit() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = "A different "
    reader.range = NSRange(location: 12, length: 0)
    adapter.executeAsync = { _, _, _, _ in XCTFail("Readable mismatch must not post"); return .committed }
    let asyncResult30 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult30, .aborted)
  }

  func testAutomaticGenerationChangeAfterPostingIsUncertain() async {
    let (adapter, reader, token) = fixture(automatic: true)
    reader.value = ""
    reader.range = NSRange(location: 0, length: 0)
    var generation: UInt64 = 1
    adapter.inputGeneration = { generation }
    adapter.executeAsync = { _, _, _, _ in generation += 1; return .committed }
    let asyncResult31 = await adapter.replaceAutomaticBoundaryAsync(autoCandidate(token), with: "WORD ")
    XCTAssertEqual(asyncResult31, .uncertain)
  }

  func testUntrustedAutomaticPrefixRejectsOpaqueAndEmbeddedWordWithoutPosting() async {
    for value in ["", "url/word ", "prefixword ", "x@word "] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = value
      reader.range = NSRange(location: value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true)
      var posts = 0
      adapter.executeAsync = { _, _, _, _ in posts += 1; return .aborted }
      let asyncResult32 = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD ")
      XCTAssertEqual(asyncResult32, .aborted)
      XCTAssertEqual(posts, 0, value)
    }
  }

  func testUntrustedAutomaticPrefixAcceptsProvenFieldStartOrWhitespace() async {
    for prefix in ["", "previous ", "🙂\n"] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = prefix + "word "
      reader.range = NSRange(location: reader.value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true)
      adapter.executeAsync = { _, _, _, preflight in
        guard preflight() else { return .aborted }
        reader.value = prefix + "WORD "
        return .committed
      }
      let asyncResult33 = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD ")
      XCTAssertEqual(asyncResult33, .committed)
    }
  }

  func testAutomaticWordStartProofCannotChangeBeforeDispatch() async {
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
    adapter.executeAsync = { _, _, _, _ in
      XCTFail("Changed prefix must not be edited")
      return .aborted
    }
    let asyncResult34 = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD ")
    XCTAssertEqual(asyncResult34, .aborted)
  }

  func testFreshOpaqueWordCanDispatchButReadableEmbeddedSuffixCannot() async {
    for value in ["", "url/word "] {
      let (adapter, reader, token) = fixture(automatic: true)
      reader.value = value
      reader.range = NSRange(location: value.utf16.count, length: 0)
      let original = autoCandidate(token)
      let candidate = AutomaticBoundaryCandidate(word: original.word, boundary: original.boundary,
        inputGeneration: 1, requiresWordStartProof: true, allowsOpaqueWordStart: true)
      var posts = 0
      adapter.executeAsync = { _, _, _, preflight in
        guard preflight() else { return .aborted }
        posts += 1
        return .committed
      }
      let asyncResult35 = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD ")
      XCTAssertEqual(asyncResult35,
        value.isEmpty ? .dispatched : .aborted)
      XCTAssertEqual(posts, value.isEmpty ? 1 : 0)
    }
  }

  private func autoCandidate(_ token: ContextToken) -> AutomaticBoundaryCandidate {
    .init(word: word(token), boundary: .init(kind: .down, keyCode: 49, modifiers: [],
      timestampNanos: 2, layout: .init(rawValue: "US"), context: token,
      origin: .physical, text: " ", isRepeat: false), inputGeneration: 1)
  }

  func testPostedSuffixDeletionAndInsertionPrefixesWaitForExactReadback() async {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var attempts = 0
    adapter.executeAsync = { _, _, _, _ in
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
    let asyncResult36 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult36, .committed)
    XCTAssertEqual(attempts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testPostedSelectedReplacementPrefixWaitsForExactReadback() async {
    let (adapter, reader, token) = fixture()
    let evidence = adapter.selected(in: token)!
    adapter.executeAsync = { _, _, _, _ in
      var reads = 0
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A WO Z" : "A WORD Z"
        reader.range = NSRange(location: reads == 1 ? 4 : 6, length: 0)
      }
      return .committed
    }
    let asyncResult37 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult37, .committed)
  }

  func testIntermediateProofRejectsUnrelatedSurroundingsOrCaret() async {
    for state in [("A wor Q", 5), ("B wor Z", 5), ("A wor Z", 1)] {
      var waits = 0
      let (adapter, reader, token) = fixture(wait: { _ in waits += 1 })
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      adapter.executeAsync = { _, _, _, _ in
        reader.value = state.0
        reader.range = NSRange(location: state.1, length: 0)
        return .committed
      }
      let asyncResult38 = await adapter.replaceAsync(evidence, with: "WORD")
      XCTAssertEqual(asyncResult38, .uncertain)
      XCTAssertEqual(waits, 0)
    }
  }

  func testIntermediateStateCannotCommitWithoutExactFinalReadback() async {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var attempts = 0
    adapter.executeAsync = { _, _, _, _ in
      attempts += 1
      reader.value = "A wo Z"
      reader.range = NSRange(location: 4, length: 0)
      return .committed
    }
    let asyncResult39 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult39, .uncertain)
    XCTAssertEqual(attempts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testPostedIntermediateProgressCannotMoveBackwards() async {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var reads = 0
    adapter.executeAsync = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A wo Z" : "A wor Z"
        reader.range = NSRange(location: reads == 1 ? 4 : 5, length: 0)
      }
      return .committed
    }
    let asyncResult40 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult40, .uncertain)
    XCTAssertEqual(reads, 2)
  }

  func testTransportTimeoutWithPinnedOrUnknownIdentityWaitsForExactFinalProof() async {
    for knownIdentity in [false, true] {
      let (adapter, reader, token) = fixture()
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      var reads = 0
      var posts = 0
      adapter.executeAsync = { _, _, _, _ in
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
      let asyncResult41 = await adapter.replaceAsync(evidence, with: "WORD")
      XCTAssertEqual(asyncResult41, .committed)
      XCTAssertEqual(posts, 1)
      XCTAssertEqual(reads, 2)
    }
  }

  func testIndependentValueAndRangeProgressWaitsForExactFinalProof() async {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    adapter.executeAsync = { _, _, _, _ in
      var states = [("A wor Z", 4), ("A  Z", 6), ("A WORD Z", 6)]
      reader.onRead = {
        let state = states.removeFirst()
        reader.value = state.0
        reader.range = NSRange(location: state.1, length: 0)
      }
      return .committed
    }
    let asyncResult42 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult42, .committed)
  }

  func testKnownIdentityChangeRejectedSecurityOrUnrelatedPartialValueNeverRecover() async {
    for kind in 0..<3 {
      let (adapter, reader, token) = fixture()
      reader.range = NSRange(location: 6, length: 0)
      let evidence = adapter.suffix("word", in: token)!
      var reads = 0
      adapter.executeAsync = { _, _, _, _ in
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
      let asyncResult43 = await adapter.replaceAsync(evidence, with: "WORD")
      XCTAssertEqual(asyncResult43, .uncertain)
      XCTAssertEqual(reads, 1)
    }
  }

  func testPersistentTransportTimeoutIsBoundedAndNeverReposts() async {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in
      posts += 1
      reader.onObservation = { .transient(identity: nil, value: nil) }
      return .committed
    }
    let asyncResult44 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult44, .uncertain)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.1)
  }

  func testNewerValueWithOlderCachedCaretWaitsForExactFinalProof() async {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    adapter.executeAsync = { _, _, _, _ in
      var reads = 0
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A WO Z" : "A WORD Z"
        reader.range = NSRange(location: reads == 1 ? 2 : 6, length: 0)
      }
      return .committed
    }
    let asyncResult45 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult45, .committed)
  }

  func testCaretCannotRegressAgainstItsOwnObservedProgress() async {
    let (adapter, reader, token) = fixture()
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    var reads = 0
    adapter.executeAsync = { _, _, _, _ in
      reader.onRead = {
        reads += 1
        reader.value = reads == 1 ? "A wor Z" : "A wo Z"
        reader.range = NSRange(location: reads == 1 ? 3 : 4, length: 0)
      }
      return .committed
    }
    let asyncResult46 = await adapter.replaceAsync(evidence, with: "X")
    XCTAssertEqual(asyncResult46, .uncertain)
    XCTAssertEqual(reads, 2)
  }

  func testManualReadbackCanSettleAfterBrowserDelayBeyondOneHundredMilliseconds() async {
    var elapsed: TimeInterval = 0
    let (adapter, reader, token) = fixture(manual: true, now: { elapsed }, wait: { elapsed += $0 })
    let evidence = adapter.selected(in: token)!
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in
      posts += 1
      reader.onObservation = {
        if elapsed < 0.15 { return .transient(identity: reader.id, value: nil) }
        return .snapshot(.init(identity: reader.id, value: "A WORD Z", range: NSRange(location: 6, length: 0)))
      }
      return .committed
    }
    let asyncResult47 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult47, .committed)
    XCTAssertEqual(posts, 1)
    XCTAssertLessThanOrEqual(elapsed, 0.3)
  }
  func testReactiveOverlayReplacesProvenSuffixAsSelectionWithoutBackspaces() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, authorized in
      guard authorized() else { return .rejected }
      reader.range = NSRange(location: 2, length: 4)
      return .selected
    }
    adapter.executeAsync = { posted, _, selected, preflight in
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
    let asyncResult48 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult48, .committed)
  }

  func testRejectedOverlaySelectionNeverFallsBackToDeletion() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, _ in .rejected }
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in posts += 1; return .aborted }
    let asyncResult49 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult49, .aborted)
    XCTAssertEqual(posts, 0)
  }

  func testOverlaySelectionMustBeReadBackExactlyBeforePosting() async {
    let (adapter, reader, token) = fixture(manual: true)
    reader.range = NSRange(location: 6, length: 0)
    let evidence = adapter.suffix("word", in: token)!
    reader.prepare = { _, _, _ in
      reader.range = NSRange(location: 1, length: 5)
      return .selected
    }
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in posts += 1; return .aborted }
    let asyncResult50 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult50, .aborted)
    XCTAssertEqual(posts, 0)
  }

  func testOverlayCaretWordReadsWholeTokenAndPreservesUTF16Offset() async {
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

  func testOverlayCaretWordRejectsMiddleOfWordAndEmptyProxy() async {
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
    manual: Bool = false, automatic: Bool = false, bundleID: String = "test",
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) -> (AXSelectionAdapter, ProofReader, ContextToken) {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: bundleID, focusID: "a", layout: .init(rawValue: "US"), qualified: true)
    let reader = ProofReader()
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { manual }, allowAutomaticBoundary: { automatic }, now: now)
    adapter.observeLater = { delay in wait(delay) }
    adapter.inputGeneration = { 1 }
    return (adapter, reader, context.current()!)
  }
  private func assertModeRace(first: NSRange, second: NSRange) async {
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
    adapter.executeAsync = { _, _, _, preflight in
      reader.range = second
      guard preflight() else { return .aborted }
      posts += 1
      return .committed
    }
    let asyncResult51 = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(asyncResult51, .aborted)
    XCTAssertEqual(posts, 0)
  }
  func testGenerationCapturedBeforeInitialAXRead() async {
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

extension AXSelectionProofTests {
  @MainActor func testAsyncReadbackYieldsAndNeverRepostsAfterGenerationChanges() async {
    var time: TimeInterval = 0
    var generation: UInt64 = 1
    let (adapter, _, token) = fixture(now: { time }, wait: { _ in XCTFail("blocking wait") })
    adapter.inputGeneration = { generation }
    adapter.observeLater = { delay in
      await Task.yield()
      time += delay
      generation += 1
    }
    var posts = 0
    adapter.executeAsync = { _, _, _, valid in
      XCTAssertTrue(valid())
      posts += 1
      return .committed
    }
    let evidence = adapter.selected(in: token)!
    let result = await adapter.replaceAsync(evidence, with: "WORD")
    XCTAssertEqual(result, .uncertain)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(time, 0.005)
  }
  @MainActor func testAsyncDelayedReadbackRetainsExactProofAndDeadline() async {
    var time: TimeInterval = 0
    let (adapter, reader, token) = fixture(now: { time }, wait: { _ in XCTFail("blocking wait") })
    adapter.observeLater = { delay in
      time += delay
      if time >= 0.015 { reader.value = "A WORD Z"; reader.range = NSRange(location: 6, length: 0) }
    }
    var posts = 0
    adapter.executeAsync = { _, _, _, _ in posts += 1; return .committed }
    let result = await adapter.replaceAsync(adapter.selected(in: token)!, with: "WORD")
    XCTAssertEqual(result, .committed)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(time, 0.015, accuracy: 0.00001)
  }
}

extension AXSelectionProofTests {
  func testAsyncFocusSecurityAndPermissionInvalidationDuringWaitNeverReposts() async {
    for reason: InvalidationReason in [.focusChanged, .secureInput, .permissionRevoked] {
      let context = ContextState()
      context.update(pid: 42, bundleID: "test", focusID: "field", layout: .init(rawValue: "US"), qualified: true)
      let token = context.current()!
      let reader = ProofReader()
      let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader)
      adapter.inputGeneration = { 1 }
      var posts = 0
      adapter.executeAsync = { _, _, _, _ in posts += 1; return .committed }
      adapter.observeLater = { _ in context.invalidate(reason) }
      let result = await adapter.replaceAsync(adapter.selected(in: token)!, with: "WORD")
      XCTAssertEqual(result, .uncertain, "\(reason)")
      XCTAssertEqual(posts, 1)
    }
  }
  func testAsyncCancellationWhilePostingCannotAcceptLateMatchingReadback() async {
    let (adapter, reader, token) = fixture()
    var resume: CheckedContinuation<ApplyResult, Never>?
    let started = expectation(description: "posting suspended")
    adapter.executeAsync = { _, _, _, _ in
      await withCheckedContinuation { resume = $0; started.fulfill() }
    }
    let proof = adapter.selected(in: token)!
    let completed = expectation(description: "cancelled replacement completed")
    var result: ApplyResult?
    let task = Task { @MainActor in
      result = await adapter.replaceAsync(proof, with: "WORD")
      completed.fulfill()
    }
    await fulfillment(of: [started], timeout: 1)
    guard let resume else { task.cancel(); return XCTFail("Posting did not reach suspension") }
    task.cancel()
    reader.value = "A WORD Z"
    reader.range = NSRange(location: 6, length: 0)
    resume.resume(returning: .committed)
    await fulfillment(of: [completed], timeout: 1)
    XCTAssertEqual(result, .uncertain)
  }
}
