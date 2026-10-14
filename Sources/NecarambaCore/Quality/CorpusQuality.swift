import Foundation

public enum CorpusSplit: String, Codable, Sendable { case train, calibration, holdout }
public enum CorpusCaseShape: String, Codable, Sendable { case lowercase, title, uppercase, doubleCaps, mixed, unspecified }
public enum CorpusApplicationCategory: String, Codable, Sendable { case editor, browser, terminal, office, chat, unspecified }
public struct CorpusCase: Codable, Sendable {
    public let id: String
    public let input: String
    public let layout: LayoutID
    public let expected: String
    public let shouldChange: Bool
    public let split: CorpusSplit
    public let sourceLicense: String
    public let category: String
    public let family: String
    public let language: Language?
    public let caseShape: CorpusCaseShape?
    public let applicationCategory: CorpusApplicationCategory?
    public let hostScenarioID: String?
    public init(id: String, input: String, layout: LayoutID, expected: String, shouldChange: Bool, split: CorpusSplit, sourceLicense: String, category: String, family: String, language: Language? = nil, caseShape: CorpusCaseShape? = nil, applicationCategory: CorpusApplicationCategory? = nil, hostScenarioID: String? = nil) {
        self.id = id; self.input = input; self.layout = layout; self.expected = expected; self.shouldChange = shouldChange; self.split = split; self.sourceLicense = sourceLicense; self.category = category; self.family = family
        self.language = language; self.caseShape = caseShape; self.applicationCategory = applicationCategory; self.hostScenarioID = hostScenarioID
    }
}
public enum CorpusValidationError: Error { case invalid(String) }
public enum CorpusValidator {
    public static func normalizedFamily(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func decodeJSONL(_ data: Data) throws -> [CorpusCase] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw CorpusValidationError.invalid("Empty/non-UTF8 JSONL") }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let allowed = Set(["id", "input", "layout", "expected", "shouldChange", "split", "sourceLicense", "category", "family"])
        return try lines.enumerated().map { index, line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let bytes = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], (Set(object.keys) == allowed || Set(object.keys) == allowed.union(["language", "caseShape", "applicationCategory", "hostScenarioID"])) else {
                throw CorpusValidationError.invalid("Invalid schema at line \(index + 1)")
            }
            return try JSONDecoder().decode(CorpusCase.self, from: bytes)
        }
    }
    public static func caseShape(of input: String) -> CorpusCaseShape {
        let letters = String(input.filter(\.isLetter))
        guard !letters.isEmpty else { return .mixed }
        if letters == letters.lowercased() { return .lowercase }
        if letters == letters.uppercased() { return .uppercase }
        if RuleIndex.doubleCapsCandidate(letters) != nil { return .doubleCaps }
        if letters == letters.prefix(1).uppercased() + letters.dropFirst().lowercased() { return .title }
        return .mixed
    }
    public static func validate(_ rows: [CorpusCase]) throws {
        guard !rows.isEmpty else { throw CorpusValidationError.invalid("Empty corpus") }
        var labels: [LayoutID: [String: String]] = [:]
        var ids = Set<String>(); var families: [String: CorpusSplit] = [:]; var tokens: [String: CorpusSplit] = [:]
        for row in rows {
            guard !row.id.isEmpty, !row.input.isEmpty, !row.expected.isEmpty, !row.layout.rawValue.isEmpty, !row.category.isEmpty, !row.sourceLicense.isEmpty, !row.family.isEmpty,
                  row.shouldChange == (row.input != row.expected), ids.insert(row.id).inserted else {
                throw CorpusValidationError.invalid("Invalid or duplicate row \(row.id)")
            }
            if row.language != nil || row.caseShape != nil || row.applicationCategory != nil || row.hostScenarioID != nil {
                guard row.language != nil, let shape = row.caseShape, shape != .unspecified,
                      let application = row.applicationCategory, application != .unspecified,
                      row.hostScenarioID == "synthetic.\(application.rawValue).token-only",
                      shape == caseShape(of: row.input) else { throw CorpusValidationError.invalid("Invalid synthetic strata metadata: \(row.id)") }
            }
            if let expected = labels[row.layout]?[row.input], expected != row.expected { throw CorpusValidationError.invalid("Contradictory label: \(row.id)") }
            labels[row.layout, default: [:]][row.input] = row.expected
            let family = normalizedFamily(row.family)
            if let existing = families[family], existing != row.split { throw CorpusValidationError.invalid("Family leakage: \(family)") }
            families[family] = row.split
            for value in [row.input, row.expected] {
                let token = normalizedFamily(value)
                if let existing = tokens[token], existing != row.split { throw CorpusValidationError.invalid("Normalized token leakage: \(token)") }
                tokens[token] = row.split
            }
        }
    }
}
public struct ConfusionCounts: Codable, Sendable {
    public var total = 0, truePositive = 0, falsePositive = 0, falseNegative = 0, trueNegative = 0, noChange = 0, falseChanges = 0
    public var precision: Double? { truePositive + falsePositive > 0 ? Double(truePositive) / Double(truePositive + falsePositive) : nil }
    public var recall: Double? { truePositive + falseNegative > 0 ? Double(truePositive) / Double(truePositive + falseNegative) : nil }
    public var falseChangeRate: Double? { noChange > 0 ? Double(falseChanges) / Double(noChange) : nil }
}
public struct CorpusMismatch: Codable, Sendable { public let id: String; public let category: String; public let input: String; public let expected: String; public let actual: String }
public struct MetricInterval: Codable, Sendable { public let lower: Double; public let upper: Double }
public struct CoverageMeasurement: Codable, Sendable {
    public let samples: Int
    public let independentFamilies: Int
    public let minimumIndependentFamilies: Int
    public let passed: Bool
    public init(samples: Int, independentFamilies: Int, minimumIndependentFamilies: Int) {
        self.samples = samples; self.independentFamilies = independentFamilies
        self.minimumIndependentFamilies = minimumIndependentFamilies; self.passed = independentFamilies >= minimumIndependentFamilies
    }
}
public struct QualityReport: Codable, Sendable {
    public let total: Int, truePositive: Int, falsePositive: Int, falseNegative: Int
    public let precision: Double?, falseChangeRate: Double?, recall: Double?, layoutRecall: Double?
    public let precisionInterval: MetricInterval?, falseChangeInterval: MetricInterval?, layoutRecallInterval: MetricInterval?
    public let counts: ConfusionCounts
    public let perCategory: [String: ConfusionCounts]
    public let mismatches: [CorpusMismatch]
    public let perStratum: [String: ConfusionCounts]
    public let coverage: [String: CoverageMeasurement]
    public let tokenQualityPassed: Bool
    public let physicalDifferentialQualified: Bool
    public let passed: Bool
    public let failures: [String]
}
public enum QualityEvaluator {
    /// Review v3 design minima count independent declared families, never repeated variants.
    /// These are coverage floors, not statistical claims of sufficient population power.
    public static let minimumIndependentFamilies: [String: Int] = [
        "feature.layout": 100, "feature.typo": 10, "feature.yo": 10, "feature.doubleCaps": 20,
        "language.english": 100, "language.russian": 100,
        "case.lowercase": 100, "case.title": 100, "case.uppercase": 100, "case.doubleCaps": 20, "case.mixed": 100,
        "application.editor": 100, "application.browser": 100, "application.terminal": 100, "application.office": 100, "application.chat": 100
    ]
    public static func evaluate(_ rows: [CorpusCase], physicalDifferentialQualified: Bool = false, predict: (CorpusCase) -> String) -> QualityReport {
        var counts = ConfusionCounts(), categories = Dictionary(uniqueKeysWithValues: ["typo", "yo", "doubleCaps"].map { ($0, ConfusionCounts()) }), mismatches: [CorpusMismatch] = []
        var strata: [String: ConfusionCounts] = [:], families: [String: Set<String>] = [:]
        var layoutCorrect = 0, layoutTotal = 0
        for row in rows {
            let actual = predict(row), changed = actual != row.input, exact = actual == row.expected
            func add(_ c: inout ConfusionCounts) {
                c.total += 1
                if row.shouldChange {
                    if exact { c.truePositive += 1 } else { c.falseNegative += 1; if changed { c.falsePositive += 1 } }
                } else {
                    c.noChange += 1
                    if changed { c.falsePositive += 1; c.falseChanges += 1 } else { c.trueNegative += 1 }
                }
            }
            add(&counts); var category = categories[row.category, default: ConfusionCounts()]; add(&category); categories[row.category] = category
            var keys: [String] = []
            if let language = row.language { keys.append("language." + language.rawValue) }
            if let shape = row.caseShape { keys.append("case." + shape.rawValue) }
            if let application = row.applicationCategory, row.hostScenarioID == "synthetic.\(application.rawValue).token-only" { keys.append("application." + application.rawValue) }
            if row.shouldChange, let feature = ["layout", "typo", "yo", "doubleCaps"].first(where: { row.category == $0 || row.category.hasPrefix($0 + ".") }) { keys.append("feature." + feature) }
            for key in keys {
                var stratum = strata[key, default: ConfusionCounts()]; add(&stratum); strata[key] = stratum
                families[key, default: []].insert(CorpusValidator.normalizedFamily(row.family))
            }
            if row.category.hasPrefix("layout") && row.shouldChange { layoutTotal += 1; if exact { layoutCorrect += 1 } }
            if !exact { mismatches.append(CorpusMismatch(id: row.id, category: row.category, input: row.input, expected: row.expected, actual: actual)) }
        }
        let layoutRecall = layoutTotal > 0 ? Double(layoutCorrect) / Double(layoutTotal) : nil
        var failures: [String] = []
        if counts.precision.map({ $0 >= 0.995 }) != true { failures.append("precision undefined or below 0.995") }
        if counts.falseChangeRate.map({ $0 <= 0.001 }) != true { failures.append("false-change rate undefined or above 0.001") }
        if layoutRecall.map({ $0 >= 0.95 }) != true { failures.append("layout recall undefined or below 0.95") }
        if rows.count < 2000 { failures.append("holdout has fewer than 2000 rows") }
        if counts.noChange < 1000 { failures.append("holdout has fewer than 1000 no-change rows") }
        var coverage: [String: CoverageMeasurement] = [:]
        for (key, minimum) in minimumIndependentFamilies {
            let measured = CoverageMeasurement(samples: strata[key]?.total ?? 0, independentFamilies: families[key]?.count ?? 0, minimumIndependentFamilies: minimum)
            coverage[key] = measured
            if !measured.passed { failures.append("coverage \(key): \(measured.independentFamilies) independent families < \(minimum)") }
        }
        let tokenQualityPassed = failures.isEmpty
        if !physicalDifferentialQualified { failures.append("physical differential UNRUN or unqualified") }
        return QualityReport(total: counts.total, truePositive: counts.truePositive, falsePositive: counts.falsePositive, falseNegative: counts.falseNegative, precision: counts.precision, falseChangeRate: counts.falseChangeRate, recall: counts.recall, layoutRecall: layoutRecall, precisionInterval: interval(counts.truePositive, counts.truePositive + counts.falsePositive), falseChangeInterval: interval(counts.falseChanges, counts.noChange), layoutRecallInterval: interval(layoutCorrect, layoutTotal), counts: counts, perCategory: categories, mismatches: mismatches, perStratum: strata, coverage: coverage, tokenQualityPassed: tokenQualityPassed, physicalDifferentialQualified: physicalDifferentialQualified, passed: failures.isEmpty, failures: failures)
    }
    /// Two-sided Wilson interval with z=1.96 (95%), including zero-error samples.
    public static func interval(_ successes: Int, _ total: Int) -> MetricInterval? {
        guard total > 0 else { return nil }
        let n = Double(total), p = Double(successes) / n, z = 1.96, d = 1 + z*z/n
        let center = (p + z*z/(2*n))/d, radius = z * sqrt(p*(1-p)/n + z*z/(4*n*n))/d
        return MetricInterval(lower: max(0, center-radius), upper: min(1, center+radius))
    }
}
