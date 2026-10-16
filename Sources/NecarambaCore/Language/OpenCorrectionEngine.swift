import Foundation

/// Independent, conservative lexical policy over caller-verified RU/EN candidates.
public struct OpenCorrectionEngine: Sendable {
    private let lexicon: any OpenWordLookup
    private let rules: OpenCorrectionRules
    /// Words whose е/ё ambiguity this model classifies more precisely than a generic protected token.
    public var yoProtectedWords: Set<String> { rules.yoProtectedWords }
    public init(lexicon: any OpenWordLookup, rules: OpenCorrectionRules) {
        self.lexicon = lexicon; self.rules = rules
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
        func excludedWord(_ text: String) -> Bool { wordPolicy.containsExcluded(text) }
        func protectedWord(_ text: String) -> Bool { rules.protectedWords.contains(TokenGuard.normalized(text)) }
        func yoProtectedWord(_ text: String) -> Bool { rules.yoProtectedWords.contains(TokenGuard.normalized(text)) }
        // Only an authored contraction may carry an apostrophe; its letters keep every case guard.
        func contraction(_ text: String) -> Bool {
            rules.contractions.contains(TokenGuard.normalized(text)) &&
                !TokenGuard.isProtected(text.replacingOccurrences(of: "'", with: ""))
        }
        guard !excludedWord(word.text) else { return .unchanged(.excludedWord) }
        guard !protectedWord(word.text), !yoProtectedWord(word.text), Self.bounded(word.text), Self.bounded(russianCandidate), Self.bounded(englishCandidate) else { return .unchanged(.protectedToken) }
        guard russianLayout != englishLayout,
            (word.layout == russianLayout && word.text == russianCandidate) || (word.layout == englishLayout && word.text == englishCandidate),
            word.events.allSatisfy({ $0.context == word.context && $0.layout == word.layout }) else { return .unchanged(.unsupportedLayout) }
        let punctuationSource = TokenGuard.isProtected(word.text)
        if punctuationSource {
            guard physicalCandidatesVerified, word.layout == englishLayout,
                  Self.punctuationSource(word.text), !word.events.isEmpty,
                  word.events.allSatisfy({ $0.origin == .physical && $0.kind == .down && $0.text?.count == 1 && $0.modifiers.isSubset(of: [.shift]) }),
                  word.events.compactMap(\.text).joined() == word.text,
                  !TokenGuard.isProtected(russianCandidate),
                  (!Self.leadingShiftedMark(word.text) || word.events.first?.modifiers.contains(.shift) == true) else { return .unchanged(.protectedToken) }
        }
        let sourceLanguage: Language = word.layout == russianLayout ? .russian : .english
        let targetLanguage: Language = sourceLanguage == .russian ? .english : .russian
        let alternative = sourceLanguage == .russian ? englishCandidate : russianCandidate
        let alternativeLayout = sourceLanguage == .russian ? englishLayout : russianLayout
        func known(_ text: String, _ language: Language) -> Bool {
            lexicon.contains(TokenGuard.normalized(text), language: language) || (language == .english && contraction(text))
        }
        func repairKnown(_ value: String, _ language: Language) -> Bool {
            guard !TokenGuard.isProtected(value) else { return false }
            let normalized = TokenGuard.normalized(value)
            if preferences.typoEnabled, let target = rules.typos[normalized], known(target, language) { return true }
            if preferences.yoEnabled, let target = rules.yo[normalized], known(target, language) { return true }
            return false
        }
        let sourceKnown = known(word.text, sourceLanguage)
        var text = word.text, layout = word.layout, language = sourceLanguage
        var kinds: [CorrectionKind] = []
        let sourceRepair = !sourceKnown && repairKnown(word.text, sourceLanguage)
        let alternativeKnown = known(alternative, targetLanguage)
        let alternativeRepair = !alternativeKnown && repairKnown(alternative, targetLanguage)
        if !sourceKnown, sourceRepair && (alternativeKnown || alternativeRepair) { return .unchanged(.ambiguous) }
        if !sourceKnown, (alternativeKnown || alternativeRepair),
           !TokenGuard.isProtected(alternative) || (targetLanguage == .english && contraction(alternative)),
           !protectedWord(alternative) {
            text = alternative; layout = alternativeLayout; language = targetLanguage; kinds.append(.layout)
        }
        if punctuationSource && kinds.isEmpty { return .unchanged(.protectedToken) }
        guard !excludedWord(text) else { return .unchanged(.excludedWord) }
        // Typos cannot overwrite valid words. Explicit curated ё preferences may
        // replace an accepted е spelling; ambiguity exclusions live in the rules.
        if !known(text, language), preferences.typoEnabled,
           let target = rules.typos[TokenGuard.normalized(text)], known(target, language) {
            text = RuleIndex.preserveCase(text, target: target); kinds.append(.typo)
        }
        guard !excludedWord(text) else { return .unchanged(.excludedWord) }
        guard !protectedWord(text) else { return .unchanged(.protectedToken) }
        if preferences.yoEnabled, !yoProtectedWord(text), let target = rules.yo[TokenGuard.normalized(text)], known(target, language) {
            text = RuleIndex.preserveCase(text, target: target); kinds.append(.yo)
        }
        if preferences.typoEnabled, let caps = RuleIndex.doubleCapsCandidate(text), known(caps, language) {
            text = caps; kinds.append(.doubleCaps)
        }
        guard !excludedWord(text) else { return .unchanged(.excludedWord) }
        guard !protectedWord(text), !TokenGuard.isProtected(text) || (language == .english && contraction(text))
        else { return .unchanged(.protectedToken) }
        guard text != word.text, !kinds.isEmpty else { return .unchanged(sourceKnown ? .correct : .ambiguous) }
        return .replace(.init(original: word.text, replacement: text, sourceLayout: word.layout,
            targetLayout: layout, modelVersion: modelVersion, kind: kinds.count == 1 ? kinds[0] : .combined))
    }
    private static func bounded(_ text: String) -> Bool { !text.isEmpty && text.count <= 128 && text.utf8.count <= 512 }
    private static func leadingShiftedMark(_ text: String) -> Bool {
        text.first.map { Set<Character>([":", "<", ">", "{", "}", "\"", "~"]).contains($0) } ?? false
    }
    private static func punctuationSource(_ text: String) -> Bool {
        // Shifted punctuation is only a leading title-case key, never embedded
        // colon/comparison syntax. The caller must prove the captured sequence.
        let shifted: Set<Character> = [":", "<", ">", "{", "}", "\"", "~"]
        if let first = text.first, shifted.contains(first) {
            return bounded(text) && text.count > 1 && text.dropFirst().allSatisfy { $0.isASCII && $0.isLowercase }
        }
        // Grave and backslash carry ё in the Russian-PC and macOS Russian layouts.
        let marks: Set<Character> = ["'", ",", ".", ";", "[", "]", "`", "\\"]
        guard bounded(text), text.contains(where: { marks.contains($0) }),
              text.allSatisfy({ marks.contains($0) || $0.isASCII && $0.isLetter }) else { return false }
        let letters = String(text.filter(\.isLetter))
        guard !letters.isEmpty, !TokenGuard.isProtected(letters) else { return false }
        let dots = text.filter { $0 == "." }.count
        guard dots <= 1 else { return false }
        if dots == 1 {
            let suffix = text.split(separator: ".", omittingEmptySubsequences: false).last!.lowercased()
            let protected: Set<String> = ["com", "org", "net", "ru", "io", "dev", "app", "edu", "gov", "mil", "int", "co", "uk", "de", "fr", "info", "biz", "me"]
            if protected.contains(suffix) { return false }
        }
        return true
    }
}
