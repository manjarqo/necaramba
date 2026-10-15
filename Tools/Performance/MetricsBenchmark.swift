import Foundation

@main struct MetricsBenchmark {
  static func main() throws {
    var samples: [Double] = []
    for _ in 0..<6 {
      let metrics = InputPerformanceMetrics()
      let began = DispatchTime.now().uptimeNanoseconds
      for n in 0..<1_000_000 { metrics.record(.tapCallback, durationNanos: UInt64(n)) }
      let elapsed = DispatchTime.now().uptimeNanoseconds - began
      let count = metrics.snapshotAndReset()[.tapCallback, default: []].reduce(0, +)
      precondition(count == 1_000_000)
      samples.append(Double(elapsed) / 1_000_000)
    }
    let result: [String: Any] = ["scope": "Single-thread optimized aggregate record cost; excludes clock calls and contention",
                               "nanosecondsPerRecord": Array(samples.dropFirst()), "samplesPerRun": 1_000_000]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
  }
}
