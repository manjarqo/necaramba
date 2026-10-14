import Foundation
public enum TokenGuard {
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func isProtected(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let scalars = text.unicodeScalars
        if scalars.contains(where: { !CharacterSet.letters.contains($0) && !CharacterSet.nonBaseCharacters.contains($0) }) { return true }
        let latin = scalars.contains { (0x41...0x7A).contains($0.value) && CharacterSet.letters.contains($0) }
        let cyrillic = scalars.contains { (0x400...0x52F).contains($0.value) }
        if latin && cyrillic { return true }
        let letters = text.filter { $0.isLetter }
        if letters.count > 1 && letters == letters.uppercased() { return true }
        let title = text.prefix(1).uppercased() + text.dropFirst().lowercased()
        return text != text.lowercased() && text != title && RuleIndex.doubleCapsCandidate(text) == nil
    }
}
