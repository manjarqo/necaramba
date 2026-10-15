/// Pure word decision over caller-verified physical RU/EN candidates.
public struct PatternCorrectionEngine: Sendable {
  private let classifier: PatternClassifier
  private let autocorrector: PatternAutocorrector
  public init(classifier: PatternClassifier, autocorrector: PatternAutocorrector) {
    self.classifier = classifier; self.autocorrector = autocorrector
  }
  public func decide(word: BufferedWord, russianCandidate: String, russianLayout: LayoutID,
    englishCandidate: String, englishLayout: LayoutID, preferences: PreferencesSnapshot,
    excludedWords: Set<String>, modelVersion: UInt64,
    physicalCandidatesVerified: Bool = false) -> LinguisticDecision {
    guard preferences.autoEnabled else { return .unchanged(.disabled) }
    return decide(word: word, russianCandidate: russianCandidate, russianLayout: russianLayout,
        englishCandidate: englishCandidate, englishLayout: englishLayout, preferences: preferences,
        wordPolicy: PreparedWordPolicy(excluded: excludedWords, protected: []), modelVersion: modelVersion,
        physicalCandidatesVerified: physicalCandidatesVerified)
  }
  public func decide(word: BufferedWord, russianCandidate: String, russianLayout: LayoutID,
    englishCandidate: String, englishLayout: LayoutID, preferences: PreferencesSnapshot,
    wordPolicy: PreparedWordPolicy, modelVersion: UInt64,
    physicalCandidatesVerified: Bool = false) -> LinguisticDecision {
    guard preferences.autoEnabled else { return .unchanged(.disabled) }
    guard !wordPolicy.containsExcluded(word.text) else { return .unchanged(.excludedWord) }
    let punctuationSource = !Self.safeWord(word.text)
    if punctuationSource {
      guard physicalCandidatesVerified, word.layout == englishLayout,
        Self.physicalPunctuationSource(word.text), Self.safeWord(russianCandidate)
      else { return .unchanged(.protectedToken) }
    }
    guard russianLayout != englishLayout,
      (word.layout == russianLayout && word.text == russianCandidate) ||
        (word.layout == englishLayout && word.text == englishCandidate),
      word.events.allSatisfy({ $0.context == word.context && $0.layout == word.layout })
    else { return .unchanged(.unsupportedLayout) }
    guard Self.safeCandidate(russianCandidate), Self.safeCandidate(englishCandidate)
    else { return .unchanged(.protectedToken) }

    // Both inputs are complete words. The caller, not this engine, establishes
    // physical-key provenance and computes representations in the two layouts.
    let candidates = [(russianCandidate, russianLayout), (englishCandidate, englishLayout)]
    let classifications = candidates.map {
      classifier.classifyToken($0.0, languagePair: "ru-en", forceComplete: true)
    }
    if punctuationSource {
      guard classifications[0].status == .known,
        classifications[1].status == .scored, classifications[1].score < 0
      else { return .unchanged(.protectedToken) }
    }
    var scored: (text: String, layout: LayoutID, score: Int32)?
    var known: (text: String, layout: LayoutID)?
    var allScoredZero = true
    var unsupported = false
    for ((text, layout), result) in zip(candidates, classifications) {
      switch result.status {
      case .unsupported:
        // This also represents local resource/overflow failures. Unlike the
        // reference selector's skipped category0, fail closed for these errors.
        unsupported = true
      case .rejected: return .unchanged(.ambiguous)
      case .known: known = (text, layout)
      case .scored:
        if result.score != 0 { allScoredZero = false }
        if scored == nil || result.score > scored!.score { scored = (text, layout, result.score) }
      }
    }
    guard !unsupported else { return .unchanged(.unsupportedLayout) }
    let selected: (text: String, layout: LayoutID)
    let layoutAbstained = known == nil && allScoredZero
    if let known { selected = known }
    else if let scored, !allScoredZero { selected = (scored.text, scored.layout) }
    // Local integration policy: a layout abstention may still apply a
    // dictionary correction in the verified source layout. It cannot switch it.
    else { selected = (word.text, word.layout) }
    guard Self.safeWord(selected.text) else { return .unchanged(.protectedToken) }
    guard !wordPolicy.containsExcluded(selected.text) else { return .unchanged(.excludedWord) }
    let corrected = autocorrector.correct(selected.text, typoEnabled: preferences.typoEnabled,
      yoEnabled: preferences.yoEnabled, forceComplete: true)
    guard corrected.status != .unsupported else { return .unchanged(.ambiguous) }
    let output = corrected.replacement ?? selected.text
    guard !wordPolicy.containsExcluded(output) else { return .unchanged(.excludedWord) }
    guard Self.safeWord(output) else { return .unchanged(.protectedToken) }
    guard output != word.text else { return .unchanged(layoutAbstained ? .ambiguous : .correct) }
    var kinds: [CorrectionKind] = []
    if selected.layout != word.layout { kinds.append(.layout) }
    if corrected.appliedTypo { kinds.append(.typo) }
    if corrected.appliedYo { kinds.append(.yo) }
    guard !kinds.isEmpty else { return .unchanged(.ambiguous) }
    return .replace(.init(original: word.text, replacement: output, sourceLayout: word.layout,
      targetLayout: selected.layout, modelVersion: modelVersion,
      kind: kinds.count == 1 ? kinds[0] : .combined))
  }
  // A physical alternative can contain layout punctuation even when the
  // selected word is ordinary Russian. Validate text safety after selection.
  private static func safeCandidate(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 128 && text.utf8.count <= 512 &&
      text.utf16.count <= 512 && text.unicodeScalars.allSatisfy {
        $0.value >= 32 && $0.value != 127 && !$0.properties.isWhitespace
      }
  }
  // This exception requires an explicit captured-key proof AND a known Russian
  // alternative against a negatively scored English spelling. It is not a
  // general URL detector: common suffixes/multiple dots remain protected, while
  // unfamiliar single-dot spellings still require both classifier assertions.
  private static func physicalPunctuationSource(_ text: String) -> Bool {
    guard safeCandidate(text) else { return false }
    let punctuation: Set<UInt32> = [39, 44, 46, 59, 91, 93, 96]
    var letters = false
    var symbols = false
    var dots = 0
    for scalar in text.unicodeScalars {
      if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
        letters = true
      } else if punctuation.contains(scalar.value) {
        symbols = true
        if scalar.value == 46 { dots += 1 }
      } else { return false }
    }
    guard letters, symbols, dots <= 1 else { return false }
    if dots == 1 {
      let suffix = text.split(separator: ".", omittingEmptySubsequences: false).last!.lowercased()
      let protectedSuffixes: Set<String> = ["com", "org", "net", "ru", "io", "dev", "app",
        "edu", "gov", "mil", "int", "co", "uk", "de", "fr", "info", "biz", "me"]
      if protectedSuffixes.contains(suffix) { return false }
    }
    return true
  }
  private static func safeWord(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 128 && text.utf8.count <= 512 &&
      text.utf16.count <= 512 && !TokenGuard.isProtected(text)
  }
}
