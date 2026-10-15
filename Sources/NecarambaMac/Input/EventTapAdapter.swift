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
  /// Preparation runs on main. The only destructive work is a prebuilt event batch on the tap run loop.
  @MainActor public func replaceAsync(
    _ evidence: SelectionEvidence, with text: String, selected: Bool, lease: ShortcutLease? = nil,
    preflight: () -> Bool
  ) async -> ApplyResult {
    precondition(Thread.isMainThread)
    guard canSuppress, CGPreflightPostEventAccess(), let runtime,
      let proofGeneration = evidence.inputGeneration,
      evidence.mode == (selected ? .selected : .suffix), text.utf16.count <= 1024,
      evidence.text.count <= 128
    else { return .aborted }
    let generation = lease?.generation ?? proofGeneration
    guard proofGeneration == generation, runtime.inputGeneration() == generation,
      lease == nil || lease?.context == evidence.context
    else { return .aborted }
    let requested = DispatchTime.now().uptimeNanoseconds
    guard !Task.isCancelled, preflight() else { return .aborted }
    var batch: [CGEvent] = []
    func pair(code: CGKeyCode, text: String? = nil) -> Bool {
      guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
      else { return false }
      for event in [down, up] {
        event.flags = []
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
    if !selected { for _ in evidence.text { guard pair(code: 51) else { return .aborted } } }
    var chunk = ""
    for scalar in text.unicodeScalars {
      let next = String(scalar)
      if chunk.utf16.count + next.utf16.count > 16 {
        guard pair(code: 0, text: chunk) else { return .aborted }
        chunk = ""
      }
      chunk += next
    }
    if !chunk.isEmpty { guard pair(code: 0, text: chunk) else { return .aborted } }
    guard batch.count <= 512, !batch.isEmpty else { return .aborted }
    guard let runloop = activeRunLoop() else { return .aborted }
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
      runtime.invalidateContext(reason: .unknownInput)
      finish(.uncertain)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: timeout!)
    CFRunLoopPerformBlock(runloop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
      var result: ApplyResult = .aborted
      defer { let outcome = result; DispatchQueue.main.async { finish(outcome) } }
      guard let self else { return }
      self.callbacks.lock()
      defer { self.callbacks.unlock() }
      guard !cancellation.isCancelled, !self.isStopped, DispatchTime.now().uptimeNanoseconds - requested < 100_000_000,
        !IsSecureEventInputEnabled(), runtime.cachedInputContext()?.0 == evidence.context,
        self.admit(
          lease, generation: generation, context: evidence.context,
          now: DispatchTime.now().uptimeNanoseconds)
      else { return }
      var batchReport: KeyBatchPosting.Report?
      let outcome = self.ownership.commit(
        expectedGeneration: generation, currentGeneration: runtime.inputGeneration,
        now: DispatchTime.now().uptimeNanoseconds
      ) {
        let report = KeyBatchPosting.postGuardedPairs(
          batch, now: { DispatchTime.now().uptimeNanoseconds },
          ownershipValid: { self.ownership.isActive && !self.ownership.expired(at: $0) },
          generationValid: { !cancellation.isCancelled && runtime.inputGeneration() == generation },
          contextValid: { runtime.cachedInputContext()?.0 == evidence.context },
          secureInput: { IsSecureEventInputEnabled() },
          post: { $0.postToPid(evidence.context.pid) })
        batchReport = report
        return report.result
        // Delivery/readback is not proven by CGEvent.post. Qualified host evidence is still required.
      }
      result = outcome.result
      // Batch metadata only, after ownership has ended; never log text or keys.
      if let report = batchReport {
        InputDiagnostics.event("tap.batch.stopReason", detail: report.reason.rawValue)
        InputDiagnostics.event("tap.batch.postedPairs", detail: report.postedPairs)
        InputDiagnostics.event("tap.batch.elapsedMicroseconds",
          detail: Int(clamping: report.elapsedNanos / 1_000))
      }
      self.release(outcome.replay, result: result)
    }
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
  private func replay(_ events: [CGEvent]) {
    if !events.isEmpty { runtime?.replayedPhysicalInput() }
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
      runtime.invalidateContext(reason: .unknownInput)
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
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}
