import Foundation
import CryptoKit
import NecarambaCore

func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let usage = "Usage: OpenModelRunner --model Resources/OpenModel/open-v1.json --output report.json (run from repository root)"
    guard args.count == 4 else { throw CorpusValidationError.invalid(usage) }
    var options: [String: String] = [:]
    for i in stride(from: 0, to: args.count, by: 2) {
        guard ["--model", "--output"].contains(args[i]), options[args[i]] == nil else { throw CorpusValidationError.invalid(usage) }
        options[args[i]] = args[i + 1]
    }
    guard let modelPath = options["--model"], let output = options["--output"] else { throw CorpusValidationError.invalid(usage) }
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).resolvingSymlinksInPath()
    func read(_ path: String) throws -> Data {
        try CorpusManifest.validateRelativePath(path)
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else { throw CorpusValidationError.invalid("Manifest path escapes repository") }
        return try Data(contentsOf: url)
    }
    let manifest = try CorpusManifest.decode(read("Corpora/manifest.json"))
    // Validate frozen assets including split separation; only calibration is scored.
    let corpus = try manifest.validate(read: read, digest: digest)
    let baseline = try JSONDecoder().decode(RuleSnapshot.self, from: read(manifest.rules.path))
    let modelData = try Data(contentsOf: URL(fileURLWithPath: modelPath))
    let model = try OpenLexicalModel(data: modelData)
    let snapshot = model.snapshot(replacingLexiconIn: baseline)
    let context = ContextToken(pid: 0, bundleID: "synthetic.open-model", focusEpoch: 1, layoutEpoch: 1)
    func predict(_ text: String, layout: LayoutID, engine: LinguisticEngine, events: [InputEvent] = []) -> String {
        let word = BufferedWord(text: text, events: events, context: context, layout: layout, delimiter: " ")
        switch engine.decide(word: word, preferences: .defaults, excludedWords: []) {
        case .unchanged: return text
        case .replace(let correction): return correction.replacement
        }
    }
    let rows = corpus.filter { $0.split == .calibration }
    func evaluate(_ rules: RuleSnapshot) throws -> Any {
        let engine = LinguisticEngine(snapshot: rules)
        let report = QualityEvaluator.evaluate(rows) { predict($0.input, layout: $0.layout, engine: engine) }
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
    }
    // Deterministic fixture codes exercise physical-provenance branches; they are
    // intentionally not represented as macOS hardware layout capture.
    let alphabet = Array(Set(snapshot.mappings.flatMap { Array($0.pairs.keys) })).sorted()
    let codes = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt16($0.offset)) })
    let physical = snapshot.mappings.map { mapping in
        PhysicalLayoutMapping(source: mapping.source, target: mapping.target, entries: mapping.pairs.map {
            .init(keyCode: codes[$0.key]!, modifiers: [], text: $0.value)
        })
    }
    let physicalEngine = LinguisticEngine(snapshot: snapshot, physicalMappings: physical)
    let cases: [(String, String, String, String)] = [
        ("ground-correct", "ground", "US", "ground"), ("ground-wrong", "пкщгтв", "RU", "ground"),
        ("connector-correct", "connector", "US", "connector"), ("connector-wrong", "сщттусещк", "RU", "connector"),
        ("also-correct", "тоже", "RU", "тоже"), ("also-wrong", "nj;t", "US", "тоже"),
        ("switched-correct", "переключилось", "RU", "переключилось"), ("switched-wrong", "gthtrk.xbkjcm", "US", "переключилось"),
        ("periodically-correct", "периодически", "RU", "периодически"), ("periodically-wrong", "gthbjlbxtcrb", "US", "периодически"),
        ("version", "1.3.166", "US", "1.3.166"), ("version-ru", "1ю3ю166", "RU", "1ю3ю166"),
        ("url", "https://example.com", "US", "https://example.com"), ("email", "user@example.com", "US", "user@example.com"),
        ("code", "foo(bar)", "US", "foo(bar)"), ("acronym", "API", "US", "API"),
        ("ambiguous-en", "he", "US", "he"), ("ambiguous-ru", "ру", "RU", "ру")
    ]
    let regressions: [[String: Any]] = cases.map { id, input, source, expected in
        let layout = LayoutID(rawValue: source)
        let events = input.enumerated().map { offset, char in
            InputEvent(kind: .down, keyCode: codes[String(char)] ?? UInt16.max, modifiers: [], timestampNanos: UInt64(offset + 1), layout: layout, context: context, origin: .physical, text: String(char), isRepeat: false)
        }
        let actual = predict(input, layout: layout, engine: physicalEngine, events: events)
        return ["id": id, "input": input, "layout": source, "expected": expected, "actual": actual, "passed": actual == expected]
    }
    let report: [String: Any] = [
        "schemaVersion": 1, "modelVersion": model.version, "modelSHA256": digest(modelData),
        "corpusVersion": manifest.corpusVersion, "rulesSHA256": manifest.rules.sha256,
        "split": "calibration", "releaseReady": false,
        "calibrationMode": "frozen synthetic token-only corpus; no holdout scoring or tuning",
        "regressionMode": "independently authored simulated physical events; not hardware or editor tests",
        "physicalDifferentialEvidence": "UNRUN", "manualVersionSwitching": "UNRUN; numeric regressions assert automatic abstention only",
        "calibration": ["baseline": try evaluate(baseline), "open": try evaluate(snapshot)],
        "regressions": regressions,
        "regressionsPassed": regressions.filter { $0["passed"] as? Bool == true }.count
    ]
    let destination = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: destination, options: .atomic)
    print("Wrote calibration and regression evidence to \(output); release qualification remains unrun.")
}
do { try run() } catch { fputs("OpenModelRunner: \(error)\n", stderr); exit(2) }
