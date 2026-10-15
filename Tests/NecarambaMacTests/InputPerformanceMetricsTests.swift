import XCTest
@testable import NecarambaMac

final class InputPerformanceMetricsTests: XCTestCase {
  func testInclusiveBoundariesAndReset() {
    let metrics = InputPerformanceMetrics()
    for boundary in InputPerformanceMetrics.bucketUpperBoundsNanos {
      metrics.record(.classification, durationNanos: boundary)
    }
    metrics.record(.classification, durationNanos: UInt64.max)
    XCTAssertEqual(metrics.snapshotAndReset()[.classification], Array(repeating: 1, count: 10))
    XCTAssertEqual(metrics.snapshotAndReset()[.classification], Array(repeating: 0, count: 10))
  }

  func testMillionSamplesHaveFixedStorage() {
    let metrics = InputPerformanceMetrics()
    for _ in 0..<1_000_000 { metrics.record(.classification, durationNanos: 1_000_000) }
    let snapshot = metrics.snapshotAndReset()
    XCTAssertEqual(snapshot.count, InputPerformanceStage.allCases.count)
    XCTAssertEqual(snapshot.values.reduce(0) { $0 + $1.count }, InputPerformanceStage.allCases.count * 10)
    XCTAssertEqual(snapshot[.classification]?.first, 1_000_000)
  }

  func testCancellationCountsResetIndependently() {
    let metrics = InputPerformanceMetrics()
    metrics.recordCancellation(.staleGeneration)
    metrics.record(.total, durationNanos: 1)
    XCTAssertEqual(metrics.cancellationSnapshotAndReset()[.staleGeneration], 1)
    XCTAssertEqual(metrics.cancellationSnapshotAndReset()[.staleGeneration], 0)
    XCTAssertEqual(metrics.snapshotAndReset()[.total]?.first, 1)
  }

  func testConcurrentWritersDoNotLoseSamples() {
    let metrics = InputPerformanceMetrics()
    DispatchQueue.concurrentPerform(iterations: 10_000) { _ in metrics.record(.posting, durationNanos: 0) }
    XCTAssertEqual(metrics.snapshotAndReset()[.posting]?.first, 10_000)
  }

  func testDiagnosticSessionRequiresExactOptInAndExpires() {
    XCTAssertFalse(InputDiagnosticSession(environment: [:], startedAtNanos: 10).isEnabled(at: 10))
    XCTAssertFalse(InputDiagnosticSession(environment: ["NECARAMBA_PERF_TRACE": "true"], startedAtNanos: 10).isEnabled(at: 10))
    let session = InputDiagnosticSession(environment: ["NECARAMBA_PERF_TRACE": "1"], startedAtNanos: 10)
    XCTAssertTrue(session.isEnabled(at: 10))
    XCTAssertTrue(session.isEnabled(at: 600_000_000_009))
    XCTAssertFalse(session.isEnabled(at: 600_000_000_010))
    XCTAssertFalse(session.isEnabled(at: 9))
  }

  func testOrdinaryStagesAreQuietAndErrorsRemainVisible() {
    XCTAssertFalse(InputDiagnostics.shouldEmit("ax.readValue", tracing: false))
    XCTAssertTrue(InputDiagnostics.shouldEmit("ax.mutation.uncertain", tracing: false))
    XCTAssertTrue(InputDiagnostics.shouldEmit("ax.readValue", tracing: true))
    XCTAssertFalse(InputDiagnostics.shouldEmit("arbitrary private text", tracing: true))
  }
  func testAggregateExportHasOnlyFixedStagesAndCounts() {
    let metrics = InputPerformanceMetrics()
    metrics.record(.posting, durationNanos: 1)
    metrics.recordCancellation(.uncertain)
    let report = metrics.exportRowsAndReset()
    XCTAssertEqual(report.count, InputPerformanceStage.allCases.count + InputPerformanceCancellation.allCases.count)
    XCTAssertTrue(report.contains("timing.posting=1,0,0,0,0,0,0,0,0,0"))
    XCTAssertTrue(report.contains("cancel.uncertain=1"))
    XCTAssertTrue(metrics.exportRowsAndReset().contains("cancel.uncertain=0"))
  }
  func testQuietDiagnosticExitsStillRecordCancellationReasons() {
    let metrics = InputPerformanceMetrics()
    for reason in ["runtime.manual.cancelled_generation", "ax.unsafeContext", "manual.gesture.permissionsDenied", "ax.readback.deadlineExceeded", "ax.mutation.aborted"] {
      InputDiagnostics.event(reason, metrics: metrics)
    }
    InputDiagnostics.event("not a known stage", metrics: metrics)
    let counts = metrics.cancellationSnapshotAndReset()
    for reason: InputPerformanceCancellation in [.staleGeneration, .unsafeContext, .permissionDenied, .deadline, .postingAborted] {
      XCTAssertEqual(counts[reason], 1)
    }
    XCTAssertEqual(counts.values.reduce(0, +), 5)
  }
}
