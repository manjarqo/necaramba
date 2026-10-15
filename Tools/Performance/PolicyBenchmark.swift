import Foundation

@main struct PolicyBenchmark {
  static func main() throws {
    let snapshot = RuleSnapshot(modelVersion: 1,
      lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)],
      mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"),
        pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])])
    let engine = LinguisticEngine(snapshot: snapshot)
    let word = BufferedWord(text: "ghbdtn", events: [],
      context: .init(pid: 1, bundleID: "benchmark.fixture", focusEpoch: 1, layoutEpoch: 1),
      layout: .init(rawValue: "US"), delimiter: " ")
    var rows: [[String: Any]] = []
    var checksum = 0
    for size in [0, 100, 1000] {
      let exclusions = Set((0..<size).map { "Excluded\($0)" })
      let prepared = PreparedWordPolicy(excluded: exclusions, protected: [])
      let expected = engine.decide(word: word, preferences: .defaults, excludedWords: exclusions)
      precondition(expected == engine.decide(word: word, preferences: .defaults, wordPolicy: prepared))
      for run in 0..<6 {
        // Alternate order to reduce systematic warmup/order bias.
        for preparedPath in run % 2 == 0 ? [false, true] : [true, false] {
          let start = DispatchTime.now().uptimeNanoseconds
          for _ in 0..<1000 {
            let result = preparedPath
              ? engine.decide(word: word, preferences: .defaults, wordPolicy: prepared)
              : engine.decide(word: word, preferences: .defaults, excludedWords: exclusions)
            precondition(result == expected)
            if case .replace = result { checksum &+= 1 }
          }
          let elapsed = DispatchTime.now().uptimeNanoseconds - start
          if run > 0 { rows.append(["exclusions": size, "prepared": preparedPath,
                                    "run": run, "nanosecondsPerDecision": Double(elapsed) / 1000]) }
        }
      }
    }
    let result: [String: Any] = ["scope": "Synthetic pure fallback engine only; no AX, UI or keyboard latency",
                               "iterationsPerRun": 1000, "checksum": checksum, "rows": rows]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
