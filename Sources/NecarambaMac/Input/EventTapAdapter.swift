import AppKit
import Carbon
import CoreGraphics
import Foundation
import NecarambaCore

public final class EventTapAdapter {
  public static let ownMarker = Int64.random(in: 1...Int64.max)
  private weak var runtime: InputRuntime?
  private let lock = NSLock()
  // Serializes stop against in-flight callbacks, without holding InputRuntime's lock.
  // Recursive because a tap-disabled callback can stop its own adapter.
  private let callbacks = NSRecursiveLock()
  private var thread: Thread?
  private var loop: CFRunLoop?
  private var tap: CFMachPort?
  private var stopped = false
  private let ready = DispatchSemaphore(value: 0)
  private var installed = false
  public private(set) var canSuppress = false
  private var timeouts: [UInt64] = []
  private let ownership = EditOwnership<CGEvent>()
  private let shortcut = ShortcutSession()
  private var suppressNextVUp = false
  // Confined to the tap run loop, including ownership and gesture deadlines.
  private lazy var deadlineScheduler = InputDeadlineScheduler { deadline, action in
    let now = DispatchTime.now().uptimeNanoseconds
    let delay = deadline > now ? Double(deadline - now) / 1_000_000_000 : 0
    let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in action() }!
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    return { CFRunLoopTimerInvalidate(timer) }
  }
  private func rescheduleDeadline() {
    let deadline = isStopped ? nil : [runtime?.nextDeadlineNanos, ownership.nextDeadlineNanos].compactMap { $0 }.min()
    deadlineScheduler.update(deadline: deadline) { [weak self] in self?.tick() }
  }
  public init(runtime: InputRuntime) { self.runtime = runtime }
  public func start() -> Bool {
    guard CGPreflightListenEventAccess() else { return false }
    lock.lock()
    guard thread == nil else {
      let result = installed
      lock.unlock()
      return result
    }
    canSuppress = CGPreflightPostEventAccess()
    stopped = false
    installed = false
    let worker = Thread { [weak self] in self?.run() }
    worker.name = "Necaramba input"
    thread = worker
    lock.unlock()
    worker.start()
    guard ready.wait(timeout: .now() + 1) == .success else {
      stop()
      return false
    }
    lock.lock()
    let result = installed
    lock.unlock()
    return result
  }
  public var isInstalled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return installed
  }
  public func stop() {
    callbacks.lock()
    lock.lock()
    stopped = true
    installed = false
    let runloop = loop
    let port = tap
    lock.unlock()
    InputDiagnostics.event("tap.lifecycle.stopped")
    // Disable before the caller can create another tap. Teardown/replay stays on
    // the original run loop; no synchronous wait on that run loop or main queue.
    if let port { CGEvent.tapEnable(tap: port, enable: false) }
    callbacks.unlock()
    if let runloop {
      CFRunLoopPerformBlock(runloop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
        if let self { self.release(self.ownership.cancel(), result: .aborted) }
        CFRunLoopStop(runloop)
      }
      CFRunLoopWakeUp(runloop)
    }
  }
  private func run() {
    let mask: [CGEventType] = [
      .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
      .scrollWheel,
    ]
    let bits = mask.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: canSuppress ? .defaultTap : .listenOnly,
        eventsOfInterest: bits,
        callback: { _, type, event, reference in
          guard let reference else { return Unmanaged.passUnretained(event) }
          let owner = Unmanaged<EventTapAdapter>.fromOpaque(reference).takeUnretainedValue()
          return owner.receive(type, event) ? Unmanaged.passUnretained(event) : nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      lock.lock()
      thread = nil
      lock.unlock()
      ready.signal()
      return
    }
    let runloop = CFRunLoopGetCurrent()
    lock.lock()
    tap = port
    loop = runloop
    let halt = stopped
    lock.unlock()
    guard !halt, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
      CFMachPortInvalidate(port)
      lock.lock()
      tap = nil
      loop = nil
      thread = nil
      lock.unlock()
      ready.signal()
      return
    }
    CFRunLoopAddSource(runloop, source, .commonModes)
    callbacks.lock()
    lock.lock()
    if !stopped {
      CGEvent.tapEnable(tap: port, enable: true)
      installed = true
    }
    lock.unlock()
    callbacks.unlock()
    ready.signal()
    CFRunLoopRun()
    deadlineScheduler.update(deadline: nil) {}
    CFRunLoopRemoveSource(runloop, source, .commonModes)
    CFMachPortInvalidate(port)
    lock.lock()
    loop = nil
    tap = nil
    thread = nil
    installed = false
    lock.unlock()
  }
  /// Preparation runs on main; prebuilt key pairs are posted on the tap run loop.
  /// Physical replay holds ownership across two asynchronous, bounded phase delays.
  @MainActor public func replaceAsync(
    _ evidence: SelectionEvidence, with text: String, selected: Bool, lease: ShortcutLease? = nil,
    physicalKeys: [PhysicalLayoutMapping.Entry]? = nil,
    phaseAuthorization: (@MainActor () -> Bool)? = nil,
    preflight: () -> Bool
  ) async -> ApplyResult {
    guard let generation = evidence.inputGeneration,
      evidence.mode == (selected ? .selected : .suffix) else { return .aborted }
    return await postReplacement(context: evidence.context, proofGeneration: generation,
      deleteCount: selected ? 0 : evidence.text.count,
      temporarySpace: ReplacementEventSequence.usesTemporarySpace(bundleID: evidence.context.bundleID, selected: selected),
      text: text, lease: lease, physicalKeys: physicalKeys, phaseAuthorization: phaseAuthorization, preflight: preflight)
  }
  @MainActor public func replacePhysicalAsync(
    _ mutation: PhysicalSuffixMutation, with text: String, lease: ShortcutLease? = nil,
    physicalKeys: [PhysicalLayoutMapping.Entry]? = nil,
    phaseAuthorization: (@MainActor () -> Bool)? = nil,
    preflight: () -> Bool
  ) async -> ApplyResult {
    guard mutation.deleteCount > 0 else { return .aborted }
    return await postReplacement(context: mutation.focus.context, proofGeneration: mutation.inputGeneration,
      deleteCount: mutation.deleteCount,
      temporarySpace: ReplacementEventSequence.usesTemporarySpace(bundleID: mutation.focus.context.bundleID, selected: false),
      text: text, lease: lease, physicalKeys: physicalKeys, phaseAuthorization: phaseAuthorization, preflight: preflight)
  }
  @MainActor private func postReplacement(context: ContextToken, proofGeneration: UInt64,
    deleteCount: Int, temporarySpace: Bool, text: String, lease: ShortcutLease?, physicalKeys: [PhysicalLayoutMapping.Entry]?, phaseAuthorization: (@MainActor () -> Bool)?, preflight: () -> Bool
  ) async -> ApplyResult {
    precondition(Thread.isMainThread)
    // Fixed reason codes only; no text or key data.
    func abort(_ reason: Int) -> ApplyResult {
      InputDiagnostics.event("tap.post.aborted", detail: reason)
      return .aborted
    }
    guard canSuppress, CGPreflightPostEventAccess(), let runtime,
      text.utf16.count <= 1024, deleteCount >= 0, deleteCount <= 128 else { return abort(1) }
    let generation = lease?.generation ?? proofGeneration
    guard proofGeneration == generation, runtime.inputGeneration() == generation,
      lease == nil || lease?.context == context
    else { return abort(2) }
    // Large selections retain the bounded Unicode transport instead of truncating physical replay.
    let usePhysicalReplay = physicalKeys != nil && ReplacementEventSequence.canReplayPhysical(
      keyCount: physicalKeys?.count ?? 0, deleteCount: deleteCount, temporarySpace: temporarySpace)
    let requested = DispatchTime.now().uptimeNanoseconds
    let expectedForegroundPID = !usePhysicalReplay ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier
    guard !Task.isCancelled, !usePhysicalReplay || expectedForegroundPID != nil, preflight(),
      !usePhysicalReplay || NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedForegroundPID else { return abort(3) }
    var batch: [CGEvent] = []
    guard let source = CGEventSource(stateID: .privateState) else { return abort(4) }
    func pair(code: CGKeyCode, text: String? = nil, modifiers: Set<Modifier> = []) -> Bool {
      guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
      else { return false }
      for event in [down, up] {
        event.flags = modifiers.contains(.shift) ? .maskShift : []
        if modifiers.contains(.capsLock) { event.flags.insert(.maskAlphaShift) }
        event.setIntegerValueField(.eventSourceUserData, value: Self.ownMarker)
        if let text {
          let units = Array(text.utf16)
          units.withUnsafeBufferPointer {
            event.keyboardSetUnicodeString(
              stringLength: units.count, unicodeString: $0.baseAddress!)
          }
        }
      }
      batch += [down, up]
      return true
    }
    if temporarySpace { guard pair(code: 49) else { return abort(4) } }
    for _ in 0..<(deleteCount + (temporarySpace ? 1 : 0)) { guard pair(code: 51) else { return abort(4) } }
    let deletionCount = batch.count
    if usePhysicalReplay, let physicalKeys {
      guard physicalKeys.map(\.text).joined() == text, !physicalKeys.isEmpty,
        physicalKeys.allSatisfy({ $0.modifiers.isSubset(of: [.shift, .capsLock]) }) else { return abort(5) }
      for key in physicalKeys {
        guard pair(code: key.keyCode, modifiers: key.modifiers) else { return abort(4) }
      }
    } else {
      var chunk = ""
      for scalar in text.unicodeScalars {
        let next = String(scalar)
        if chunk.utf16.count + next.utf16.count > 16 {
          guard pair(code: 0, text: chunk) else { return abort(4) }
          chunk = ""
        }
        chunk += next
      }
      if !chunk.isEmpty { guard pair(code: 0, text: chunk) else { return abort(4) } }
    }
    guard batch.count <= 512, !batch.isEmpty else { return abort(6) }
    guard let runloop = activeRunLoop() else { return abort(6) }
    let cancellation = PostingCancellation()
    return await withTaskCancellationHandler(operation: {
    await withCheckedContinuation { continuation in
    var finished = false
    var timeout: DispatchWorkItem?

    let finish: (ApplyResult) -> Void = { result in
      guard !finished else { return }
      finished = true
      timeout?.cancel()
      timeout = nil
      continuation.resume(returning: result)
    }
    timeout = DispatchWorkItem {
      guard !finished else { return }
      let result = cancellation.cancelForTimeout()
      runtime.invalidateContext(reason: .unknownInput)
      finish(result)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: timeout!)
    // Our own layout switch posts a TIS notification whose focus reconciliation hides
    // cached safety. Retry only that transient state, within the same admission deadline;
    // the token published afterwards must still equal the proven context.
    var admitAndPost: (() -> Void)?
    admitAndPost = { [weak self] in
      guard let self else { admitAndPost = nil; DispatchQueue.main.async { finish(.aborted) }; return }
      self.callbacks.lock()
      defer { self.callbacks.unlock() }
      let cached = runtime.cachedInputContext()?.0
      let decision = Self.admission(cancelled: cancellation.isCancelled || self.isStopped,
        elapsedNanos: DispatchTime.now().uptimeNanoseconds - requested,
        secureInput: IsSecureEventInputEnabled(), cached: cached, expected: context,
        reconciling: cached == nil && runtime.contextReconciling())
      var rejection: Int?
      switch decision {
      case .retry:
        InputDiagnostics.event("tap.post.reconcileRetry")
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.002, 0, 0, 0) { _ in
          admitAndPost?()
        }!
        CFRunLoopAddTimer(runloop, timer, .commonModes)
        return
      case .reject(let code):
        rejection = code
        if code == 10 {
          // Bitmask of the differing fields only: 1 none, 2 pid, 4 bundle, 8 focus, 16 layout.
          var mismatch = cached == nil ? 1 : 0
          if let cached {
            if cached.pid != context.pid { mismatch |= 2 }
            if cached.bundleID != context.bundleID { mismatch |= 4 }
            if cached.focusEpoch != context.focusEpoch { mismatch |= 8 }
            if cached.layoutEpoch != context.layoutEpoch { mismatch |= 16 }
          }
          InputDiagnostics.event("tap.post.contextMismatch", detail: mismatch)
        }
      case .admit:
        if !self.admit(lease, generation: generation, context: context,
          now: DispatchTime.now().uptimeNanoseconds) { rejection = 11 }
      }
      admitAndPost = nil
      if let rejection {
        InputDiagnostics.event("tap.post.aborted", detail: rejection)
        DispatchQueue.main.async { finish(.aborted) }; return
      }
      cancellation.markAdmitted()
      let ownershipRevision = self.ownership.revision
      var phaseApproved = true
      let authorized = {
        phaseApproved && !cancellation.isCancelled && !self.isStopped &&
        self.ownership.revision == ownershipRevision && self.ownership.isActive && !self.ownership.expired(at: DispatchTime.now().uptimeNanoseconds) &&
        runtime.inputGeneration() == generation && runtime.cachedInputContext()?.0 == context &&
        !IsSecureEventInputEnabled()
      }
      let post: ([CGEvent]) -> ApplyResult = { events in
        let report = KeyBatchPosting.postGuardedPairs(
          events, now: { DispatchTime.now().uptimeNanoseconds },
          ownershipValid: { self.ownership.revision == ownershipRevision && self.ownership.isActive && !self.ownership.expired(at: $0) },
          generationValid: { !cancellation.isCancelled && !self.isStopped && runtime.inputGeneration() == generation },
          contextValid: { runtime.cachedInputContext()?.0 == context },
          secureInput: { IsSecureEventInputEnabled() },
          post: { event in
            if usePhysicalReplay { event.post(tap: .cgSessionEventTap) }
            else { event.postToPid(context.pid) }
          })
        InputDiagnostics.event("tap.batch.stopReason", detail: report.reason.rawValue)
        InputDiagnostics.event("tap.batch.postedPairs", detail: report.postedPairs)
        return report.result
      }
      let complete: (ApplyResult) -> Void = { result in
        if self.ownership.revision == ownershipRevision { self.release(self.ownership.cancel(), result: result) }
        InputDiagnostics.event("tap.phased.finished", detail: result == .committed ? 1 : (result == .uncertain ? 2 : 0))
        DispatchQueue.main.async {
          let finalResult: ApplyResult
          if result == .committed, usePhysicalReplay,
            (phaseAuthorization?() == false || NSWorkspace.shared.frontmostApplication?.processIdentifier != expectedForegroundPID) {
            finalResult = .uncertain
          } else { finalResult = result }
          finish(finalResult)
        }
      }
      if usePhysicalReplay {
        InputDiagnostics.event("tap.phased.begin")
        var phase = 0
        PhasedKeyPosting.run(deletion: Array(batch.prefix(deletionCount)), insertion: Array(batch.dropFirst(deletionCount)),
          schedule: { delay, action in
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in
              // TIS and foreground APIs stay on main. Never synchronously wait from the tap.
              DispatchQueue.main.async {
                let approved = phaseAuthorization?() != false &&
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedForegroundPID
                CFRunLoopPerformBlock(runloop, CFRunLoopMode.commonModes.rawValue) {
                  self.callbacks.lock()
                  defer { self.callbacks.unlock() }
                  phaseApproved = approved
                  InputDiagnostics.event("tap.phased.stage", detail: phase)
                  phase += 1
                  action()
                }
                CFRunLoopWakeUp(runloop)
              }
            }!
            CFRunLoopAddTimer(runloop, timer, .commonModes)
          }, authorized: authorized, post: post, finish: complete)
        self.rescheduleDeadline()
      } else {
        let outcome = self.ownership.commit(expectedGeneration: generation,
          currentGeneration: runtime.inputGeneration, now: DispatchTime.now().uptimeNanoseconds) { post(batch) }
        self.release(outcome.replay, result: outcome.result)
        DispatchQueue.main.async { finish(outcome.result) }
      }
    }
    CFRunLoopPerformBlock(runloop, CFRunLoopMode.commonModes.rawValue) { admitAndPost?() }
    CFRunLoopWakeUp(runloop)
    // No remote AX request or main-thread callback occurs inside the destructive block.
    }
    }, onCancel: { cancellation.cancel() })
  }

  private func activeRunLoop() -> CFRunLoop? {
    lock.lock(); defer { lock.unlock() }
    return installed && !stopped ? loop : nil
  }
  private var isStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
  func tick() {
    callbacks.lock()
    defer { rescheduleDeadline(); callbacks.unlock() }
    guard !isStopped else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    if ownership.expired(at: now) {
      let events = ownership.cancel()
      release(events, result: .aborted)
      runtime?.invalidateContext(reason: .unknownInput)
    }
    runtime?.advance(to: now)
  }
  /// Posts Command-C or Command-V as our own events. Main thread only; the proven
  /// context, input generation and secure-input state are checked immediately before.
  @MainActor public func postCommandShortcut(_ shortcut: CommandShortcut, context: ContextToken,
                                             generation: UInt64) -> Bool {
    precondition(Thread.isMainThread)
    guard canSuppress, CGPreflightPostEventAccess(), let runtime, !IsSecureEventInputEnabled(),
      runtime.inputGeneration() == generation, runtime.cachedInputContext()?.0 == context,
      let source = CGEventSource(stateID: .privateState) else { return false }
    let code: CGKeyCode = shortcut == .copy ? 8 : 9
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
    for event in [down, up] {
      event.flags = .maskCommand
      event.setIntegerValueField(.eventSourceUserData, value: Self.ownMarker)
    }
    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
    return true
  }
  enum PostingAdmission: Equatable { case admit, retry, reject(Int) }
  /// Fixed codes: 7 cancelled/stopped, 8 deadline, 9 secure input, 10 context mismatch.
  /// Only a missing token during authoritative reconciliation is transient.
  static func admission(cancelled: Bool, elapsedNanos: UInt64, secureInput: Bool,
                        cached: ContextToken?, expected: ContextToken, reconciling: Bool) -> PostingAdmission {
    if cancelled { return .reject(7) }
    if elapsedNanos >= 100_000_000 { return .reject(8) }
    if secureInput { return .reject(9) }
    if cached == expected { return .admit }
    if cached == nil && reconciling { return .retry }
    return .reject(10)
  }
  private func admit(
    _ lease: ShortcutLease?, generation: UInt64, context: ContextToken, now: UInt64
  ) -> Bool {
    if let lease {
      return ownership.isActive
        && shortcut.admits(lease, generation: generation, context: context, now: now)
    }
    guard shortcut.active == nil, !ownership.isActive else { return false }
    return ownership.begin(now: now)
  }
  public func finishShortcut(_ lease: ShortcutLease, _ result: ApplyResult) {
    lock.lock()
    let runloop = loop
    lock.unlock()
    guard let runloop else { return }
    CFRunLoopPerformBlock(runloop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
      guard let self, self.shortcut.active == lease else { return }
      self.release(self.ownership.cancel(), result: result)
    }
    CFRunLoopWakeUp(runloop)
  }
  private func release(_ events: [CGEvent], result: ApplyResult) {
    defer { rescheduleDeadline() }
    guard let original = shortcut.active else {
      replay(events)
      return
    }
    shortcut.cancel()
    if result == .aborted, runtime?.cachedInputContext()?.0 == original.context {
      replay(events)
      return
    }
    let filtered = ShortcutSession.consumeTrigger(events)
    suppressNextVUp = filtered.awaitingRelease
    replay(filtered.events)
  }
  /// A held key release cannot insert text; anything else is new physical input.
  static func replayInvalidatesInput(_ events: [CGEvent]) -> Bool {
    events.contains { $0.type != .keyUp }
  }
  private func replay(_ events: [CGEvent]) {
    if Self.replayInvalidatesInput(events) { runtime?.replayedPhysicalInput() }
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: Self.ownMarker)
      event.post(tap: .cgSessionEventTap)
    }
  }
  func receive(_ type: CGEventType, _ event: CGEvent) -> Bool {
    let callbackStart = InputPerformanceMetrics.nowNanos()
    defer { InputPerformanceMetrics.shared.record(.tapCallback, durationNanos: InputPerformanceMetrics.nowNanos() - callbackStart) }
    callbacks.lock()
    defer { rescheduleDeadline(); callbacks.unlock() }
    guard !isStopped else { return true }
    guard let runtime else { return true }
    if type == .tapDisabledByUserInput {
      InputDiagnostics.event("tap.lifecycle.disabled_user_input")
      runtime.invalidateContext(reason: .permissionRevoked)
      stop()
      return true
    }
    if type == .tapDisabledByTimeout {
      InputDiagnostics.event("tap.lifecycle.disabled_timeout")
      let now = DispatchTime.now().uptimeNanoseconds
      timeouts = timeouts.filter { now - $0 < 60_000_000_000 }
      runtime.invalidateContext(reason: .unknownInput)
      if timeouts.count < 3, let tap {
        timeouts.append(now)
        CGEvent.tapEnable(tap: tap, enable: true)
        InputDiagnostics.event("tap.lifecycle.reenabled", detail: timeouts.count)
      } else {
        InputDiagnostics.event("tap.lifecycle.timeout_recovery_stopped", detail: timeouts.count)
        stop()
      }
      return true
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.ownMarker { return true }
    switch ownership.intercept(event.copy() ?? event, now: DispatchTime.now().uptimeNanoseconds) {
    case .held: return false
    case .replay(let events):
      release(events, result: .aborted)
      runtime.invalidateContext(reason: .unknownInput)
      return false
    case .pass: break
    }
    if type == .keyUp, event.getIntegerValueField(.keyboardEventKeycode) == 9, suppressNextVUp {
      suppressNextVUp = false
      return false
    }
    guard [.keyDown, .keyUp, .flagsChanged].contains(type) else {
      runtime.invalidateContext(reason: .mouseNavigation)
      return true
    }
    guard let (context, layout) = runtime.cachedInputContext() else {
      if type == .keyDown {
        runtime.missedInput(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
          command: event.flags.contains(.maskCommand))
      }
      else { runtime.invalidateContext(reason: .unknownInput) }
      return true
    }
    let marker = event.getIntegerValueField(.eventSourceUserData)
    let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
    let origin: EventOrigin =
      marker == Self.ownMarker ? .ours : (sourcePID == 0 ? .physical : .foreignSynthetic)
    var modifiers: Set<Modifier> = []
    for (flag, modifier): (CGEventFlags, Modifier) in [
      (.maskShift, .shift), (.maskAlternate, .option), (.maskCommand, .command),
      (.maskControl, .control), (.maskAlphaShift, .capsLock), (.maskSecondaryFn, .function),
    ] { if event.flags.contains(flag) { modifiers.insert(modifier) } }
    var chars = [UniChar](repeating: 0, count: 8)
    var count = 0
    event.keyboardGetUnicodeString(
      maxStringLength: 8, actualStringLength: &count, unicodeString: &chars)
    let text = count > 0 && count <= 8 ? String(utf16CodeUnits: chars, count: count) : nil
    let disposition = runtime.accept(
      InputEvent(
        kind: type == .keyDown ? .down : (type == .keyUp ? .up : .flagsChanged),
        keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers,
        timestampNanos: DispatchTime.now().uptimeNanoseconds, layout: layout, context: context,
        origin: origin, text: text,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0))
    if case .suppressed(let lease) = disposition,
      ownership.begin(now: DispatchTime.now().uptimeNanoseconds), shortcut.begin(lease)
    {
      _ = ownership.intercept(event.copy() ?? event, now: DispatchTime.now().uptimeNanoseconds)
      return false
    }
    return true
  }
}

/// Cancellation is sampled between pairs on the tap; it never authorizes a retry.
private final class PostingCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var admitted = false
  func markAdmitted() { lock.lock(); defer { lock.unlock() }; admitted = true }
  func cancelForTimeout() -> ApplyResult {
    lock.lock(); defer { lock.unlock() }
    cancelled = true
    // Once admitted, a pair may already be in flight. Never advertise a safe retry.
    return admitted ? .uncertain : .aborted
  }
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}
