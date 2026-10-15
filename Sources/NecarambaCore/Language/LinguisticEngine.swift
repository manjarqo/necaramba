import Foundation
public enum DecisionReason: String, Sendable, Equatable { case correct, ambiguous, protectedToken, excludedWord, disabled, unsupportedLayout }
public enum CorrectionKind: String, Sendable, Equatable { case layout, typo, doubleCaps, yo, combined }
public struct Correction: Sendable, Equatable {
    public let original: String
    public let replacement: String
    public let sourceLayout: LayoutID
    public let targetLayout: LayoutID
    public let modelVersion: UInt64
    public let kind: CorrectionKind
    public init(original: String, replacement: String, sourceLayout: LayoutID, targetLayout: LayoutID, modelVersion: UInt64, kind: CorrectionKind) {
        self.original = original; self.replacement = replacement; self.sourceLayout = sourceLayout; self.targetLayout = targetLayout; self.modelVersion = modelVersion; self.kind = kind
    }
}
public enum LinguisticDecision: Sendable, Equatable { case unchanged(DecisionReason), replace(Correction) }

/// Conservative working slice. Release enablement requires the independent corpus gate.
public struct LinguisticEngine: Sendable {
    private let snapshot: RuleSnapshot
    private let index: RuleIndex
    private let physicalMappings: [PhysicalLayoutMapping]
    public init(snapshot: RuleSnapshot, physicalMappings: [PhysicalLayoutMapping] = []) {
        self.snapshot = snapshot; self.index = RuleIndex(snapshot: snapshot); self.physicalMappings = physicalMappings
    }
    public func decide(word: BufferedWord, preferences: PreferencesSnapshot, excludedWords: Set<String>) -> LinguisticDecision {
        guard preferences.autoEnabled else { return .unchanged(.disabled) }
        return decide(word: word, preferences: preferences,
            wordPolicy: PreparedWordPolicy(excluded: excludedWords, protected: []))
    }
    public func decide(word: BufferedWord, preferences: PreferencesSnapshot, wordPolicy: PreparedWordPolicy) -> LinguisticDecision {
        guard preferences.autoEnabled else { return .unchanged(.disabled) }
        guard !wordPolicy.containsExcluded(word.text) else { return .unchanged(.excludedWord) }
        let confirmedCapsLock = !word.events.isEmpty && word.events.allSatisfy {
            $0.origin == .physical && $0.kind == .down && $0.modifiers.contains(.capsLock) && !$0.modifiers.contains(.shift)
        }
        func protected(_ text: String) -> Bool { index.isProtected(confirmedCapsLock ? text.lowercased() : text) }
        let punctuationSource = TokenGuard.isPotentialPhysicalLayoutSource(word.text)
        if punctuationSource {
            guard !index.isExplicitlyProtected(word.text) else { return .unchanged(.protectedToken) }
            // The visible text must be the exact recorded physical sequence. Never infer
            // punctuation from character pairs, selection text, or unsupported layouts.
            guard !physicalMappings.isEmpty, !word.events.isEmpty,
                  word.events.allSatisfy({ $0.origin == .physical && $0.kind == .down && $0.text?.count == 1 }),
                  word.events.compactMap(\.text).joined() == word.text else { return .unchanged(.protectedToken) }
        } else if protected(word.text) { return .unchanged(.protectedToken) }
        var candidate = word.text
        var targetLayout = word.layout
        var kinds: [CorrectionKind] = []
        if !word.events.isEmpty && !word.events.allSatisfy({ $0.context == word.context && $0.layout == word.layout }) {
            return .unchanged(.unsupportedLayout)
        }
        var physicalSupported = word.events.isEmpty
        var candidates: [(String, LayoutID)] = []
        for mapping in snapshot.mappings where mapping.source == word.layout {
            let converted: String?
            if word.events.isEmpty { converted = LayoutConverter.convert(word.text, mapping: mapping) }
            else if physicalMappings.isEmpty { converted = LayoutConverter.convert(keys: word.events, to: mapping.target, mappings: snapshot.mappings) }
            else { converted = LayoutConverter.convert(keys: word.events, to: mapping.target, physicalMappings: physicalMappings) }
            if converted != nil { physicalSupported = true }
            if let converted, converted != word.text, index.isKnown(converted), !protected(converted),
               (!punctuationSource || converted.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })) {
                candidates.append((converted, mapping.target))
            }
        }
        if candidates.count > 1 || (index.isKnown(word.text) && !candidates.isEmpty) { return .unchanged(.ambiguous) }
        if !index.isKnown(word.text), let chosen = candidates.first {
            candidate = chosen.0; targetLayout = chosen.1; kinds.append(.layout)
        }
        if punctuationSource && kinds.isEmpty { return .unchanged(.protectedToken) }
        guard !wordPolicy.containsExcluded(candidate) else { return .unchanged(.excludedWord) }
        if preferences.typoEnabled, let typo = index.typo(for: candidate), index.isKnown(typo), typo != candidate {
            candidate = typo; kinds.append(.typo)
        }
        guard !wordPolicy.containsExcluded(candidate) else { return .unchanged(.excludedWord) }
        if preferences.typoEnabled, let caps = RuleIndex.doubleCapsCandidate(candidate), index.isKnown(caps), caps != candidate {
            candidate = caps; kinds.append(.doubleCaps)
        }
        guard !wordPolicy.containsExcluded(candidate) else { return .unchanged(.excludedWord) }
        if preferences.yoEnabled, let yo = index.yo(for: candidate), index.isKnown(yo), yo != candidate {
            candidate = yo; kinds.append(.yo)
        }
        guard !wordPolicy.containsExcluded(candidate) else { return .unchanged(.excludedWord) }
        guard !kinds.isEmpty else {
            if index.isKnown(word.text) { return .unchanged(.correct) }
            return .unchanged(physicalSupported ? .ambiguous : .unsupportedLayout)
        }
        guard !protected(candidate) else { return .unchanged(.protectedToken) }
        return .replace(.init(original: word.text, replacement: candidate, sourceLayout: word.layout, targetLayout: targetLayout, modelVersion: snapshot.modelVersion, kind: kinds.count == 1 ? kinds[0] : .combined))
    }
}
