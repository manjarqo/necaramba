import Foundation
import OSLog

/// Monotonic, process-scoped opt-in. Expiry needs no timer or background wakeup.
struct InputDiagnosticSession {
  private let startedAtNanos: UInt64
  private let durationNanos: UInt64
  init(environment: [String: String], startedAtNanos: UInt64,
       requestedUntil: TimeInterval = 0, wallTime: TimeInterval = Date().timeIntervalSince1970) {
    self.startedAtNanos = startedAtNanos
    let remaining = requestedUntil - wallTime
    let duration: TimeInterval
    if environment["NECARAMBA_PERF_TRACE"] == "1" { duration = 600 }
    else { duration = remaining.isFinite && remaining > 0 ? min(600, remaining) : 0 }
    durationNanos = UInt64(duration * 1_000_000_000)
  }
  func isEnabled(at now: UInt64) -> Bool {
    now >= startedAtNanos && now - startedAtNanos < durationNanos
  }
}

/// Only fixed reviewed stage names are accepted. No keyboard text or AX values.
enum InputDiagnostics {
  private static let logger = Logger(subsystem: "local.necaramba.app", category: "ManualInput")
  private static let session = InputDiagnosticSession(
    environment: ProcessInfo.processInfo.environment,
    startedAtNanos: InputPerformanceMetrics.nowNanos(),
    requestedUntil: UserDefaults.standard.double(forKey: "InputDiagnosticsUntil"))
  private static let errors: Set<String> = [
    "ax.mutation.aborted",
    "ax.mutation.uncertain",
    "tap.lifecycle.disabled_timeout",
    "tap.lifecycle.disabled_user_input",
    "tap.lifecycle.timeout_recovery_stopped",
  ]
  private static let stages: Set<String> = [
    "ax.terminalProxy.matched",
    "ax.terminalProxy.missing",
    "tap.phased.begin",
    "tap.phased.stage",
    "tap.phased.finished",
    "tap.post.aborted",
    "tap.post.contextMismatch",
    "tap.post.reconcileRetry",
    "auto.eligibility.rejected",
    "auto.decision.correct",
    "auto.decision.ambiguous",
    "auto.decision.protectedToken",
    "auto.decision.excludedWord",
    "auto.decision.disabled",
    "auto.decision.unsupportedLayout",
    "auto.decision.layout",
    "auto.decision.typo",
    "auto.decision.doubleCaps",
    "auto.decision.yo",
    "auto.decision.combined",
    "auto.boundary.cancelledGeneration",
    "auto.boundary.contextOrMappingDenied",
    "auto.boundary.delivered",
    "auto.boundary.received",
    "auto.ready",
    "auto.result",
    "ax.auto.boundaryOrSnapshotRejected",
    "ax.auto.emptyProxy",
    "ax.auto.freshOpaqueCapture",
    "ax.auto.opaquePrefixBlocked",
    "ax.auto.readableRangeRejected",
    "ax.auto.readableSuffix",
    "ax.auto.readableSuffixMismatch",
    "ax.compositionDirectLayout",
    "ax.compositionRejected",
    "ax.execute.begin",
    "ax.focusChangedDuringRead",
    "ax.invalidFocus",
    "ax.invalidRangeMetadata",
    "ax.invalidRole",
    "ax.invalidTextMetadata",
    "ax.malformedMarkedRange",
    "ax.malformedSelectedRange",
    "ax.mutation.aborted",
    "ax.mutation.committed",
    "ax.mutation.dispatched",
    "ax.mutation.uncertain",
    "ax.opaque.nonemptyOrSelected",
    "ax.overlay.selectRange",
    "ax.overlay.selectionPrepared",
    "ax.overlay.selectionRejected",
    "ax.overlay.selectionUnproven",
    "ax.readDeadlineExceeded",
    "ax.readFocus",
    "ax.readMarkedRange",
    "ax.readRole",
    "ax.readSelectedRange",
    "ax.readSubrole",
    "ax.readValue",
    "ax.readback.attemptsExhausted",
    "ax.readback.attributeTransportPending",
    "ax.readback.confirmed",
    "ax.readback.contextOrGenerationChanged",
    "ax.readback.deadlineExceeded",
    "ax.readback.focusTransportPending",
    "ax.readback.identityChanged",
    "ax.readback.postedIntermediate",
    "ax.readback.rejectedObservation",
    "ax.readback.scopeOrDeadlineRejected",
    "ax.readback.tornPostedIntermediate",
    "ax.readback.unchanged",
    "ax.readback.unprovenPartialValue",
    "ax.readback.unprovenState",
    "ax.repeat.lineageOrContextRejected",
    "ax.secureOrMalformedSubrole",
    "ax.subroleUnproven",
    "ax.tracked.boundsOrScopeRejected",
    "ax.tracked.execute.begin",
    "ax.tracked.executeMissing",
    "ax.tracked.generationMissingOrChanged",
    "ax.tracked.identityRejected",
    "ax.tracked.nonemptyValue",
    "ax.tracked.physicalProofRejected",
    "ax.tracked.preflightRejected",
    "ax.tracked.rangeZero",
    "ax.tracked.snapshotMissing",
    "ax.unsafeContext",
    "context.application.chrome",
    "context.application.other",
    "context.application.safari",
    "context.application.spark",
    "context.attach.noAXPermission",
    "context.attach.noApplication",
    "context.attach.observerCreateFailed",
    "context.attach.observerNotificationFailed",
    "context.chrome.activation",
    "context.chrome.activationRefresh",
    "context.focus.lost",
    "context.focus.recovered",
    "context.focus.keyboardOwnerResolved",
    "context.focus.editableAncestorCandidate",
    "context.invalidate.attach",
    "context.refresh.afterFocusEpoch",
    "context.refresh.afterLayoutEpoch",
    "context.refresh.beforeFocusEpoch",
    "context.refresh.beforeLayoutEpoch",
    "context.refresh.elementChanged",
    "context.refresh.focusIdentityChanged",
    "context.refresh.focusNotification",
    "context.refresh.secureOrPermissionMissing",
    "context.refresh.slowMilliseconds",
    "context.refresh.systemFocusUnavailable",
    "context.role.application",
    "context.role.combobox",
    "context.role.group",
    "context.role.missing",
    "context.role.other",
    "context.role.list",
    "context.role.row",
    "context.role.menu",
    "context.role.menuitem",
    "context.role.scrollarea",
    "context.role.searchfield",
    "context.role.statictext",
    "context.role.unknown",
    "context.role.layoutarea",
    "context.role.layoutitem",
    "context.role.textinput",
    "context.application.vscodium",
    "context.application.tabby",
    "context.role.textarea",
    "context.role.textfield",
    "context.role.webarea",
    "context.role.window",
    "context.spark.activation",
    "context.systemFocus.overlayOwner",
    "manual.cachedLayoutMatchesCurrent",
    "manual.caretWordUnavailable",
    "manual.contextMissing",
    "manual.currentFocusEpoch",
    "manual.currentLayoutEpoch",
    "manual.gesture.focusEpoch",
    "manual.gesture.layoutEpoch",
    "manual.gesture.permissionsDenied",
    "manual.layoutMissing",
    "manual.mappingCapture.inputChanged",
    "manual.mappingExists",
    "manual.physicalTranslationMissing",
    "manual.rawMatchesPhysical",
    "manual.ready.afterFocusEpoch",
    "manual.ready.afterLayoutEpoch",
    "manual.ready.afterSameBundle",
    "manual.ready.afterSameProcess",
    "manual.ready.beforeFocusEpoch",
    "manual.ready.beforeLayoutEpoch",
    "manual.ready.beforeMatches",
    "manual.ready.contextMismatch",
    "manual.ready.permissions",
    "manual.ready.quarantined",
    "manual.result",
    "manual.selectedProof",
    "manual.selection.result",
    "manual.selectionNonempty",
    "manual.suffix.result",
    "manual.trackedFallback.begin",
    "manual.trackedFallback.result",
    "manual.wordContextMismatch",
    "manual.wordFocusEpoch",
    "manual.wordLayoutEpoch",
    "manual.wordLayoutMismatch",
    "manual.wordMappingMissing",
    "manual.wordMissing",
    "manual.wordSamePID",
    "runtime.manual.cancelled_generation",
    "runtime.manual.delivered",
    "runtime.single_shift.cancelled_generation",
    "runtime.single_shift.delivered",
    "tap.batch.elapsedMicroseconds",
    "tap.batch.postedPairs",
    "tap.batch.stopReason",
    "tap.lifecycle.disabled_timeout",
    "tap.lifecycle.disabled_user_input",
    "tap.lifecycle.reenabled",
    "tap.lifecycle.stopped",
    "tap.lifecycle.timeout_recovery_stopped",
  ]
  static func shouldEmit(_ reason: String, tracing: Bool) -> Bool {
    errors.contains(reason) || (tracing && stages.contains(reason))
  }
  static func event(_ reason: String, detail: Int = 0, metrics: InputPerformanceMetrics = .shared) {
    // Fixed authoritative exit observations, counted even when detailed traces are off.
    switch reason {
    case "auto.boundary.cancelledGeneration", "runtime.manual.cancelled_generation", "runtime.single_shift.cancelled_generation":
      metrics.recordCancellation(.staleGeneration)
    case "ax.unsafeContext", "ax.invalidFocus", "ax.focusChangedDuringRead", "ax.readback.identityChanged", "manual.ready.contextMismatch", "manual.contextMissing":
      metrics.recordCancellation(.unsafeContext)
    case "manual.gesture.permissionsDenied", "context.attach.noAXPermission":
      metrics.recordCancellation(.permissionDenied)
    case "ax.readback.deadlineExceeded", "ax.readDeadlineExceeded", "ax.readback.attemptsExhausted":
      metrics.recordCancellation(.deadline)
    case "ax.mutation.aborted": metrics.recordCancellation(.postingAborted)
    default: break
    }
    guard shouldEmit(reason, tracing: session.isEnabled(at: InputPerformanceMetrics.nowNanos())) else { return }
    logger.notice("stage=\(reason, privacy: .public) code=\(detail, privacy: .public)")
  }
}

/// Explicit lifecycle export, outside the tap. Records fixed aggregate rows only.
public enum InputPerformanceReport {
  public static func flush() {
    guard ProcessInfo.processInfo.environment["NECARAMBA_PERF_TRACE"] == "1" else { return }
    let logger = Logger(subsystem: "local.necaramba.app", category: "Performance")
    for row in InputPerformanceMetrics.shared.exportRowsAndReset() {
      logger.notice("aggregate=\(row, privacy: .public)")
    }
  }
}
