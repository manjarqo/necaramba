/// A bounded UTF-8 splice operation over already-selected pattern material.
public struct PatternRewriteRule: Sendable {
  public let prefixBytes: Int
  public let suffixBytes: Int
  public let insertion: String
  public init(prefixBytes: Int, suffixBytes: Int, insertion: String) {
    self.prefixBytes = prefixBytes; self.suffixBytes = suffixBytes; self.insertion = insertion
  }
  /// Matching, anchors and case projection belong to the caller. Invalid byte
  /// counts or an invalid UTF-8 result never produce lossy Unicode text.
  public func apply(to material: String) -> String? {
    let count = material.utf8.count
    guard count <= 512, insertion.utf8.count <= 512,
      prefixBytes >= 0, suffixBytes >= 0,
      prefixBytes <= count, suffixBytes <= count - prefixBytes,
      prefixBytes + suffixBytes + insertion.utf8.count <= 512 else { return nil }
    let bytes = Array(material.utf8)
    let result = Array(bytes.prefix(prefixBytes)) + Array(insertion.utf8) + Array(bytes.suffix(suffixBytes))
    return String(bytes: result, encoding: .utf8)
  }
}
