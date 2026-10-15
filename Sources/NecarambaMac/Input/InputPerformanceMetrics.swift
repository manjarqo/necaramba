import Foundation

/// Only aggregate timing leaves the input path. No per-event samples are retained.
enum InputPerformanceStage: Int, CaseIterable {
  case commandQueue, classification, preflight, posting, verification, total
  case gestureRecognition, contextRefresh, tapCallback
}

enum InputPerformanceCancellation: Int, CaseIterable {
  case staleGeneration, unsafeContext, permissionDenied, deadline, postingAborted, uncertain, captureDuringReconcile
}

final class InputPerformanceMetrics {
  static let shared = InputPerformanceMetrics()
  static let bucketUpperBoundsNanos: [UInt64] = [1, 2, 5, 10, 20, 50, 100, 200, 500].map { $0 * 1_000_000 }
  private let lock = NSLock()
  private var buckets = Array(repeating: UInt64(0), count: InputPerformanceStage.allCases.count * 10)
  private var cancellations = Array(repeating: UInt64(0), count: InputPerformanceCancellation.allCases.count)

  static func nowNanos() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

  func record(_ stage: InputPerformanceStage, durationNanos: UInt64) {
    let index = Self.bucketUpperBoundsNanos.firstIndex { durationNanos <= $0 } ?? 9
    lock.lock()
    if buckets[stage.rawValue * 10 + index] < .max { buckets[stage.rawValue * 10 + index] += 1 }
    lock.unlock()
  }

  func recordCancellation(_ reason: InputPerformanceCancellation) {
    lock.lock()
    if cancellations[reason.rawValue] < .max { cancellations[reason.rawValue] += 1 }
    lock.unlock()
  }

  /// Allocate replacement/export structures outside the short writer lock.
  func snapshotAndReset() -> [InputPerformanceStage: [UInt64]] {
    var snapshot = Array(repeating: UInt64(0), count: InputPerformanceStage.allCases.count * 10)
    lock.lock()
    swap(&snapshot, &buckets)
    lock.unlock()
    return Dictionary(uniqueKeysWithValues: InputPerformanceStage.allCases.map {
      ($0, Array(snapshot[($0.rawValue * 10)..<($0.rawValue * 10 + 10)]))
    })
  }

  func cancellationSnapshotAndReset() -> [InputPerformanceCancellation: UInt64] {
    var snapshot = Array(repeating: UInt64(0), count: InputPerformanceCancellation.allCases.count)
    lock.lock()
    swap(&snapshot, &cancellations)
    lock.unlock()
    return Dictionary(uniqueKeysWithValues: InputPerformanceCancellation.allCases.map { ($0, snapshot[$0.rawValue]) })
  }

  func exportRowsAndReset() -> [String] {
    let timings = snapshotAndReset()
    let reasons = cancellationSnapshotAndReset()
    return InputPerformanceStage.allCases.map {
      "timing.\($0)=\(timings[$0, default: []].map(String.init).joined(separator: ","))"
    } + InputPerformanceCancellation.allCases.map { "cancel.\($0)=\(reasons[$0, default: 0])" }
  }
}
