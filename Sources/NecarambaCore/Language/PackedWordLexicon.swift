import Foundation

/// Sorted newline-delimited UTF-8 with one 32-bit offset per word; no retained String index.
public struct PackedOpenLexicon: OpenWordLookup {
    public enum ValidationError: Error { case size, malformed, alphabet, order, count }
    public static let maximumDataSize = 64 * 1024 * 1024
    public static let maximumWordCount = 2_000_000
    private let english: PackedWordLexicon
    private let russian: PackedWordLexicon
    public var wordCount: Int { english.count + russian.count }
    public var storageByteCount: Int { english.storageByteCount + russian.storageByteCount }

    public init(english: Data, russian: Data) throws {
        guard !english.isEmpty, !russian.isEmpty, english.count <= Self.maximumDataSize,
              russian.count <= Self.maximumDataSize - english.count else { throw ValidationError.size }
        let en = try PackedWordLexicon(data: english, russian: false, maximumCount: Self.maximumWordCount)
        let ru = try PackedWordLexicon(data: russian, russian: true, maximumCount: Self.maximumWordCount - en.count)
        self.english = en
        self.russian = ru
    }

    public func contains(_ word: String, language: Language) -> Bool {
        switch language {
        case .english: return english.contains(word)
        case .russian: return russian.contains(word)
        }
    }
}

private struct PackedWordLexicon: Sendable {
    let data: Data
    let offsets: [UInt32]
    var count: Int { offsets.count - 1 }
    var storageByteCount: Int { data.count + offsets.count * MemoryLayout<UInt32>.stride }

    init(data: Data, russian: Bool, maximumCount: Int) throws {
        typealias Failure = PackedOpenLexicon.ValidationError
        self.data = data
        offsets = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt32] in
            guard bytes.last == 10 else { throw Failure.malformed }
            var starts: [UInt32] = []
            // A bounded initial reservation; growth never depends on a trusted record count.
            starts.reserveCapacity(min(maximumCount + 1, data.count / 12 + 1))
            var start = 0
            var cursor = 0
            var length = 0
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if byte == 10 {
                    guard cursor > start else { throw Failure.malformed }
                    guard starts.count < maximumCount else { throw Failure.count }
                    if let previous = starts.last {
                        let previousStart = Int(previous)
                        let previousEnd = start - 1
                        var p = previousStart, q = start
                        while p < previousEnd && q < cursor && bytes[p] == bytes[q] { p += 1; q += 1 }
                        let strictlyOrdered = p == previousEnd ? q < cursor : q < cursor && bytes[p] < bytes[q]
                        guard strictlyOrdered else { throw Failure.order }
                    }
                    starts.append(UInt32(start))
                    cursor += 1
                    start = cursor
                    length = 0
                    continue
                }
                length += 1
                guard length <= 128 else { throw Failure.malformed }
                if russian {
                    guard cursor + 1 < bytes.count else { throw Failure.alphabet }
                    let next = bytes[cursor + 1]
                    guard (byte == 0xD0 && (0xB0...0xBF).contains(next)) ||
                            (byte == 0xD1 && ((0x80...0x8F).contains(next) || next == 0x91)) else { throw Failure.alphabet }
                    cursor += 2
                } else {
                    guard (97...122).contains(byte) else { throw Failure.alphabet }
                    cursor += 1
                }
            }
            guard !starts.isEmpty else { throw Failure.malformed }
            starts.append(UInt32(bytes.count))
            return starts
        }
    }

    func contains(_ word: String) -> Bool {
        guard !word.isEmpty, word.utf8.count <= 256 else { return false }
        let query = Array(word.utf8)
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var low = 0, high = count
            while low < high {
                let mid = low + (high - low) / 2
                let start = Int(offsets[mid]), end = Int(offsets[mid + 1]) - 1
                let length = end - start
                var i = 0
                while i < min(length, query.count) && bytes[start + i] == query[i] { i += 1 }
                if i == length && i == query.count { return true }
                let storedLess = i == length || (i < query.count && bytes[start + i] < query[i])
                if storedLess { low = mid + 1 } else { high = mid }
            }
            return false
        }
    }
}
