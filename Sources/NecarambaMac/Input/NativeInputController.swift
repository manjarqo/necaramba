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
  @MainActor private lazy var transactions = EditTransactionCoordinator()
  private let injectedClipboardSelection: ClipboardSelectionConverting?
  @MainActor private lazy var clipboardSelection: ClipboardSelectionConverting = injectedClipboardSelection
    ?? ClipboardSelectionConverter(clipboard: SystemClipboard(), shortcuts: RuntimeCommandShortcuts(runtime: runtime))
  /// Native terminals copy terminal output; pasting there would not replace a selection.
  static func isNativeTerminal(_ bundleID: String) -> Bool {
    ApplicationProfileRegistry.shared.profile(for: bundleID)?.nativeTerminal == true
  }
  private var quarantined: ContextToken?
  private var pendingLayoutTransition: (target: LayoutID, generation: UInt64)?
  private var replacementLayout: LayoutID?
  private var preparationLease: ShortcutLease?
  private let corpusQualified: Bool
  private let manualActionScope: ManualActionScope
  private let automaticActionScope: ManualActionScope
  private let conservativeAutomaticEnabled: Bool
  private var automaticEngine: LinguisticEngine?
  private var localPatternEngine: PatternCorrectionEngine?
  private var openCorrectionEngine: OpenCorrectionEngine?
  private var fallbackAutomaticReady = false
  private var automaticPair: (ru: LayoutID, en: LayoutID)?
  private var automaticTables: CapturedLayoutTables? {
    didSet { automaticPair = automaticTables.flatMap(Self.ruENLayouts) }
  }
  private var preparedWordPolicy = PreparedWordPolicy(excluded: [], protected: [])
  private var preparedAutomaticPolicy = PreparedWordPolicy(excluded: [], protected: [])
  private var preparedOpenPolicy = PreparedWordPolicy(excluded: [], protected: [])
  private var availableLayoutRevision: UInt64 = 0
  private var rulesInstallRequest: UInt64 = 0
  private var localInstallRequest: UInt64 = 0
  private var openInstallRequest: UInt64 = 0
  private var requestedRules = RuleSnapshot(modelVersion: 0)
  private var excluded: Set<String> = []
  private var appOverrides: [String: AppOverride] = [:]
  public private(set) var automaticReady = false
  public var onAutomaticReadinessChanged: ((Bool) -> Void)?
  public var onResult: (ApplyResult) -> Void = { _ in }
  public var onCommitted: (UUID, CounterKind) -> Void = { _, _ in }
  public var onToggleAuto: () -> Void = {}
  public init(
    profiles: CapabilityProfiles = CapabilityProfiles(), layouts: LayoutAccess = TISLayoutAdapter(),
    permissions: PermissionReading = PermissionMonitor(),
    preferences: PreferencesSnapshot = .defaults, snapshot: RuleSnapshot = .init(modelVersion: 0),
    corpusQualified: Bool = false, conservativeAutomaticEnabled: Bool = false, editingContext: ContextRefreshing? = nil,
    selectionAccess: SelectionAccess? = nil, layoutCapture: LayoutTableCapturing? = nil,
    engineBuilder: RuleEngineBuilding = RuleEngineBuilder(),
    clipboardSelection: ClipboardSelectionConverting? = nil
  ) {
    injectedClipboardSelection = clipboardSelection
    precondition(Thread.isMainThread)
    let manualScope = ManualActionScope()
    manualActionScope = manualScope
    let automaticScope = ManualActionScope()
    automaticActionScope = automaticScope
    self.conservativeAutomaticEnabled = conservativeAutomaticEnabled
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
      allowMissingMarkedTextRange: { manualScope.active },
      allowAutomaticBoundary: { automaticScope.active })
    self.selectionAccess = selectionAccess ?? ax
    selection = SelectionAdapter(selection: self.selectionAccess)
    replacement = ReplacementCoordinator(
      context: editContext, layouts: layouts, sender: KeySender(selection: self.selectionAccess))
    runtime = InputRuntime(
      context: editingContext as ContextAccess? ?? monitor.state,
      initialLayout: layouts.current() ?? LayoutID(rawValue: "unsupported"),
      preferences: preferences, snapshot: initial, earlyEnabled: corpusQualified && !conservativeAutomaticEnabled,
      conservativeAutomaticEnabled: conservativeAutomaticEnabled, engine: engine,
      command: { [weak self] in self?.execute($0) })
    ax.executeAsync = { [weak self] evidence, text, selected, preflight in
      guard let self, self.replacementLayout == nil || self.layouts.current() == self.replacementLayout else { return .aborted }
      let target = self.replacementLayout
      return await self.runtime.replaceByKeysAsync(
        evidence, with: text, selected: selected, lease: self.preparationLease, physicalKeys: self.replayKeys(text),
        phaseAuthorization: { [weak self] in
          guard let self else { return false }
          return target == nil || self.layouts.current() == target
        }, preflight: preflight)
    }
    ax.executePhysicalAsync = { [weak self] mutation, text, preflight in
      guard let self, self.replacementLayout == nil || self.layouts.current() == self.replacementLayout else {
        InputDiagnostics.event("tap.post.aborted", detail: 12)
        return .aborted
      }
      let target = self.replacementLayout
      return await self.runtime.replacePhysicalSuffixAsync(mutation, with: text, lease: self.preparationLease,
        physicalKeys: self.replayKeys(text), phaseAuthorization: { [weak self] in
          guard let self else { return false }
          return target == nil || self.layouts.current() == target
        }, preflight: preflight)
    }
    ax.onStage = { [weak self] stage in self?.transactions.transition(stage) }
    ax.inputGeneration = { [weak self] in self?.runtime.inputGeneration() ?? UInt64.max }
    replacement.selectLayout = { [weak self] target, token, generation in
      guard let self else { return false }
      return await self.selectLayout(target, in: token, generation: generation)
    }
    replacement.authorization = { [weak self] token, generation in
      guard let self else { return false }
      return self.layoutAuthorized(token, generation: generation)
    }
    replacement.inputGeneration = { [weak self] in self?.runtime.inputGeneration() ?? .max }
    runtime.onInputInvalidation = { [weak self] in self?.replacement.invalidate(.unknownInput) }
    monitor.onLayoutChanged = { [weak self] id in
      guard let self else { return }
      if let pending = self.pendingLayoutTransition, id == pending.target,
        self.runtime.inputGeneration() == pending.generation {
        // The monitor still publishes fresh focus/security evidence. Defer only
        // our own runtime layout bookkeeping until verified TIS completion.
        return
      }
      let old = self.runtime.cachedInputContext()?.1
      if let id {
        self.runtime.updateLayout(id)
      } else {
        self.runtime.invalidateContext(reason: .layoutChanged)
      }
      if old != id { self.replacement.invalidate(.layoutChanged) }
    }
    monitor.onAvailableLayoutsChanged = { [weak self] in
      guard let self else { return }
      self.availableLayoutRevision &+= 1
      self.manualTables = nil
      self.automaticTables = nil
      self.fallbackAutomaticReady = false
      self.runtime.invalidateContext(reason: .layoutChanged)
      self.replacement.invalidate(.layoutChanged)
      self.install(self.requestedRules)
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
      self.requestedRules = snapshot
      self.rulesInstallRequest &+= 1
      let request = self.rulesInstallRequest
      let revision = self.availableLayoutRevision
      let tables = self.captureTablesIfNeeded()
      self.compiler.async { [weak self] in
        guard let self else { return }
        let actual = tables?.resolve(snapshot) ?? snapshot
        let prepared = self.engineBuilder.build(
          snapshot: actual, physicalMappings: tables?.physicalMappings(for: actual) ?? [])
        let automaticRules = self.conservativeAutomaticEnabled ? tables?.layoutOnlySnapshot(snapshot) : nil
        let automaticEngine = automaticRules.map {
          LinguisticEngine(snapshot: $0, physicalMappings: tables?.physicalMappings(for: $0) ?? [])
        }
        let automaticReady = automaticRules.map { !$0.lexicon.isEmpty && !$0.mappings.isEmpty } ?? false
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard request == self.rulesInstallRequest else { onInstalled(self.rules.modelVersion); return }
          guard revision == self.availableLayoutRevision else { self.install(snapshot, onInstalled: onInstalled); return }
          self.rules = actual
          self.prepareWordPolicies()
          self.engine = prepared
          self.automaticEngine = automaticEngine
          self.automaticTables = tables
          self.fallbackAutomaticReady = automaticReady
          self.runtime.install(actual, engine: prepared)
          self.refreshAutomaticReadiness()
          onInstalled(actual.modelVersion)
        }
      }
    }
    if Thread.isMainThread { capture() } else { DispatchQueue.main.async(execute: capture) }
  }
  public func installLocalModel(url: URL, onInstalled: @escaping (Result<String, Error>) -> Void) {
    let capture = { [weak self] in
      guard let self else { return }
      self.localInstallRequest &+= 1
      let request = self.localInstallRequest
      let revision = self.availableLayoutRevision
      let tables = self.captureTablesIfNeeded()
      self.compiler.async { [weak self] in
        let result = Result { try LocalPatternModelLoader.load(url: url) }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard request == self.localInstallRequest else { onInstalled(.failure(CocoaError(.userCancelled))); return }
          guard revision == self.availableLayoutRevision else { self.installLocalModel(url: url, onInstalled: onInstalled); return }
          switch result {
          case .success(let model):
            self.localPatternEngine = .init(classifier: model.classifier, autocorrector: model.autocorrector)
            self.automaticTables = tables
            self.manualTables = tables
            self.runtime.invalidateContext(reason: .unknownInput)
            self.replacement.invalidate(.unknownInput)
            self.refreshAutomaticReadiness()
            onInstalled(.success(model.version))
          case .failure(let error): onInstalled(.failure(error))
          }
        }
      }
    }
    if Thread.isMainThread { capture() } else { DispatchQueue.main.async(execute: capture) }
  }
  public func installOpenModel(directory: URL, onInstalled: @escaping (Result<String, Error>) -> Void) {
    let capture = { [weak self] in
      guard let self else { return }
      self.openInstallRequest &+= 1
      let request = self.openInstallRequest
      let revision = self.availableLayoutRevision
      let tables = self.captureTablesIfNeeded()
      self.compiler.async { [weak self] in
        let result = Result { try OpenModelLoader.load(directory: directory) }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard request == self.openInstallRequest else { onInstalled(.failure(CocoaError(.userCancelled))); return }
          guard revision == self.availableLayoutRevision else { self.installOpenModel(directory: directory, onInstalled: onInstalled); return }
          switch result {
          case .success(let model):
            self.openCorrectionEngine = model.engine
            self.prepareWordPolicies()
            self.automaticTables = tables
            self.manualTables = tables
            self.runtime.invalidateContext(reason: .unknownInput)
            self.replacement.invalidate(.unknownInput)
            self.refreshAutomaticReadiness()
            onInstalled(.success(model.version))
          case .failure(let error): onInstalled(.failure(error))
          }
        }
      }
    }
    if Thread.isMainThread { capture() } else { DispatchQueue.main.async(execute: capture) }
  }
  private func prepareWordPolicies() {
    preparedWordPolicy = .init(excluded: excluded, protected: [])
    preparedAutomaticPolicy = .init(excluded: excluded.union(rules.protectedTokens), protected: [])
    // The open model never changes ё in its ambiguous е/ё words but permits an explicit
    // physical layout conversion to them. Generic package tokens must not override that
    // narrower classification; user exclusions and all other tokens still apply.
    let yoAmbiguous = openCorrectionEngine?.yoProtectedWords ?? []
    preparedOpenPolicy = .init(excluded: excluded.union(rules.protectedTokens.filter {
      !yoAmbiguous.contains(TokenGuard.normalized($0)) }), protected: [])
  }
  private func captureTablesIfNeeded() -> CapturedLayoutTables? {
    if let manualTables { return manualTables }
    let tables = layoutCapture?.captureTables()
    manualTables = tables
    return tables
  }
  private func refreshAutomaticReadiness() {
    let modelReady = (localPatternEngine != nil || openCorrectionEngine != nil) && automaticPair != nil
    runtime.updateLocalAutomaticReadiness(modelReady)
    automaticReady = conservativeAutomaticEnabled && (modelReady || fallbackAutomaticReady)
    InputDiagnostics.event("auto.ready", detail: automaticReady ? 1 : 0)
    onAutomaticReadinessChanged?(automaticReady)
  }
  /// Identify alphabet coverage from captured unmodified translations, not TIS names.
  /// Multiple matching layouts are ambiguous and must not be selected arbitrarily.
  private static func ruENLayouts(_ tables: CapturedLayoutTables) -> (ru: LayoutID, en: LayoutID)? {
    let latin = Set("abcdefghijklmnopqrstuvwxyz")
    let russian = Set("абвгдежзийклмнопрстуфхцчшщъыьэюя")
    var en: [LayoutID] = [], ru: [LayoutID] = []
    for layout in tables.layouts {
      let alphabet = Set(layout.entries.filter { $0.modifiers.isEmpty && $0.text.count == 1 }.flatMap { Array($0.text) })
      if latin.isSubset(of: alphabet) { en.append(layout.id) }
      if russian.isSubset(of: alphabet) { ru.append(layout.id) }
    }
    guard en.count == 1, ru.count == 1, en[0] != ru[0] else { return nil }
    return (ru[0], en[0])
  }
  public func updateWordPolicies(_ words: Set<String>) {
    guard excluded != words else { return }
    excluded = words
    prepareWordPolicies()
    runtime.invalidateContext(reason: .unknownInput)
  }
  public func updateAppPolicies(_ policies: [String: AppOverride]) {
    guard appOverrides != policies else { return }
    appOverrides = policies
    runtime.invalidateContext(reason: .unknownInput)
  }
  public func invalidateContext(reason: InvalidationReason) {
    runtime.invalidateContext(reason: reason)
    context.invalidateAndRequestRecovery(reason)
    replacement.invalidate(reason)
  }
  private func ready(_ token: ContextToken, diagnose: Bool = false) -> Bool {
    guard !Task.isCancelled, quarantined != token else {
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
  private func layoutAuthorized(_ token: ContextToken, generation: UInt64) -> Bool {
    let p = permissions.current()
    guard !Task.isCancelled, runtime.inputGeneration() == generation,
      p.listen, p.post, p.ax, !p.secureInput,
      let current = editContext.current(), editContext.isSafe(current) else { return false }
    return current.pid == token.pid && current.bundleID == token.bundleID && current.focusEpoch == token.focusEpoch
  }
  @MainActor private func selectLayout(_ target: LayoutID, in token: ContextToken,
                                       generation: UInt64, editing: Bool = true) async -> Bool {
    pendingLayoutTransition = (target, generation)
    if editing { replacementLayout = target }
    defer { if !editing { pendingLayoutTransition = nil } }
    return await VerifiedLayoutSwitcher(access: layouts).selectAsync(target, authorized: {
      if editing { return self.layoutAuthorized(token, generation: generation) }
      let p = self.permissions.current()
      guard !Task.isCancelled, p.listen, !p.secureInput,
        self.runtime.inputGeneration() == generation,
        let current = self.runtime.cachedInputContext()?.0 else { return false }
      return current.pid == token.pid && current.bundleID == token.bundleID && current.focusEpoch == token.focusEpoch
    })
  }
  /// An aborted automatic edit posted no key, so the text is unchanged; it must not
  /// leave the layout selected for the replacement. New input keeps the user's layout.
  @MainActor private func restoreUnchangedLayout(_ original: LayoutID, token: ContextToken,
                                                 generation: UInt64) async {
    guard layouts.current() != original, runtime.inputGeneration() == generation else { return }
    _ = await selectLayout(original, in: token, generation: generation, editing: false)
  }
  private func finishReplacementLayout() {
    pendingLayoutTransition = nil
    replacementLayout = nil
    if let current = layouts.current() { runtime.updateLayout(current) }
  }
  private func replayKeys(_ text: String) -> [PhysicalLayoutMapping.Entry]? {
    guard let target = replacementLayout, layouts.current() == target else { return nil }
    return (manualTables ?? automaticTables)?.replayKeys(for: text, in: target)
  }
  @MainActor private func prepareMutation(_ target: LayoutID, token: ContextToken,
                                         generation: UInt64) async -> ContextToken? {
    guard editContext.isSafe(token), layoutAuthorized(token, generation: generation),
      await selectLayout(target, in: token, generation: generation),
      let after = editContext.refresh(), layouts.current() == target,
      layoutAuthorized(token, generation: generation), editContext.isSafe(after),
      after.pid == token.pid, after.bundleID == token.bundleID,
      after.focusEpoch == token.focusEpoch else { return nil }
    return after
  }
  // This only translates an intentional layout epoch. The original physical
  // key, text, source layout and origin remain unchanged; focus/input checks
  // above must succeed before this frozen evidence is rebased.
  private func rebased(_ event: InputEvent, in token: ContextToken) -> InputEvent {
    .init(kind: event.kind, keyCode: event.keyCode, modifiers: event.modifiers,
      timestampNanos: event.timestampNanos, layout: event.layout, context: token,
      origin: event.origin, text: event.text, isRepeat: event.isRepeat)
  }
  private func rebased(_ word: BufferedWord, in token: ContextToken) -> BufferedWord? {
    guard word.events.allSatisfy({ $0.context == word.context }) else { return nil }
    return .init(text: word.text, events: word.events.map { rebased($0, in: token) },
      context: token, layout: word.layout, delimiter: word.delimiter)
  }
  private func execute(_ command: RuntimeCommand) {
    precondition(Thread.isMainThread)
    let token: ContextToken
    switch command {
    case .gesture(_, let context): token = context
    case .boundary(let word, _, _): token = word.context
    case .automaticBoundary(let candidate, _, _): token = candidate.word.context
    case .plainPaste(let lease): token = lease.context
    }
    let generation = runtime.inputGeneration()
    let recognizedAt = runtime.commandRecognizedAtNanos ?? InputPerformanceMetrics.nowNanos()
    Task { @MainActor [weak self] in
      guard let self else { return }
      var didRun = false
      self.transactions.start(token: token, operation: {
        guard self.runtime.inputGeneration() == generation else { return .aborted }
        didRun = true
        InputPerformanceMetrics.shared.record(.commandQueue, durationNanos: InputPerformanceMetrics.nowNanos() - recognizedAt)
        defer { InputPerformanceMetrics.shared.record(.total, durationNanos: InputPerformanceMetrics.nowNanos() - recognizedAt) }
        await self.executeAsync(command)
        return .aborted // Individual commands publish their verified result.
      }, completion: { result in
        // A rejected paste must release its captured shortcut immediately.
        if case .plainPaste(let lease) = command, !didRun {
          self.runtime.finishShortcut(lease, .aborted)
        }
      })
    }
  }
  @MainActor private func executeAsync(_ command: RuntimeCommand) async {
    defer { finishReplacementLayout() }
    precondition(Thread.isMainThread)
    switch command {
    case .gesture(let action, let token):
      if case .manualCorrection = action {
        InputDiagnostics.event("manual.gesture.focusEpoch", detail: Int(clamping: token.focusEpoch))
        InputDiagnostics.event("manual.gesture.layoutEpoch", detail: Int(clamping: token.layoutEpoch))
      }
      guard permissions.current().listen, !permissions.current().secureInput else {
        runtime.discardManualCandidate()
        if case .manualCorrection = action { InputDiagnostics.event("manual.gesture.permissionsDenied") }
        return
      }
      switch action {
      case .toggleAuto: onToggleAuto()
      case .manualCorrection:
        guard ready(token, diagnose: true) else { return }
        let result = await manualCorrectionOperation()
        diagnoseResult(result, event: "manual.result")
        report(result, token: token)
      case .switchLayout:
        guard let current = layouts.current(),
          let next = layouts.supported().first(where: { $0 != current })
        else { return }
        let generation = runtime.inputGeneration()
        if await selectLayout(next, in: token, generation: generation, editing: false) {
          let after = editContext.refresh()
          runtime.updateLayout(next, preservingManualIn: after, expectedGeneration: generation)
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
        word: word, preferences: prefs, wordPolicy: preparedWordPolicy)
      {
        let plan = EditPlan(
          expected: word.context, original: correction.original,
          replacement: correction.replacement, sourceLayout: correction.sourceLayout,
          targetLayout: correction.targetLayout, delimiter: word.delimiter)
        let result = await replacement.applyAsync(plan)
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
    case .automaticBoundary(let candidate, let snapshot, let prefs):
      await executeAutomaticAsync(candidate, snapshot: snapshot, preferences: prefs)
    case .plainPaste(let lease):
      preparationLease = lease
      let result = await plainPasteOperation(in: lease.context, clipboard: SystemClipboard())
      preparationLease = nil
      runtime.finishShortcut(lease, result)
      report(result, token: lease.context)
    }
  }
  @MainActor private func executeAutomaticAsync(_ candidate: AutomaticBoundaryCandidate, snapshot: RuleSnapshot,
                                preferences: PreferencesSnapshot) async {
    InputDiagnostics.event("auto.boundary.received")
    guard conservativeAutomaticEnabled, automaticReady,
      snapshot.modelVersion == rules.modelVersion, preferences.autoEnabled, self.preferences.autoEnabled,
      appOverrides[candidate.word.context.bundleID] != .deny,
      candidate.inputGeneration == runtime.inputGeneration(),
      candidate.boundary.kind == .down, candidate.boundary.origin == .physical,
      candidate.boundary.keyCode == 49, candidate.boundary.text == " ", candidate.word.delimiter == " ",
      candidate.boundary.context == candidate.word.context, candidate.boundary.layout == candidate.word.layout,
      ready(candidate.word.context), layouts.current() == candidate.word.layout,
      let tables = automaticTables,
      let source = tables.manualConversion(candidate.word, target: candidate.word.layout)?.word else {
      InputDiagnostics.event("auto.boundary.contextOrMappingDenied")
      return
    }
    let classificationStart = InputPerformanceMetrics.nowNanos()
    let decision: LinguisticDecision
    let usingFullModel: Bool
    if let localPatternEngine, let pair = automaticPair {
      guard let ru = tables.manualConversion(source, target: pair.ru)?.replacement,
        let en = tables.manualConversion(source, target: pair.en)?.replacement else { return }
      usingFullModel = true
      decision = localPatternEngine.decide(word: source, russianCandidate: ru, russianLayout: pair.ru,
        englishCandidate: en, englishLayout: pair.en, preferences: self.preferences,
        wordPolicy: preparedAutomaticPolicy, modelVersion: rules.modelVersion,
        physicalCandidatesVerified: true)
    } else if let openCorrectionEngine, let pair = automaticPair {
      guard let ru = tables.manualConversion(source, target: pair.ru)?.replacement,
        let en = tables.manualConversion(source, target: pair.en)?.replacement else { return }
      usingFullModel = true
      decision = openCorrectionEngine.decide(word: source, russianCandidate: ru, russianLayout: pair.ru,
        englishCandidate: en, englishLayout: pair.en, preferences: self.preferences,
        wordPolicy: preparedOpenPolicy, modelVersion: rules.modelVersion,
        physicalCandidatesVerified: true)
    } else {
      guard source.text.count >= 3, let automaticEngine else { return }
      usingFullModel = false
      let conservative = PreferencesSnapshot(autoEnabled: true, typoEnabled: false, yoEnabled: false)
      decision = automaticEngine.decide(word: source, preferences: conservative, wordPolicy: preparedWordPolicy)
    }
    InputPerformanceMetrics.shared.record(.classification, durationNanos: InputPerformanceMetrics.nowNanos() - classificationStart)
    guard case .replace(let correction) = decision else {
      if case .unchanged(let reason) = decision { InputDiagnostics.event("auto.decision." + reason.rawValue) }
      return
    }
    InputDiagnostics.event("auto.decision." + correction.kind.rawValue)
    guard (usingFullModel || correction.kind == .layout), candidate.inputGeneration == runtime.inputGeneration(),
      let automatic = selectionAccess as? AutomaticBoundarySuffixReplacing else { return }
    automaticActionScope.active = true
    defer { automaticActionScope.active = false }
    let initialCandidate = AutomaticBoundaryCandidate(word: source, boundary: candidate.boundary,
      inputGeneration: candidate.inputGeneration, requiresWordStartProof: candidate.requiresWordStartProof,
      allowsOpaqueWordStart: candidate.allowsOpaqueWordStart)
    if let eligibility = selectionAccess as? AutomaticBoundaryEligibilityReading {
      guard eligibility.canReplaceAutomaticBoundary(initialCandidate,
        with: correction.replacement + source.delimiter) else {
        InputDiagnostics.event("auto.eligibility.rejected")
        return
      }
    } else if candidate.requiresWordStartProof && !candidate.allowsOpaqueWordStart {
      // An adapter without word-start eligibility cannot authorize a lost prefix.
      return
    }
    guard candidate.boundary.context == source.context,
      let mutationContext = await prepareMutation(correction.targetLayout, token: source.context,
        generation: candidate.inputGeneration),
      let mutationWord = rebased(source, in: mutationContext) else {
      await restoreUnchangedLayout(candidate.word.layout, token: source.context, generation: candidate.inputGeneration)
      return
    }
    var identity = selectionAccess.selected(in: mutationContext)?.identity
    let proven = AutomaticBoundaryCandidate(word: mutationWord, boundary: rebased(candidate.boundary, in: mutationContext),
      inputGeneration: candidate.inputGeneration, requiresWordStartProof: candidate.requiresWordStartProof,
      allowsOpaqueWordStart: candidate.allowsOpaqueWordStart)
    let result = await automatic.replaceAutomaticBoundaryAsync(proven, with: correction.replacement + source.delimiter)
    diagnoseResult(result, event: "auto.result")
    if result == .dispatched, let dispatched = selectionAccess as? SuffixDispatchProofReading {
      identity = dispatched.dispatchedSuffix(in: mutationContext, inputGeneration: candidate.inputGeneration)?.focus.identity
    }
    guard result == .committed || result == .dispatched else {
      if result == .aborted {
        await restoreUnchangedLayout(candidate.word.layout, token: mutationContext, generation: candidate.inputGeneration)
      }
      report(result, token: source.context)
      return
    }
    guard candidate.inputGeneration == runtime.inputGeneration(),
      layouts.current() == correction.targetLayout,
      let after = editContext.refresh(), after.pid == source.context.pid,
      after.bundleID == source.context.bundleID, after.focusEpoch == source.context.focusEpoch,
      layoutAuthorized(source.context, generation: candidate.inputGeneration) else {
      report(.uncertain, token: source.context)
      return
    }
    var committedCounter: (UUID, CounterKind)?
    if result == .committed {
      // Spark may normalize the physical Space to NBSP. Journal only the
      // exact committed boundary, proved in the same field and input generation.
      var committedDelimiter: String? = source.delimiter
      if source.context.bundleID == "com.readdle.SparkDesktop" {
        committedDelimiter = nil
        for delimiter in [source.delimiter, "\u{00a0}"] {
          guard candidate.inputGeneration == runtime.inputGeneration(), editContext.isSafe(after) else { break }
          let suffix = correction.replacement + delimiter
          guard let proof = selectionAccess.suffix(suffix, in: after),
            proof.text == suffix, proof.context == after, identity != nil, proof.identity == identity,
            proof.inputGeneration == candidate.inputGeneration,
            candidate.inputGeneration == runtime.inputGeneration(), editContext.isSafe(after)
          else { continue }
          committedDelimiter = delimiter
          break
        }
      }
      let plan = EditPlan(expected: source.context, original: source.text, replacement: correction.replacement,
        sourceLayout: source.layout, targetLayout: correction.targetLayout,
        delimiter: committedDelimiter ?? source.delimiter)
      if committedDelimiter != nil { replacement.recordCommitted(plan, after: after) }
      else { replacement.invalidate(.unknownInput) }
      let kind: CounterKind
      switch correction.kind {
      case .layout: kind = .layout
      case .typo: kind = .typo
      case .yo: kind = .yo
      case .doubleCaps: kind = .doubleCaps
      case .combined: kind = correction.targetLayout == correction.sourceLayout ? .typo : .layout
      }
      committedCounter = (plan.id, kind)
    } else { replacement.invalidate(.unknownInput) }
    guard retainManualResult(original: source, text: correction.replacement, target: correction.targetLayout,
      identity: identity, before: source.context, generation: candidate.inputGeneration) else { report(.uncertain, token: source.context); return }
    if let committedCounter { onCommitted(committedCounter.0, committedCounter.1) }
    report(result, token: source.context)
  }
  private func quarantine(_ result: ApplyResult, token: ContextToken) {
    if result == .uncertain {
      quarantined = token
      runtime.invalidateContext(reason: .unknownInput)
      replacement.invalidate(.unknownInput)
      context.invalidateAndRequestRecovery(.unknownInput)
    }
  }
  private func report(_ result: ApplyResult, token: ContextToken) {
    if result == .uncertain { InputPerformanceMetrics.shared.recordCancellation(.uncertain) }
    quarantine(result, token: token)
    onResult(result)
  }
  private func manualMapping(from source: LayoutID) -> LayoutMapping? {
    guard layoutCapture != nil else {
      return rules.mappings.first(where: { $0.source == source })
    }
    guard let target = layouts.supported().first(where: { $0 != source }) else { return nil }
    if let mapping = manualTables?.manualMapping(source: source, target: target) { return mapping }
    return captureTablesIfNeeded()?.manualMapping(source: source, target: target)
  }
  private func retainManualResult(original: BufferedWord, text: String, target: LayoutID,
                                  identity: UUID?, before: ContextToken, generation: UInt64, alternateText: String? = nil) -> Bool {
    guard let after = editContext.refresh(), after.pid == before.pid,
      after.bundleID == before.bundleID, after.focusEpoch == before.focusEpoch,
      layoutAuthorized(before, generation: generation) else {
      runtime.invalidateContext(reason: .focusChanged)
      return false
    }
    let candidate = ManualRepeatCandidate(original: original, currentText: text, context: after,
      layout: target, delimiter: original.delimiter, fieldIdentity: identity, alternateText: alternateText)
    if !runtime.retainManualResult(candidate, expectedGeneration: generation) {
      runtime.updateLayout(target)
      return false
    }
    return true
  }
  @MainActor private func repeatManualAsync(_ candidate: ManualRepeatCandidate, mapping: LayoutMapping,
                            generation: UInt64) async -> ApplyResult {
    let text: String
    if let alternate = candidate.alternateText {
      text = alternate
    } else if layoutCapture != nil {
      guard let converted = manualTables?.manualConversion(candidate.original, target: mapping.target)
      else { return .aborted }
      text = converted.replacement
    } else {
      text = LayoutConverter.convert(candidate.currentText, mapping: mapping)
    }
    guard text != candidate.currentText, runtime.inputGeneration() == generation else { return .aborted }
    let result: ApplyResult
    if selectionAccess.suffix(candidate.currentText + candidate.delimiter, in: candidate.context) != nil {
      result = await replacement.applyAsync(.init(expected: candidate.context, original: candidate.currentText,
        replacement: text, sourceLayout: layouts.current() ?? candidate.layout, targetLayout: mapping.target,
        delimiter: candidate.delimiter))
    } else if let repeated = selectionAccess as? ManualRepeatedSuffixReplacing {
      guard let mutationContext = await prepareMutation(mapping.target, token: candidate.context, generation: generation) else { return .aborted }
      result = await repeated.replaceRepeatedSuffixAsync(candidate.rebased(in: mutationContext), with: text + candidate.delimiter)
      replacement.invalidate(.unknownInput)
    } else { return .aborted }
    if result == .dispatched {
      guard layouts.current() == mapping.target else {
        quarantine(.uncertain, token: candidate.context)
        return .uncertain
      }
    }
    if result == .committed || result == .dispatched {
      guard retainManualResult(original: candidate.original, text: text, target: mapping.target,
        identity: candidate.fieldIdentity, before: candidate.context, generation: generation,
        alternateText: candidate.alternateText == nil ? nil : candidate.currentText) else { quarantine(.uncertain, token: candidate.context); return .uncertain }
      if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .manual) }
    } else {
      runtime.invalidateContext(reason: .unknownInput)
      quarantine(result, token: candidate.context)
    }
    return result
  }
  @MainActor public func manualCorrectionAsync() async -> ApplyResult {
    guard let token = editContext.current() else { return .aborted }
    let generation = runtime.inputGeneration()
    return await transactions.perform(token: token) {
      guard self.layoutAuthorized(token, generation: generation) else { return .aborted }
      return await self.manualCorrectionOperation()
    }
  }
  @MainActor public func undoLastAsync() async -> ApplyResult {
    guard let token = editContext.current() else { return .aborted }
    let generation = runtime.inputGeneration()
    return await transactions.perform(token: token) {
      guard self.layoutAuthorized(token, generation: generation) else { return .aborted }
      return await self.undoLastOperation()
    }
  }
  @MainActor public func plainPasteAsync(clipboard: ClipboardAccess) async -> ApplyResult {
    guard let token = editContext.current() else { return .aborted }
    return await plainPasteAsync(in: token, clipboard: clipboard)
  }
  @MainActor public func plainPasteAsync(in token: ContextToken, clipboard: ClipboardAccess) async -> ApplyResult {
    let generation = runtime.inputGeneration()
    return await transactions.perform(token: token) {
      guard self.layoutAuthorized(token, generation: generation) else { return .aborted }
      return await self.plainPasteOperation(in: token, clipboard: clipboard)
    }
  }
  @MainActor private func manualCorrectionOperation() async -> ApplyResult {
    defer { finishReplacementLayout() }
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
    var explicitText = selected
    let repeated = runtime.manualRepeatCandidate()
    // Spark can normalize the physical trailing Space to NBSP. Refresh physical
    // candidates from AX; retain literal alternate pairs for exact repeated undo.
    let needsCaretWord = repeated == nil ||
      (token.bundleID == "com.readdle.SparkDesktop" && repeated?.alternateText == nil)
    if selected?.text.isEmpty != false, needsCaretWord,
      let visibleWord = selectionAccess as? ManualCaretWordReading {
      switch visibleWord.wordBeforeCaret(in: token) {
      case .notRequired: break
      case .unavailable:
        InputDiagnostics.event("manual.caretWordUnavailable")
        return .aborted
      case .word(let evidence):
        explicitText = evidence
        InputDiagnostics.event("manual.caretWordLength", detail: evidence.text.count)
      }
    }
    if let evidence = explicitText, !evidence.text.isEmpty,
      let preferredMapping = manualMapping
    {
      let mapping = LayoutConverter.selectionMapping(evidence.text, preferred: preferredMapping,
        alternative: self.manualMapping(from: preferredMapping.target))
      guard runtime.inputGeneration() == manualGeneration else { return .aborted }
      runtime.discardManualCandidate()
      let text = LayoutConverter.convert(evidence.text, mapping: mapping)
      guard text != evidence.text else { return .aborted }
      guard let mutationContext = await prepareMutation(mapping.target, token: token, generation: manualGeneration) else { return .aborted }
      let rebasedEvidence = SelectionEvidence(context: mutationContext, text: evidence.text,
        location: evidence.location, length: evidence.length, identity: evidence.identity,
        inputGeneration: evidence.inputGeneration, mode: evidence.mode)
      let result = await selectionAccess.replaceAsync(rebasedEvidence, with: text)
      diagnoseResult(result, event: "manual.selection.result")
      guard result == .committed else {
        quarantine(result, token: token)
        return result
      }
      guard layouts.current() == mapping.target,
        let after = editContext.refresh(), after.pid == token.pid,
        after.bundleID == token.bundleID, after.focusEpoch == token.focusEpoch,
        layoutAuthorized(token, generation: manualGeneration)
      else {
        quarantine(.uncertain, token: token)
        return .uncertain
      }
      let original = BufferedWord(text: evidence.text, events: [], context: token, layout: mapping.source, delimiter: "")
      guard retainManualResult(original: original, text: text, target: mapping.target,
        identity: evidence.identity, before: token, generation: manualGeneration, alternateText: evidence.text) else { quarantine(.uncertain, token: token); return .uncertain }
      let plan = EditPlan(
        expected: token, original: evidence.text, replacement: text, sourceLayout: mapping.source,
        targetLayout: mapping.target, delimiter: "")
      replacement.recordCommitted(plan, after: after)
      onCommitted(plan.id, .manual)
      return .committed
    }
    if let repeated = runtime.manualRepeatCandidate(),
      let mapping = self.manualMapping(from: repeated.layout), repeated.context == token {
      return await repeatManualAsync(repeated, mapping: mapping, generation: manualGeneration)
    }
    if replacement.hasUndo {
      let undone = await undoLastOperation()
      if undone != .aborted { return undone }
    }
    InputDiagnostics.event("manual.cachedLayoutMatchesCurrent", detail: runtime.cachedInputContext()?.1 == current ? 1 : 0)
    guard let capturedWord = runtime.manualWord() else {
      if selected == nil, let manualMapping,
        let result = await clipboardSelectionConversion(token: token, layout: current,
          preferred: manualMapping, generation: manualGeneration) {
        return result
      }
      InputDiagnostics.event("manual.wordMissing")
      return .aborted
    }
    guard capturedWord.context == token else {
      InputDiagnostics.event("manual.wordContextMismatch")
      InputDiagnostics.event("manual.wordFocusEpoch", detail: Int(clamping: capturedWord.context.focusEpoch))
      InputDiagnostics.event("manual.currentFocusEpoch", detail: Int(clamping: token.focusEpoch))
      InputDiagnostics.event("manual.wordLayoutEpoch", detail: Int(clamping: capturedWord.context.layoutEpoch))
      InputDiagnostics.event("manual.currentLayoutEpoch", detail: Int(clamping: token.layoutEpoch))
      InputDiagnostics.event("manual.wordSamePID", detail: capturedWord.context.pid == token.pid ? 1 : 0)
      return .aborted
    }
    guard capturedWord.layout == current else {
      InputDiagnostics.event("manual.wordLayoutMismatch")
      return .aborted
    }
    guard let mapping = manualMapping else {
      InputDiagnostics.event("manual.wordMappingMissing")
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
      // This manual branch dispatches captured physical input to an empty or opaque proxy.
      // This branch runs before any proven-range mutation, never as a retry.
      InputDiagnostics.event("manual.trackedFallback.begin")
      guard let mutationContext = await prepareMutation(mapping.target, token: token, generation: manualGeneration),
        let mutationWord = rebased(word, in: mutationContext) else { return .aborted }
      let result = await tracked.replaceTrackedSuffixAsync(mutationWord, with: text + word.delimiter)
      diagnoseResult(result, event: "manual.trackedFallback.result")
      replacement.invalidate(.unknownInput)
      if result == .dispatched {
        let identity = (selectionAccess as? SuffixDispatchProofReading)?
          .dispatchedSuffix(in: mutationContext, inputGeneration: manualGeneration)?.focus.identity ?? selected?.identity
        guard layouts.current() == mapping.target else {
          quarantine(.uncertain, token: token)
          return .uncertain
        }
        guard retainManualResult(original: word, text: text, target: mapping.target,
          identity: identity, before: token, generation: manualGeneration) else { quarantine(.uncertain, token: token); return .uncertain }
      } else if result == .uncertain {
        quarantine(result, token: token)
      }
      return result
    }
    let result = await replacement.applyAsync(
      .init(
        expected: token, original: word.text, replacement: text, sourceLayout: word.layout,
        targetLayout: mapping.target, delimiter: word.delimiter))
    diagnoseResult(result, event: "manual.suffix.result")
    if result == .uncertain { quarantine(result, token: token) }
    if result == .committed {
      guard retainManualResult(original: word, text: text, target: mapping.target,
        identity: selected?.identity, before: token, generation: manualGeneration) else { quarantine(.uncertain, token: token); return .uncertain }
      if let id = replacement.lastCommittedID { onCommitted(id, .manual) }
    } else if let layout = layouts.current() { runtime.updateLayout(layout) }
    return result
  }
  /// A selection in a focused field that Accessibility cannot read, outside terminals.
  /// Returns nil when this path does not apply or the field has no selection.
  @MainActor private func clipboardSelectionConversion(token: ContextToken, layout: LayoutID,
    preferred: LayoutMapping, generation: UInt64) async -> ApplyResult? {
    guard let opaque = (selectionAccess as? OpaqueFocusReading)?.opaqueFocus(in: token),
      !opaque.terminalProxy, !Self.isNativeTerminal(token.bundleID) else { return nil }
    InputDiagnostics.event("manual.clipboardSelection.begin")
    // Our own layout selection changes only the layout epoch of the same field.
    let valid = { [weak self] () -> Bool in
      guard let self, self.runtime.inputGeneration() == generation, let current = self.editContext.current()
      else { return false }
      return current.pid == token.pid && current.bundleID == token.bundleID && current.focusEpoch == token.focusEpoch
    }
    let outcome = await clipboardSelection.convert(in: token, generation: generation, valid: valid) { copied in
      let mapping = LayoutConverter.selectionMapping(copied, preferred: preferred,
        alternative: self.manualMapping(from: preferred.target))
      let text = LayoutConverter.convert(copied, mapping: mapping)
      guard text != copied,
        let context = await self.prepareMutation(mapping.target, token: token, generation: generation)
      else { return nil }
      return (text, context)
    }
    let result: ApplyResult
    switch outcome {
    case .noSelection: result = .aborted
    case .rejected, .aborted: result = .aborted
    case .dispatched: result = .dispatched
    case .uncertain: result = .uncertain
    }
    InputDiagnostics.event("manual.clipboardSelection.result", detail: [.noSelection: 0, .rejected: 1,
      .aborted: 2, .dispatched: 3, .uncertain: 4][outcome] ?? -1)
    runtime.discardManualCandidate()
    replacement.invalidate(.unknownInput)
    if result == .aborted { await restoreUnchangedLayout(layout, token: token, generation: generation) }
    if result == .uncertain { quarantine(result, token: token) }
    return outcome == .noSelection ? nil : result
  }
  @MainActor private func plainPasteOperation(in token: ContextToken, clipboard: ClipboardAccess) async -> ApplyResult {
    precondition(Thread.isMainThread)
    guard ready(token) else { return .aborted }
    replacement.invalidate(.unknownInput)
    runtime.discardManualCandidate()
    let result = await selection.plainPasteAsync(in: token, clipboard: clipboard)
    quarantine(result, token: token)
    return result
  }
  @MainActor private func undoLastOperation() async -> ApplyResult {
    defer { finishReplacementLayout() }
    precondition(Thread.isMainThread)
    if runtime.manualRepeatCandidate() != nil { runtime.discardManualCandidate() }
    guard let token = editContext.current(), ready(token) else { return .aborted }
    let result = await replacement.undoLastAsync()
    quarantine(result, token: token)
    if result == .committed, let id = replacement.lastCommittedID { onCommitted(id, .undo) }
    return result
  }
}
