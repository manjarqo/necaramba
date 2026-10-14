import Foundation
import CryptoKit
import NecarambaCore

func run() throws -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 6 else { throw CorpusValidationError.invalid("Usage: CorpusRunner --manifest Corpora/manifest.json --split holdout --output Reports/quality.json") }
    var options: [String: String] = [:]
    for i in stride(from: 0, to: arguments.count, by: 2) {
        guard ["--manifest", "--split", "--output"].contains(arguments[i]), options[arguments[i]] == nil else { throw CorpusValidationError.invalid("Unknown/duplicate argument") }
        options[arguments[i]] = arguments[i + 1]
    }
    guard let manifestPath = options["--manifest"], let split = CorpusSplit(rawValue: options["--split"] ?? ""), let output = options["--output"] else { throw CorpusValidationError.invalid("Missing/invalid arguments") }
    // Manifest paths are relative to the repository working directory, documented in README.
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).resolvingSymlinksInPath()
    func read(_ path: String) throws -> Data {
        try CorpusManifest.validateRelativePath(path)
        let resolved = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(base.path + "/") else { throw CorpusValidationError.invalid("Manifest symlink escapes working directory") }
        return try Data(contentsOf: resolved)
    }
    let manifest = try CorpusManifest.decode(Data(contentsOf: URL(fileURLWithPath: manifestPath)))
    let all = try manifest.validate(read: read, digest: { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() })
    let snapshot = try JSONDecoder().decode(RuleSnapshot.self, from: read(manifest.rules.path))
    guard !snapshot.lexicon.isEmpty, !snapshot.mappings.isEmpty else { throw CorpusValidationError.invalid("Empty lexical baseline") }
    let engine = LinguisticEngine(snapshot: snapshot)
    let rows = all.filter { $0.split == split }
    let report = QualityEvaluator.evaluate(rows) { row in
        let word = BufferedWord(text: row.input, events: [], context: ContextToken(pid: 0, bundleID: "synthetic.corpus", focusEpoch: 1, layoutEpoch: 1), layout: row.layout, delimiter: " ")
        switch engine.decide(word: word, preferences: .defaults, excludedWords: []) {
        case .unchanged: return row.input
        case .replace(let correction): return correction.replacement
        }
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var object = try JSONSerialization.jsonObject(with: encoder.encode(report)) as! [String: Any]
    // Explicit nulls make undefined denominators visible in machine-readable reports.
    for key in ["precision", "recall", "falseChangeRate", "layoutRecall", "precisionInterval", "falseChangeInterval", "layoutRecallInterval"] where object[key] == nil { object[key] = NSNull() }
    object["corpusVersion"] = manifest.corpusVersion; object["split"] = split.rawValue
    object["rulesSHA256"] = manifest.rules.sha256; object["modelVersion"] = snapshot.modelVersion
    object["evaluationMode"] = "token-only synthetic replay; physical-input/editor differential unrun"
    object["releaseReady"] = false
    object["corpusTotal"] = all.count
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    let destination = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
    print("\(split.rawValue): \(report.total) cases; TP=\(report.truePositive) FP=\(report.falsePositive) FN=\(report.falseNegative); precision=\(report.precision.map(String.init(describing:)) ?? "undefined") false-change=\(report.falseChangeRate.map(String.init(describing:)) ?? "undefined") layout recall=\(report.layoutRecall.map(String.init(describing:)) ?? "undefined")")
    for failure in report.failures { print("FAIL: \(failure)") }
    return report.passed ? 0 : 1
}
do { exit(try run()) } catch { fputs("CorpusRunner: \(error)\n", stderr); exit(2) }
