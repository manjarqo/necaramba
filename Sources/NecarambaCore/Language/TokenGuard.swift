import Foundation
public enum TokenGuard {
    /// A narrow source shape. A physical map and a known target must still prove conversion.
    /// Dots are intentionally excluded: a single dot between letters is indistinguishable
    /// from a hostname or code member access without editor context.
    public static func isPotentialPhysicalLayoutSource(_ text: String) -> Bool {
        let punctuation = Set(",;'[]<>:\"{}".map(String.init))
        var punctuationCount = 0
        var letterCount = 0
        for character in text {
            let value = String(character)
            if punctuation.contains(value) { punctuationCount += 1; continue }
            guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first,
                  (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) else { return false }
            letterCount += 1
        }
        return punctuationCount == 1 && letterCount >= 2
    }
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func isProtected(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars
        if scalars.contains(where: { !CharacterSet.letters.contains($0) && !CharacterSet.nonBaseCharacters.contains($0) }) { return true }
        func isLatin(_ value: UInt32) -> Bool { (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) }
        func isRussian(_ value: UInt32) -> Bool { (0x410...0x44F).contains(value) || value == 0x401 || value == 0x451 }
        if scalars.contains(where: { CharacterSet.letters.contains($0) && !isLatin($0.value) && !isRussian($0.value) }) { return true }
        let latin = scalars.contains { isLatin($0.value) }
        let cyrillic = scalars.contains { isRussian($0.value) }
        if latin && cyrillic { return true }
        let letters = text.filter { $0.isLetter }
        if letters.count > 1 && letters == letters.uppercased() { return true }
        let title = text.prefix(1).uppercased() + text.dropFirst().lowercased()
        return text != text.lowercased() && text != title && RuleIndex.doubleCapsCandidate(text) == nil
    }
}
