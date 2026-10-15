import Foundation
import CryptoKit
import NecarambaCore
import NecarambaMac

func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func run() throws {
    let usage = "Usage: OpenModelV2Runner --directory Resources/OpenModel --output report.json [--reference absolute-file] [--split calibration|holdout]"
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 4, args.count.isMultiple(of: 2) else { throw CorpusValidationError.invalid(usage) }
    var options: [String: String] = [:]
    for i in stride(from: 0, to: args.count, by: 2) {
        guard ["--directory", "--output", "--reference", "--split"].contains(args[i]), options[args[i]] == nil else { throw CorpusValidationError.invalid(usage) }
        options[args[i]] = args[i + 1]
    }
    guard let directory = options["--directory"], let output = options["--output"],
          let split = CorpusSplit(rawValue: options["--split"] ?? "calibration"), split != .train,
          options["--reference"].map({ $0.hasPrefix("/") }) ?? true else { throw CorpusValidationError.invalid(usage) }
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).resolvingSymlinksInPath()
    func read(_ path: String) throws -> Data {
        try CorpusManifest.validateRelativePath(path)
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else { throw CorpusValidationError.invalid("Manifest path escapes repository") }
        return try Data(contentsOf: url)
    }
    let manifest = try CorpusManifest.decode(read("Corpora/manifest.json"))
    let all = try manifest.validate(read: read, digest: digest)
    let rows = all.filter { $0.split == split }
    let baseline = try JSONDecoder().decode(RuleSnapshot.self, from: read(manifest.rules.path))
    let us = LayoutID(rawValue: "US"), ru = LayoutID(rawValue: "RU")
    guard let usToRu = baseline.mappings.first(where: { $0.source == us && $0.target == ru }),
          let ruToUs = baseline.mappings.first(where: { $0.source == ru && $0.target == us }) else { throw CorpusValidationError.invalid("Missing RU/US mapping") }
    let began = ProcessInfo.processInfo.systemUptime
    let model = try OpenModelLoader.load(directory: URL(fileURLWithPath: directory, isDirectory: true))
    let initialization = ProcessInfo.processInfo.systemUptime - began
    let context = ContextToken(pid: 0, bundleID: "synthetic.open-model.physical-fixture", focusEpoch: 1, layoutEpoch: 1)
    let shiftedUS: [String: String] = [";": ":", ",": "<", ".": ">", "[": "{", "]": "}", "'": "\"", "`": "~"]
    let unshiftedUS = Dictionary(uniqueKeysWithValues: shiftedUS.map { ($0.value, $0.key) })
    func physicalCandidate(_ text: String, from layout: LayoutID) -> String {
        text.map { char in
            let value = String(char)
            if layout == us {
                if let base = unshiftedUS[value], let mapped = usToRu.pairs[base] { return mapped.uppercased() }
                return LayoutConverter.convert(value, mapping: usToRu)
            }
            if char.isUppercase, let mapped = ruToUs.pairs[value.lowercased()] { return shiftedUS[mapped] ?? mapped.uppercased() }
            return LayoutConverter.convert(value, mapping: ruToUs)
        }.joined()
    }
    func inputs(_ text: String, layout: LayoutID) -> (BufferedWord, String, String) {
        // Recorded visible characters are exact; fixture key codes are not native
        // hardware claims. Candidate mapping preserves punctuation and case.
        let events = text.enumerated().map { offset, char in
            InputEvent(kind: .down, keyCode: UInt16(offset), modifiers: char.isUppercase || unshiftedUS[String(char)] != nil ? [.shift] : [], timestampNanos: UInt64(offset + 1), layout: layout, context: context, origin: .physical, text: String(char), isRepeat: false)
        }
        return (.init(text: text, events: events, context: context, layout: layout, delimiter: " "),
                layout == ru ? text : physicalCandidate(text, from: us),
                layout == us ? text : physicalCandidate(text, from: ru))
    }
    func result(_ decision: LinguisticDecision, input: String) -> String {
        if case .replace(let correction) = decision { return correction.replacement }; return input
    }
    func predict(_ text: String, layout: LayoutID) -> String {
        let (word, russian, english) = inputs(text, layout: layout)
        return result(model.engine.decide(word: word, russianCandidate: russian, russianLayout: ru, englishCandidate: english, englishLayout: us,
            preferences: .init(typoEnabled: true, yoEnabled: true), excludedWords: [], modelVersion: baseline.modelVersion, physicalCandidatesVerified: true), input: text)
    }
    func object(_ quality: QualityReport, aggregateOnly: Bool = false) throws -> [String: Any] {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(quality)) as! [String: Any]
        if aggregateOnly {
            // Never persist reference-derived words, mismatches, or per-token labels.
            let allowed: Set<String> = ["total", "truePositive", "falsePositive", "falseNegative", "precision", "falseChangeRate", "recall", "layoutRecall", "precisionInterval", "falseChangeInterval", "layoutRecallInterval", "counts", "tokenQualityPassed", "physicalDifferentialQualified", "passed"]
            value = value.filter { allowed.contains($0.key) }
        }
        return value
    }
    let evaluationStart = ProcessInfo.processInfo.systemUptime
    let quality = QualityEvaluator.evaluate(rows) { predict($0.input, layout: $0.layout) }
    let elapsed = ProcessInfo.processInfo.systemUptime - evaluationStart
    let cases: [(String, String, String, String)] = [
        ("ground-correct", "ground", "US", "ground"), ("ground-wrong", "пкщгтв", "RU", "ground"),
        ("connector-correct", "connector", "US", "connector"), ("connector-wrong", "сщттусещк", "RU", "connector"),
        ("also-correct", "тоже", "RU", "тоже"), ("also-wrong", "nj;t", "US", "тоже"),
        ("switched-correct", "переключилось", "RU", "переключилось"), ("switched-wrong", "gthtrk.xbkjcm", "US", "переключилось"),
        ("periodically-correct", "периодически", "RU", "периодически"), ("periodically-wrong", "gthbjlbxtcrb", "US", "периодически"),
        ("not-wrong", "yt", "US", "не"), ("version", "1.3.166", "US", "1.3.166"), ("version-ru", "1ю3ю166", "RU", "1ю3ю166"),
        ("url", "https://example.com", "US", "https://example.com"), ("email", "user@example.com", "US", "user@example.com"),
        ("code", "foo(bar)", "US", "foo(bar)"), ("acronym", "API", "US", "API"),
        ("ambiguous-en", "he", "US", "he"), ("ambiguous-ru", "ру", "RU", "ру"),
        ("typo-en", "recieve", "US", "receive"), ("typo-title", "Recieve", "US", "Receive"),
        ("typo-ru", "превет", "RU", "привет"), ("yo-curated", "ежик", "RU", "ёжик"),
        ("yo-known", "ёжик", "RU", "ёжик"), ("double-caps", "HEllo", "US", "Hello"),
        ("mixed-case", "heLLo", "US", "heLLo"), ("title-colon", ":tycrbq", "US", "Женский"),
        ("title-comma", "<sdfkj", "US", "Бывало"), ("embedded-colon", "foo:bar", "US", "foo:bar")
    ]
    let regressions: [[String: Any]] = cases.map { id, input, source, expected in
        let actual = predict(input, layout: .init(rawValue: source))
        return ["id": id, "input": input, "layout": source, "expected": expected, "actual": actual, "passed": expected == actual]
    }
    // A declared-rule consistency audit is not independent quality evidence.
    let correctionObject = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("corrections.json"))) as! [String: Any]
    let consistency: [[String: Any]] = ["typos", "yo"].flatMap { kind in
        (correctionObject[kind] as? [[String: String]] ?? []).map { rule in
            let source = rule["source"]!, expected = rule["target"]!
            let layout = expected.unicodeScalars.contains { (0x400...0x4ff).contains($0.value) } ? ru : us
            let actual = predict(source, layout: layout)
            return ["kind": kind, "input": source, "expected": expected, "actual": actual, "passed": actual == expected] as [String: Any]
        }
    }
    var report: [String: Any] = [
        "schemaVersion": 2, "modelVersion": model.version,
        "modelManifestSHA256": digest(try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("manifest.json"))),
        "corpusVersion": manifest.corpusVersion, "rulesSHA256": manifest.rules.sha256, "split": split.rawValue,
        "releaseReady": false, "open": try object(quality), "regressions": regressions,
        "ruleConsistencyAudit": ["total": consistency.count, "passed": consistency.filter { $0["passed"] as? Bool == true }.count,
            "failures": consistency.filter { $0["passed"] as? Bool == false }, "scope": "own declared rules, not held-out quality evidence"],
        "regressionsPassed": regressions.filter { $0["passed"] as? Bool == true }.count,
        "openInitializationSeconds": initialization, "openEvaluationSeconds": elapsed,
        "openCasesPerSecond": elapsed > 0 ? Double(rows.count) / elapsed : 0,
        "evaluationMode": "frozen corpus with simulated physical provenance; character-table candidates, not hardware capture",
        "preferences": "automatic, typo and yo enabled; no excluded words",
        "physicalDifferentialEvidence": "UNRUN", "manualVersionSwitching": "UNRUN; numeric cases assert automatic abstention",
        "referencePolicy": "optional local reference; aggregate metrics only, never model extraction or per-token outputs",
        "timingScope": "single local process, debug/release build dependent; evaluation includes synthetic event construction and metrics"
    ]
    if let path = options["--reference"] {
        let referenceStart = ProcessInfo.processInfo.systemUptime
        let local = try LocalPatternModelLoader.load(url: URL(fileURLWithPath: path))
        let reference = PatternCorrectionEngine(classifier: local.classifier, autocorrector: local.autocorrector)
        report["referenceInitializationSeconds"] = ProcessInfo.processInfo.systemUptime - referenceStart
        let started = ProcessInfo.processInfo.systemUptime
        let referenceQuality = QualityEvaluator.evaluate(rows) { row in
            let (word, russian, english) = inputs(row.input, layout: row.layout)
            return result(reference.decide(word: word, russianCandidate: russian, russianLayout: ru, englishCandidate: english, englishLayout: us,
                preferences: .init(typoEnabled: true, yoEnabled: true), excludedWords: [], modelVersion: baseline.modelVersion, physicalCandidatesVerified: true), input: row.input)
        }
        report["reference"] = try object(referenceQuality, aggregateOnly: true)
        report["referenceEvaluationSeconds"] = ProcessInfo.processInfo.systemUptime - started
    }
    let destination = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: destination, options: .atomic)
    print("Wrote \(split.rawValue) evidence; open TP=\(quality.truePositive) FP=\(quality.falsePositive) FN=\(quality.falseNegative). Hardware/editor qualification UNRUN.")
}
do { try run() } catch { fputs("OpenModelV2Runner: \(error)\n", stderr); exit(2) }
