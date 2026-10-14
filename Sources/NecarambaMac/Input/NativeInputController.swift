import Foundation
import NecarambaCore

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
  private let engineBuilder: RuleEngineBuilding
  private let compiler = DispatchQueue(label: "Necaramba rules compiler")
  private var quarantined: ContextToken?
  private var preparationLease: ShortcutLease?
  private let corpusQualified: Bool
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
      context: editContext, qualifies: { profiles.qualifies(bundleID: $0, role: $1) })
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
  private func ready(_ token: ContextToken) -> Bool {
    guard quarantined != token else { return false }
    let p = permissions.current()
    guard p.listen, p.post, p.ax, !p.secureInput, editContext.refresh() == token else {
      return false
    }
    return true
  }
  private func execute(_ command: RuntimeCommand) {
    precondition(Thread.isMainThread)
    switch command {
    case .gesture(let action, let token):
      guard permissions.current().listen, !permissions.current().secureInput else { return }
      switch action {
      case .toggleAuto: onToggleAuto()
      case .manualCorrection:
        guard ready(token) else { return }
        report(manualCorrection(), token: token)
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
      guard corpusQualified, ready(word.context), appOverrides[word.context.bundleID] != .deny,
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
  public func manualCorrection() -> ApplyResult {
    precondition(Thread.isMainThread)
    guard let token = editContext.current(), ready(token), let current = layouts.current() else {
      return .aborted
    }
    if let evidence = selectionAccess.selected(in: token), !evidence.text.isEmpty,
      let mapping = rules.mappings.first(where: { $0.source == current })
    {
      let text = LayoutConverter.convert(evidence.text, mapping: mapping)
      guard text != evidence.text else { return .aborted }
      let result = selectionAccess.replace(evidence, with: text)
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
    if replacement.hasUndo {
      let undone = undoLast()
      if undone != .aborted { return undone }
    }
    guard let word = runtime.manualWord(), word.context == token,
      let mapping = rules.mappings.first(where: { $0.source == word.layout })
    else { return .aborted }
    let text = LayoutConverter.convert(word.text, mapping: mapping)
    let result = replacement.apply(
      .init(
        expected: token, original: word.text, replacement: text, sourceLayout: word.layout,
        targetLayout: mapping.target, delimiter: word.delimiter))
    if result == .uncertain { quarantine(result, token: token) }
    if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .manual) }
    if let layout = layouts.current() { runtime.updateLayout(layout) }
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
    let result = selection.plainPaste(in: token, clipboard: clipboard)
    quarantine(result, token: token)
    return result
  }
  public func undoLast() -> ApplyResult {
    precondition(Thread.isMainThread)
    guard let token = editContext.current(), ready(token) else { return .aborted }
    let result = replacement.undoLast()
    quarantine(result, token: token)
    if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .undo) }
    return result
  }
}
