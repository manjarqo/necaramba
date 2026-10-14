import Foundation
import NecarambaCore

/// Main-thread scope keeps optional AX composition handling exclusive to explicit manual actions.
private final class ManualActionScope { var active = false }

/// Native composition facade. Invoke its lifecycle and manual actions on the main thread.
public final class NativeInputController: InputRuntimeControl, RuleSnapshotConsumer {
  public let context: ContextMonitor
  public private(set) var runtime: InputRuntime!
  private let layouts: LayoutAccess
  private let permissions: PermissionReading
  private let editContext: ContextRefreshing
  private let selection: SelectionAdapter
  private let selectionAccess: SelectionAccess
  private let replacement: ReplacementCoordinator
  private var preferences: PreferencesSnapshot
  private var rules: RuleSnapshot
  private var engine: LinguisticEngine
  private let layoutCapture: LayoutTableCapturing?
  private var manualTables: CapturedLayoutTables?
  private let engineBuilder: RuleEngineBuilding
  private let compiler = DispatchQueue(label: "Necaramba rules compiler")
  private var quarantined: ContextToken?
  private var preparationLease: ShortcutLease?
  private let corpusQualified: Bool
  private let manualActionScope: ManualActionScope
  private var excluded: Set<String> = []
  private var appOverrides: [String: AppOverride] = [:]
  public var onResult: (ApplyResult) -> Void = { _ in }
  public var onCommitted: (UUID, CounterKind) -> Void = { _, _ in }
  public var onToggleAuto: () -> Void = {}
  public init(
    profiles: CapabilityProfiles = CapabilityProfiles(), layouts: LayoutAccess = TISLayoutAdapter(),
    permissions: PermissionReading = PermissionMonitor(),
    preferences: PreferencesSnapshot = .defaults, snapshot: RuleSnapshot = .init(modelVersion: 0),
    corpusQualified: Bool = false, editingContext: ContextRefreshing? = nil,
    selectionAccess: SelectionAccess? = nil, layoutCapture: LayoutTableCapturing? = nil,
    engineBuilder: RuleEngineBuilding = RuleEngineBuilder()
  ) {
    precondition(Thread.isMainThread)
    let manualScope = ManualActionScope()
    manualActionScope = manualScope
    self.layouts = layouts
    self.layoutCapture = layoutCapture ?? (layouts as? LayoutTableCapturing)
    self.engineBuilder = engineBuilder
    self.permissions = permissions
    self.preferences = preferences
    rules = snapshot
    self.corpusQualified = corpusQualified
    let initial = RuleSnapshot(modelVersion: 0)
    rules = initial
    engine = LinguisticEngine(snapshot: initial)
    let monitor = ContextMonitor(
      layouts: layouts, permissions: permissions,
      qualifies: { profiles.qualifies(bundleID: $0, role: $1) })
    context = monitor
    editContext = editingContext ?? monitor
    let ax = AXSelectionAdapter(
      context: editContext, qualifies: { _, role in ContextMonitor.supportsManualRole(role) },
      allowMissingMarkedTextRange: { manualScope.active })
    self.selectionAccess = selectionAccess ?? ax
    selection = SelectionAdapter(selection: self.selectionAccess)
    replacement = ReplacementCoordinator(
      context: editContext, layouts: layouts, sender: KeySender(selection: self.selectionAccess))
    runtime = InputRuntime(
      context: editingContext as ContextAccess? ?? monitor.state,
      initialLayout: layouts.current() ?? LayoutID(rawValue: "unsupported"),
      preferences: preferences, snapshot: initial, earlyEnabled: corpusQualified, engine: engine,
      command: { [weak self] in self?.execute($0) })
    ax.execute = { [weak self] evidence, text, selected, preflight in
      self?.runtime.replaceByKeys(
        evidence, with: text, selected: selected, lease: self?.preparationLease,
        preflight: preflight)
        ?? .aborted
    }
    ax.inputGeneration = { [weak self] in self?.runtime.inputGeneration() ?? UInt64.max }
    runtime.onInputInvalidation = { [weak self] in self?.replacement.invalidate(.unknownInput) }
    monitor.onLayoutChanged = { [weak self] id in
      guard let self else { return }
      let old = self.runtime.cachedInputContext()?.1
      if let id {
        self.runtime.updateLayout(id)
      } else {
        self.runtime.invalidateContext(reason: .layoutChanged)
      }
      if old != id { self.replacement.invalidate(.layoutChanged) }
    }
    if snapshot.modelVersion != 0 || !snapshot.lexicon.isEmpty || !snapshot.mappings.isEmpty {
      install(snapshot)
    }
  }
  @discardableResult public func start() -> Bool {
    precondition(Thread.isMainThread)
    context.start()
    return runtime.start()
  }
  public func stop() {
    precondition(Thread.isMainThread)
    runtime.stop()
    context.stop()
    replacement.invalidate(.unknownInput)
  }
  public func updatePreferences(_ snapshot: PreferencesSnapshot) {
    preferences = snapshot
    runtime.updatePreferences(snapshot)
  }
  public func install(_ snapshot: RuleSnapshot) { install(snapshot, onInstalled: { _ in }) }
  public func install(_ snapshot: RuleSnapshot, onInstalled: @escaping (UInt64) -> Void) {
    let capture = { [weak self] in
      guard let self else { return }
      let tables = self.layoutCapture?.captureTables()
      self.manualTables = tables
      self.compiler.async { [weak self] in
        guard let self else { return }
        let actual = tables?.resolve(snapshot) ?? snapshot
        let prepared = self.engineBuilder.build(
          snapshot: actual, physicalMappings: tables?.physicalMappings(for: actual) ?? [])
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.rules = actual
          self.engine = prepared
          self.runtime.install(actual, engine: prepared)
          onInstalled(actual.modelVersion)
        }
      }
    }
    if Thread.isMainThread { capture() } else { DispatchQueue.main.async(execute: capture) }
  }
  public func updateWordPolicies(_ words: Set<String>) {
    excluded = words
    runtime.invalidateContext(reason: .unknownInput)
  }
  public func updateAppPolicies(_ policies: [String: AppOverride]) {
    appOverrides = policies
    runtime.invalidateContext(reason: .unknownInput)
  }
  public func invalidateContext(reason: InvalidationReason) {
    runtime.invalidateContext(reason: reason)
    context.state.invalidate(reason)
    replacement.invalidate(reason)
  }
  private func ready(_ token: ContextToken, diagnose: Bool = false) -> Bool {
    guard quarantined != token else {
      runtime.discardManualCandidate()
      if diagnose { InputDiagnostics.event("manual.ready.quarantined") }
      return false
    }
    let p = permissions.current()
    guard p.listen, p.post, p.ax, !p.secureInput else {
      runtime.discardManualCandidate()
      if diagnose {
        InputDiagnostics.event("manual.ready.permissions", detail:
          (p.listen ? 1 : 0) | (p.post ? 2 : 0) | (p.ax ? 4 : 0) | (p.secureInput ? 8 : 0))
      }
      return false
    }
    let before = editContext.current()
    let after = editContext.refresh()
    guard after == token else {
      runtime.discardManualCandidate()
      if diagnose {
        InputDiagnostics.event("manual.ready.contextMismatch")
        InputDiagnostics.event("manual.ready.beforeMatches", detail: before == token ? 1 : 0)
        InputDiagnostics.event("manual.ready.beforeFocusEpoch", detail: before.map { Int(clamping: $0.focusEpoch) } ?? -1)
        InputDiagnostics.event("manual.ready.beforeLayoutEpoch", detail: before.map { Int(clamping: $0.layoutEpoch) } ?? -1)
        InputDiagnostics.event("manual.ready.afterFocusEpoch", detail: after.map { Int(clamping: $0.focusEpoch) } ?? -1)
        InputDiagnostics.event("manual.ready.afterLayoutEpoch", detail: after.map { Int(clamping: $0.layoutEpoch) } ?? -1)
        InputDiagnostics.event("manual.ready.afterSameProcess", detail: after?.pid == token.pid ? 1 : 0)
        InputDiagnostics.event("manual.ready.afterSameBundle", detail: after?.bundleID == token.bundleID ? 1 : 0)
      }
      return false
    }
    return true
  }
  private func diagnoseResult(_ result: ApplyResult, event: String) {
    let code: Int
    switch result {
    case .aborted: code = 0
    case .committed: code = 1
    case .uncertain: code = 2
    case .dispatched: code = 3
    }
    InputDiagnostics.event(event, detail: code)
  }
  private func execute(_ command: RuntimeCommand) {
    precondition(Thread.isMainThread)
    switch command {
    case .gesture(let action, let token):
      if case .manualCorrection = action {
        InputDiagnostics.event("manual.gesture.focusEpoch", detail: Int(clamping: token.focusEpoch))
        InputDiagnostics.event("manual.gesture.layoutEpoch", detail: Int(clamping: token.layoutEpoch))
      }
      guard permissions.current().listen, !permissions.current().secureInput else {
        if case .manualCorrection = action { InputDiagnostics.event("manual.gesture.permissionsDenied") }
        return
      }
      switch action {
      case .toggleAuto: onToggleAuto()
      case .manualCorrection:
        guard ready(token, diagnose: true) else { return }
        let result = manualCorrection()
        diagnoseResult(result, event: "manual.result")
        report(result, token: token)
      case .switchLayout:
        guard let current = layouts.current(),
          let next = layouts.supported().first(where: { $0 != current })
        else { return }
        if VerifiedLayoutSwitcher(access: layouts).select(next) {
          runtime.updateLayout(next)
          _ = editContext.refresh()
          replacement.invalidate(.layoutChanged)
        }
      }
    case .boundary(let word, let snapshot, let prefs):
      guard snapshot.modelVersion == rules.modelVersion else { return }
      guard corpusQualified, ready(word.context), context.isAutomaticEligible(word.context),
        appOverrides[word.context.bundleID] != .deny,
        prefs.autoEnabled
      else { return }
      if case .replace(let correction) = engine.decide(
        word: word, preferences: prefs, excludedWords: excluded)
      {
        let plan = EditPlan(
          expected: word.context, original: correction.original,
          replacement: correction.replacement, sourceLayout: correction.sourceLayout,
          targetLayout: correction.targetLayout, delimiter: word.delimiter)
        let result = replacement.apply(plan)
        if result == .committed {
          let kind: CounterKind
          switch correction.kind {
          case .layout, .combined: kind = .layout
          case .typo: kind = .typo
          case .doubleCaps: kind = .doubleCaps
          case .yo: kind = .yo
          }
          onCommitted(plan.id, kind)
        }
        report(result, token: word.context)
        if let current = layouts.current() { runtime.updateLayout(current) }
      }
    case .plainPaste(let lease):
      preparationLease = lease
      let result = plainPaste(in: lease.context, clipboard: SystemClipboard())
      preparationLease = nil
      runtime.finishShortcut(lease, result)
      report(result, token: lease.context)
    }
  }
  private func quarantine(_ result: ApplyResult, token: ContextToken) {
    if result == .uncertain {
      quarantined = token
      runtime.invalidateContext(reason: .unknownInput)
      replacement.invalidate(.unknownInput)
      context.state.invalidate(.unknownInput)
    }
  }
  private func report(_ result: ApplyResult, token: ContextToken) {
    quarantine(result, token: token)
    onResult(result)
  }
  private func manualMapping(from source: LayoutID) -> LayoutMapping? {
    guard let capture = layoutCapture else {
      return rules.mappings.first(where: { $0.source == source })
    }
    guard let target = layouts.supported().first(where: { $0 != source }) else { return nil }
    if let mapping = manualTables?.manualMapping(source: source, target: target) { return mapping }
    let tables = capture.captureTables()
    manualTables = tables
    return tables.manualMapping(source: source, target: target)
  }
  private func retainManualResult(original: BufferedWord, text: String, target: LayoutID,
                                  identity: UUID?, before: ContextToken, generation: UInt64) {
    guard let after = editContext.refresh(), after.pid == before.pid,
      after.bundleID == before.bundleID, after.focusEpoch == before.focusEpoch else {
      runtime.invalidateContext(reason: .focusChanged)
      return
    }
    let candidate = ManualRepeatCandidate(original: original, currentText: text, context: after,
      layout: target, delimiter: original.delimiter, fieldIdentity: identity)
    if !runtime.retainManualResult(candidate, expectedGeneration: generation) {
      runtime.updateLayout(target)
    }
  }
  private func repeatManual(_ candidate: ManualRepeatCandidate, mapping: LayoutMapping,
                            generation: UInt64) -> ApplyResult {
    let text: String
    if layoutCapture != nil {
      guard let converted = manualTables?.manualConversion(candidate.original, target: mapping.target)
      else { return .aborted }
      text = converted.replacement
    } else {
      text = LayoutConverter.convert(candidate.currentText, mapping: mapping)
    }
    guard text != candidate.currentText, runtime.inputGeneration() == generation else { return .aborted }
    let result: ApplyResult
    if selectionAccess.suffix(candidate.currentText + candidate.delimiter, in: candidate.context) != nil {
      result = replacement.apply(.init(expected: candidate.context, original: candidate.currentText,
        replacement: text, sourceLayout: candidate.layout, targetLayout: mapping.target,
        delimiter: candidate.delimiter))
    } else if let repeated = selectionAccess as? ManualRepeatedSuffixReplacing {
      result = repeated.replaceRepeatedSuffix(candidate, with: text + candidate.delimiter)
      replacement.invalidate(.unknownInput)
    } else { return .aborted }
    if result == .dispatched {
      guard VerifiedLayoutSwitcher(access: layouts).select(mapping.target) else {
        quarantine(.uncertain, token: candidate.context)
        return .uncertain
      }
    }
    if result == .committed || result == .dispatched {
      retainManualResult(original: candidate.original, text: text, target: mapping.target,
        identity: candidate.fieldIdentity, before: candidate.context, generation: generation)
      if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .manual) }
    } else {
      runtime.invalidateContext(reason: .unknownInput)
      quarantine(result, token: candidate.context)
    }
    return result
  }
  public func manualCorrection() -> ApplyResult {
    precondition(Thread.isMainThread)
    let manualGeneration = runtime.inputGeneration()
    manualActionScope.active = true
    defer { manualActionScope.active = false }
    InputDiagnostics.event("manual.start.wordLength", detail: runtime.manualWord()?.text.count ?? 0)
    guard let token = editContext.current() else {
      InputDiagnostics.event("manual.contextMissing")
      return .aborted
    }
    guard ready(token, diagnose: true) else { return .aborted }
    guard let current = layouts.current() else {
      InputDiagnostics.event("manual.layoutMissing")
      return .aborted
    }
    let selected = selectionAccess.selected(in: token)
    InputDiagnostics.event("manual.selectedProof", detail: selected == nil ? 0 : 1)
    InputDiagnostics.event("manual.selectionNonempty", detail: selected?.text.isEmpty == false ? 1 : 0)
    let manualMapping = manualMapping(from: current)
    guard runtime.inputGeneration() == manualGeneration else {
      InputDiagnostics.event("manual.mappingCapture.inputChanged")
      return .aborted
    }
    InputDiagnostics.event("manual.mappingExists", detail: manualMapping == nil ? 0 : 1)
    if let evidence = selected, !evidence.text.isEmpty,
      let mapping = manualMapping
    {
      runtime.discardManualCandidate()
      let text = LayoutConverter.convert(evidence.text, mapping: mapping)
      guard text != evidence.text else { return .aborted }
      let result = selectionAccess.replace(evidence, with: text)
      diagnoseResult(result, event: "manual.selection.result")
      guard result == .committed else {
        quarantine(result, token: token)
        return result
      }
      guard VerifiedLayoutSwitcher(access: layouts).select(mapping.target),
        let after = editContext.refresh()
      else {
        quarantine(.uncertain, token: token)
        return .uncertain
      }
      runtime.updateLayout(mapping.target)
      let plan = EditPlan(
        expected: token, original: evidence.text, replacement: text, sourceLayout: current,
        targetLayout: mapping.target, delimiter: "")
      replacement.recordCommitted(plan, after: after)
      onCommitted(plan.id, .manual)
      return .committed
    }
    if let repeated = runtime.manualRepeatCandidate(), let mapping = manualMapping,
      repeated.context == token, repeated.layout == current {
      return repeatManual(repeated, mapping: mapping, generation: manualGeneration)
    }
    if replacement.hasUndo {
      let undone = undoLast()
      if undone != .aborted { return undone }
    }
    guard let capturedWord = runtime.manualWord(), capturedWord.context == token, capturedWord.layout == current,
      let mapping = manualMapping
    else {
      InputDiagnostics.event("manual.wordContextLayoutOrMappingMissing")
      return .aborted
    }
    let word: BufferedWord
    let text: String
    if layoutCapture != nil {
      guard let converted = manualTables?.manualConversion(capturedWord, target: mapping.target) else {
        InputDiagnostics.event("manual.physicalTranslationMissing")
        return .aborted
      }
      word = converted.word
      text = converted.replacement
      InputDiagnostics.event("manual.rawMatchesPhysical", detail: capturedWord.text == word.text ? 1 : 0)
    } else {
      word = capturedWord
      text = LayoutConverter.convert(word.text, mapping: mapping)
    }
    guard runtime.inputGeneration() == manualGeneration, text != word.text else { return .aborted }
    if selectionAccess.suffix(word.text + word.delimiter, in: token) == nil,
      let tracked = selectionAccess as? ManualTrackedSuffixReplacing
    {
      // Only explicit manual input can use a freshly proved empty AX proxy.
      // This branch runs before any proven-range mutation, never as a retry.
      InputDiagnostics.event("manual.trackedFallback.begin")
      let result = tracked.replaceTrackedSuffix(word, with: text + word.delimiter)
      diagnoseResult(result, event: "manual.trackedFallback.result")
      replacement.invalidate(.unknownInput)
      if result == .dispatched {
        guard VerifiedLayoutSwitcher(access: layouts).select(mapping.target) else {
          quarantine(.uncertain, token: token)
          return .uncertain
        }
        retainManualResult(original: word, text: text, target: mapping.target,
          identity: selected?.identity, before: token, generation: manualGeneration)
      } else if result == .uncertain {
        quarantine(result, token: token)
      }
      return result
    }
    let result = replacement.apply(
      .init(
        expected: token, original: word.text, replacement: text, sourceLayout: word.layout,
        targetLayout: mapping.target, delimiter: word.delimiter))
    diagnoseResult(result, event: "manual.suffix.result")
    if result == .uncertain { quarantine(result, token: token) }
    if result == .committed {
      retainManualResult(original: word, text: text, target: mapping.target,
        identity: selected?.identity, before: token, generation: manualGeneration)
      if let id = replacement.lastCommittedID { onCommitted(id, .manual) }
    } else if let layout = layouts.current() { runtime.updateLayout(layout) }
    return result
  }
  public func plainPaste(clipboard: ClipboardAccess) -> ApplyResult {
    precondition(Thread.isMainThread)
    guard let token = editContext.current() else { return .aborted }
    return plainPaste(in: token, clipboard: clipboard)
  }
  public func plainPaste(in token: ContextToken, clipboard: ClipboardAccess) -> ApplyResult {
    precondition(Thread.isMainThread)
    guard ready(token) else { return .aborted }
    replacement.invalidate(.unknownInput)
    runtime.discardManualCandidate()
    let result = selection.plainPaste(in: token, clipboard: clipboard)
    quarantine(result, token: token)
    return result
  }
  public func undoLast() -> ApplyResult {
    precondition(Thread.isMainThread)
    if runtime.manualRepeatCandidate() != nil { runtime.discardManualCandidate() }
    guard let token = editContext.current(), ready(token) else { return .aborted }
    let result = replacement.undoLast()
    quarantine(result, token: token)
    if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .undo) }
    return result
  }
}
