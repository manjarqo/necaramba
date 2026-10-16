# Necaramba B: macOS Input and Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подключить чистое ядро к реальному вводу macOS с безопасной заменой, выделением, plain paste и собственной отменой.

**Architecture:** Один InputRuntime владеет event-tap run loop и context epochs. ReplacementCoordinator исполняет только revalidated EditPlan через тестируемые адаптеры; UI получает агрегированные события, но не владеет вводом.

**Tech Stack:** Swift/AppKit, Carbon TIS/UCKeyTranslate, CoreGraphics CGEvent, optional Accessibility, XCTest, подписанный host harness.

**Spec:** [2026-10-14-necaramba-design.md](../specs/2026-10-14-necaramba-design.md)

## Global Constraints

- Flutter/Dart для UI, Swift/AppKit для нативного ядра; минимальная macOS 12.0; архитектуры arm64 и x86_64.
- Основной цикл ввода работает локально и без сети.
- Callback event tap не выполняет сеть, файловый ввод-вывод или блокирующие AX-вызовы.
- Не сохранять и не отправлять набранный текст по умолчанию.
- При неопределённом фокусе, Secure Input, IME/composition или недоступных разрешениях пропускать ввод без изменения.
- Синтетические события маркируются и не обрабатываются повторно.
- Код, идентификаторы сервисов, модели, звуки, графика и аккаунты сторонних переключателей не входят в распространяемый продукт.
- Не выпускать функцию как совместимую без соответствующего теста и результата в матрице приёмки.

---

## Структура и зависимости

A1–A6 должны пройти unit gates. B не ожидает полного production corpus для adapter harness, но real auto остаётся закрыт до A7. Изменения общего Package.swift сериализовать: B добавляет target/library NecarambaMac и testTarget NecarambaMacTests, а не переписывает package поверх A/C/D.

```
Sources/NecarambaMac/Input/{InputRuntime,InputRuntimeControl,EventTapAdapter,
  PermissionMonitor,ContextMonitor,CapabilityRegistry}.swift
Sources/NecarambaMac/Layout/TISLayoutAdapter.swift
Sources/NecarambaMac/Replacement/{ReplacementCoordinator,KeySender,
  UndoJournal,SelectionAdapter,ClipboardTransaction,AXSelectionAdapter}.swift
Tests/NecarambaMacTests/{PermissionTests,LayoutAdapterTests,RuntimeReplayTests,
  ReplacementTests,ClipboardTransactionTests,SelectionTests}.swift
App/TestHost/{TestHost.xcodeproj,AppDelegate.swift,TestWindowController.swift}
Tests/Integration/{HostScenarios.json,CompatibilityManifest.json}
Tools/ReplayRunner/main.swift
```

## Task B1: Реальный host harness и capability gates

**Consumes:** A ContextToken/InvalidationReason. **Produces:** PermissionState(listen:Bool,post:Bool,ax:Bool,secureInput:Bool); CapabilityState(auto:Bool,manual:Bool,selection:Bool,reason:String).

- [ ] RED test: отсутствие post permission возвращает capabilities false и ordinary key goes through. В fake monitor различить listen=true/post=false/ax=true; не объединять их в `accessibilityAllowed`.

```swift
func testMissingPostCannotEnableAuto() {
    let state = PermissionState(listen: true, post: false, ax: true, secureInput: false)
    XCTAssertFalse(CapabilityRegistry.evaluate(state, supportsFocus: true).auto)
}
```

- [ ] `swift test --filter PermissionTests` → RED. Реализовать PermissionMonitor на `CGPreflightListenEventAccess`, `CGPreflightPostEventAccess`, `AXIsProcessTrusted`, `IsSecureEventInputEnabled`; request APIs вызывать только из onboarding action. CapabilityRegistry не кэширует успешный ответ навечно.
- [ ] Создать подписанный TestHost с двумя NSTextView, NSSecureTextField, marked-text fixture control, кнопкой смены фокуса и output event counters. Содержимое по умолчанию только `A ghbdtn Z`. В harness event log разрешён только synthetic-text mode; вне него content logging выключен.
- [ ] Создать Xcode project/scheme TestHost, deployment12, universal; own local bundle ID `local.necaramba.testhost` до утверждения identity. Команда `xcodebuild -project App/TestHost/TestHost.xcodeproj -scheme TestHost -configuration Debug build` → BUILD SUCCEEDED.
- [ ] На отдельном тестовом профиле разрешить/отозвать TCC вручную, выполнить AC permission/Secure Input; при отсутствии стенда отметить UNRUN, не PASS. `swift test --filter PermissionTests` → PASS. Commit `test: add macOS input capability harness`.

**Результат gate:** реальная матрица listen/post/AX и focus capability. Если надёжный фокус недоступен в выбранном sandbox channel, auto для этого control запрещён; не маскировать отсутствие наблюдения таймером.

## Task B2: TIS и контекст с epoch

**Interfaces:**

```swift
public protocol LayoutAccess: AnyObject {
    func current() -> LayoutID?
    func supported() -> [LayoutID]
    func select(_ id: LayoutID) -> Bool
}
public protocol ContextAccess: AnyObject {
    func current() -> ContextToken?
    func isSafe(_ token: ContextToken) -> Bool
}
public protocol InputRuntimeControl: AnyObject {
    func updatePreferences(_ snapshot: PreferencesSnapshot)
    func invalidateContext(reason: InvalidationReason)
}
```

**Files:** TISLayoutAdapter.swift, ContextMonitor.swift, LayoutAdapterTests.swift.

- [ ] RED test fake select returns success but current remains old → failed verified switch; missing UnicodeKeyLayoutData → unsupported; epoch mismatch → no replacement.

```swift
func testSelectionRequiresReadback() {
    let access = FakeLayoutAccess(current: LayoutID(rawValue: "US"), switchesActually: false)
    XCTAssertFalse(VerifiedLayoutSwitcher(access: access, maxAttempts: 3)
        .select(LayoutID(rawValue: "RU")))
    XCTAssertEqual(access.attempts, 3)
}
```

FakeLayoutAccess local test class stores current/attempts, select increments and optionally assigns; supported returns US/RU. VerifiedLayoutSwitcher belongs TISLayoutAdapter.swift; `.select` bound by maxAttempts and injectable sleeper, never callback-blocking production method.

- [ ] `swift test --filter LayoutAdapterTests` → RED. Implement TIS list/current/select, retain/release корректно, ID properties; map physical key through UnicodeKeyLayoutData+UCKeyTranslate with explicit deadKeyState and keyboard type. Reject nil data/IME/dead-key state in auto mode. Record keyboard type and source ID for fixtures A2.
- [ ] ContextMonitor increments epoch on workspace switch, focused-element change in qualified AX control, navigation/mouse, external TIS change, secure transition, session/wake. PID comparison alone insufficient. Monitor publishes snapshots outside callback; unknown focus causes false in isSafe.
- [ ] `swift test --filter LayoutAdapterTests` → PASS; TestHost two-fields race must not edit destination field; commit `feat: verify layouts and invalidate context epochs`.

## Task B3: EventRuntime, bounded ordering и self-event filtering

**Files:** InputRuntime.swift, EventTapAdapter.swift, RuntimeReplayTests.swift, ReplayRunner.
**Consumes:** WordBuffer/GestureRecognizer/PolicyResolver; C preferences; D new rule snapshots. **Produces:** InputRuntimeControl and RuntimeOutcome(pass/suppressed/command), published count-only events.

- [ ] RED test 100000 events including own marker, repeat, app switches and timeout: actual physical sequence equals expected pass-through sequence unless a committed explicit transaction replaces its designated suffix. No duplicate/self-recursion, every incoming event gets exactly one disposition.

```swift
func testOwnEventsPassWithoutCorrection() {
    let runtime = ReplayRuntime(model: RuleSnapshot(modelVersion: 1))
    runtime.accept(fixtureEvent(origin: .ours, text: "g"))
    XCTAssertEqual(runtime.forwardedCount, 1)
    XCTAssertEqual(runtime.corrections.count, 0)
}
```

ReplayRuntime — test-only driver around production InputRuntime state machine with fake clock/context/key sink. `fixtureEvent` определяется полностью как в A3, origin аргументом.

- [ ] `swift test --filter RuntimeReplayTests` → RED. Dedicated CFRunLoop installs tap with explicit event mask for keyDown/up/flagsChanged plus required mouse invalidations; create tap may return nil. Callback validates tag, normalizes bounded event, routes pure state, returns original on all unsupported paths. No network/disk/AX wait. Gesture timeout scheduled on same executor using monotonic clock.
- [ ] Own events set `eventSourceUserData` to per-process random tag; comparison only loop-prevention. Foreign synthetic input invalidates typed buffer. Queue maximum 16 input events during applying state; if maximum reached before first destructive step, abort and release held events in original order. If after destructive step, finish only prevalidated minimal sequence or uncertain-stop; exercise both cases in replay. Do not add unbounded dispatch Tasks per key.
- [ ] Tap timeout reenable <=3/60sec; user-disabled reason → stop. Implement graceful shutdown/invalidate runloop source; repeated start idempotent.
- [ ] `swift run ReplayRunner --scenarios Tests/Integration/HostScenarios.json --events 100000` → nonzero on order/count mismatch; `swift test --filter RuntimeReplayTests` → PASS. Commit `feat: integrate ordered event runtime and gesture scheduling`.

## Task B4: Edit transactions и собственный undo

**Files:** ReplacementCoordinator.swift, KeySender.swift, UndoJournal.swift, ReplacementTests.swift.
**Interfaces:**

```swift
public struct EditPlan: Equatable, Sendable {
    public let id: UUID
    public let expected: ContextToken
    public let original: String
    public let replacement: String
    public let sourceLayout: LayoutID
    public let targetLayout: LayoutID
    public let delimiter: String
}
public enum ApplyResult: Equatable { case committed, aborted, uncertain }
public protocol KeySending: AnyObject {
    func replaceVerifiedSuffix(_ plan: EditPlan) -> ApplyResult
}
public final class ReplacementCoordinator {
    public init(context: ContextAccess, layouts: LayoutAccess, sender: KeySending)
    public func apply(_ plan: EditPlan) -> ApplyResult
    public func undoLast() -> ApplyResult
    public func invalidate(_ reason: InvalidationReason)
}
```

- [ ] RED test different context before apply → sender.called false; different context after preparation → aborted; failure after first deletion → uncertain, no speculative undo; own valid undo restores original and layout once.

```swift
func testStaleContextNeverDeletes() {
    let context = FakeContextAccess(safe: false)
    let sender = RecordingKeySender()
    let coordinator = ReplacementCoordinator(context: context,
        layouts: FakeLayoutAccess(current: LayoutID(rawValue: "US"), switchesActually: true),
        sender: sender)
    XCTAssertEqual(coordinator.apply(testPlan()), .aborted)
    XCTAssertTrue(sender.plans.isEmpty)
}
```

Define testPlan locally: UUID fixed `00000000-0000-0000-0000-000000000001`, expected pid42/test.editor epochs1, original ghbdtn, replacement привет, layouts US/RU, delimiter space. FakeContextAccess returns expected iff safe; RecordingKeySender records only invoked plans and returns injected result.

- [ ] `swift test --filter ReplacementTests` → RED. Coordinator runs serial states spec§6. Before sender: context safety/readback and verified layout selection. KeySender posts paired down/up to qualified PID using keycode sequences; Unicode insertion only for tested adapters. Preserve modifiers and trigger delimiter. No global Cmd+Z.
- [ ] UndoJournal holds one committed plan + verified after-context; clear on user text changes, focus/layout external change, mouse, secure, sleep. Undo builds inverse plan only if still valid. Mixed correction (layout+typo+ё) yields one journal entry.
- [ ] On native failure no blind retry after partial mutation; publish uncertain reason without text. TestHost injection fails between first/second backspace and user focuses second field; no text in wrong field.
- [ ] `swift test --filter ReplacementTests` → PASS; manual host AC026/030/031/037 plus layout-race cases; commit `feat: apply and undo verified text transactions`.

## Task B5: Clipboard transaction и selection conversion

**Files:** ClipboardTransaction.swift, SelectionAdapter.swift, optional AXSelectionAdapter.swift; ClipboardTransactionTests.swift, SelectionTests.swift.
**Interfaces:** PasteboardSnapshot(items:[PasteboardItem],changeCount:Int), PasteboardItem(representations:[String:Data]); `ClipboardAccess.snapshot(maxBytes:Int)throws`, `write(_ items:[PasteboardItem])throws -> Int`, `changeCount:Int`; ClipboardTransaction.restoreIfOwned() -> Bool. General NSPasteboard adapter separate from fakes.

- [ ] RED test own write then user writes → restore false and newer contents retained; lazy/unmaterializable type → abort before clearContents; no new Copy generation → selection unavailable, never use previous clipboard.

```swift
func testUserCopyWinsOverRestoration() throws {
    let pasteboard = FakeClipboard(items: [plain("before")])
    let transaction = try ClipboardTransaction(access: pasteboard, maxBytes: 16 * 1024 * 1024)
    try transaction.replace(with: [plain("temporary")])
    try pasteboard.write([plain("user-new")])
    XCTAssertFalse(transaction.restoreIfOwned())
    XCTAssertEqual(pasteboard.items, [plain("user-new")])
}
```

`plain` test helper returns PasteboardItem with `public.utf8-plain-text: Data(string.utf8)`; FakeClipboard increments count on every write. Define enum ClipboardError cases unsupportedRepresentation,tooLarge,noText,copyTimeout,contextChanged; error preview excludes actual text.

- [ ] `swift test --filter ClipboardTransactionTests` → RED. Snapshot all items/types, limits spec; transaction records count after own write, restores only exact match; every exit path cleanup conditional. No fixed one-second timer as proof of application Paste completion.
- [ ] SelectionAdapter first obtains verified selected range via qualified AX or explicit Copy command with context + count handshake (timeout500ms design parameter), then transforms only selected string. Context invalid before Paste → conditional restore and abort. AX paths fail supported/settable checks cleanly; optional API never blocks tap callback.
- [ ] Implement CmdShiftV when enabled: read plain string, no text→pass hotkey/no-content feedback, qualified insert+conditional restore; do not alter settings via recorder. AC032–036 and clipboard section matrix.
- [ ] `swift test --filter 'ClipboardTransactionTests|SelectionTests'` → PASS (if test filter regex unsupported use two commands); host verify RTF+HTML+image multi-items and concurrent user copy. Commit `feat: preserve clipboard ownership during manual text actions`.

## Task B6: Qualification, early correction и multi-editor proof

**Files:** CapabilityRegistry.swift; Tests/Integration/CompatibilityManifest.json; Reports/compatibility.json; Reports/input-performance.json.

- [ ] Add RED tests for compatibility manifest: unspecified editor/control/OS→manual-only or unavailable, not blanket supported; capability requires immutable evidence revision and test result.
- [ ] Run synthetic TestHost matrix before external editors. Then TextEdit, Safari input/textarea/contenteditable, Chromium, Electron; native autocorrect on/off; each actual layout and physical keyboard. Tests in Terminal/IDE begin auto-deny; user explicit app allow does not bypass unsupported control.
- [ ] Implement early-within-word correction only after boundary pipeline green: classifier receives each appended token and same confidence policy; pending suffix immutable epoch; future physical events retain order. Differential corpus defines allowed correction timing windows, not just final string. Add `EarlyCorrectionTests.testTypingContinuesAfterRewrite` for `ghbdtn` followed immediately by `!`; expected `привет!` with no extra/lost event.
- [ ] Replay100000, p99 tap<=2ms/classifier<=10ms32symbol, idleCPU<=0.5%5min,RSS<=100MiB без engine/<=200MiB с открытым Flutter UI (E4). Capture hardware/OS/arch/modelVersion, warmup and sample counts. Every failed requirement blocks enabling auto on that capability; do not hide failures by changing denominator.
- [ ] Verify release on actual Intel+Apple Silicon; macOS12 floor and13 ServiceManagement transition. Mark unsupported OS/editor combinations honestly.
- [ ] Commit `test: qualify input adapters and correction timing`.

## Финальная проверка B

- [ ] Core+Mac XCTest PASS; 100000-event replay PASS; manual host evidence saved with synthetic-only content.
- [ ] F01–09/F16–18 covered in integration; C UI subscribes to count/status events, not raw input.
- [ ] `InputRuntimeControl` signatures совпадают с C; D RuleSnapshotConsumer installation enqueues atomic swap at transaction boundary and invalidates only pending word, не committed unrelated UI.
- [ ] Нет автоматического «исправления» в неподдержанных password/IME/RDP contexts; нет скрытых требований Full Disk Access/Screen Recording.

Flutter boundary: InputRuntimeControl вызывается native bridge E после validation/persistence C; InputEvent/WordBuffer/clipboard никогда не пересылаются в Dart. Replay и tap работают с закрытым окном и без engine. App/TestHost остаётся отдельным native harness.
