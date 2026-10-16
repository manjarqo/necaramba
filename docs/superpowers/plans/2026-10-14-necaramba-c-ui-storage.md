# Necaramba C — UI, Storage and Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать локальные данные, настройки и Flutter-интерфейс аналога, подключаемые к input runtime через явный контракт.

**Architecture:** SQLite публикует новые данные после commit; UI не владеет состоянием клавиатуры. Main-thread контроллер передаёт immutable PreferencesSnapshot в InputRuntimeControl, lifecycle инвалидирует контекст. Flutter widgets/Cubit отображают state snapshots через bridge E; AppKit отвечает за системное меню и окно-хост.

**Tech Stack:** Flutter/Dart, flutter_bloc Cubit, Swift, AppKit, SQLite/libsqlite3, UserDefaults, AVFoundation, ServiceManagement, XCTest, macOS 12+, Universal 2.

**Spec:** [2026-10-14-necaramba-design.md](../specs/2026-10-14-necaramba-design.md).

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

## Исполнение и владение

Это план для ревью; реализация и команды не выполнялись. Worktree создаётся при исполнении через using-git-worktrees. Ты не один в workspace: не отменять чужие изменения. Ownership C — только перечисленные файлы. Изменения Package.swift и Xcode project передавать интегратору, единственному владельцу scaffolding; не редактировать параллельно.

A предоставляет package products NecarambaCore/NecarambaMac, test targets NecarambaCoreTests/NecarambaMacTests; интегратор E — App/macos/Runner.xcworkspace, scheme Runner и native test targets. B предоставляет InputRuntimeControl. Начать после принятия этих контрактов; если scaffold отсутствует, его владелец сначала создаёт targets, затем выполняются приведённые test commands. Swift snippets ниже помещаются в названные test files; каждый импортирует XCTest и `@testable import NecarambaCore` / `@testable import NecarambaMac` по необходимости.

Native presentation models — MainActor, Flutter widgets/Cubit — Dart main isolate. SQLiteStore queue-confined, имеет собственный serial writer; UI выполняет дисковые вызовы вне main thread. Настоящие TCC/login настройки не меняются unit tests. Host tests — отдельный synthetic профиль. Не открывать хранилища других переключателей и не мигрировать личные данные пользователя.

## Общий контракт

Из A импортируются LayoutID, InputEvent, ContextToken(pid,bundleID,focusEpoch,layoutEpoch), PreferencesSnapshot. Последний — Sendable/Equatable, immutable lets: autoEnabled, typoEnabled, yoEnabled, singleShiftEnabled, optionEnabled, splitShiftEnabled, plainPasteEnabled, soundEnabled; public initializer с default arguments и static defaults. C не переопределяет типы.

Из A также импортируется InvalidationReason: focusChanged, layoutChanged, secureInput, permissionRevoked, mouseNavigation, unknownInput, sleep, sessionLock. Контракт B:

```swift
protocol InputRuntimeControl {
    func updatePreferences(_ snapshot: PreferencesSnapshot)
    func invalidateContext(reason: InvalidationReason)
}
```

Реализация B сериализует команды на runtime executor. Wake/unlock инвалидируются как unknownInput; external layout как layoutChanged. UI не ожидает исполнения команды в callback. Правила слов/приложений публикуются интегратором в immutable RuleSnapshot A после storage commit; B не читает SQLite.

## Карта файлов

| Новые файлы | Ответственность |
|---|---|
| Sources/NecarambaCore/Storage/RuleRecords.swift, WordRuleStore.swift, AppRuleStore.swift | Immutable DTO и протоколы |
| Sources/NecarambaMac/Storage/SQLiteStore.swift, SQLiteMigrations.swift, RuleArchive.swift | Локальная БД, миграции, собственный export/import |
| Sources/NecarambaMac/Preferences/PreferencesController.swift | Preferences persistence и publication |
| Sources/NecarambaMac/UI/RulesEditorModel.swift, App/lib/features/exceptions/exceptions_page.dart | Слова/программы и validation feedback |
| Sources/NecarambaMac/UI/StatusPresentation.swift, StatusItemController.swift, App/lib/features/onboarding/onboarding_page.dart, DiagnosticsExporter.swift | Меню, настройки, разрешения, redacted diagnostics |
| Sources/NecarambaMac/Appearance/SoundStore.swift, HeaderPalette.swift, HeaderImageStore.swift, StatisticsStore.swift | Собственные sounds/colors, drag/drop header image, агрегаты |
| Sources/NecarambaMac/Lifecycle/LoginController.swift, SystemLoginBackend.swift, LifecycleController.swift | Login и invalidation |
| App/macos/Runner/AppDelegate.swift, App/lib/l10n/app_en.arb, App/lib/l10n/app_ru.arb, App/macos/Runner/Resources/Sounds/correction.aiff, App/macos/Runner/Assets.xcassets | Composition root и собственные ресурсы |
| App/NecarambaLoginHelper/main.swift, Info.plist | macOS12 bundled helper |
| Tests/NecarambaCoreTests/RuleValidationTests.swift | Pure validation |
| Tests/NecarambaMacTests/SQLiteStoreTests.swift, PreferencesControllerTests.swift, RulesEditorModelTests.swift, StatusPresentationTests.swift, AppearanceStatisticsTests.swift, LifecycleControllerTests.swift | Поведенческие проверки |
| App/integration_test/settings_flow_test.dart | Flutter macOS UI synthetic harness |

## Task 1: SQLite, миграции и атомарный import/export

**Files:** Create перечисленные Storage files, RuleValidationTests.swift, SQLiteStoreTests.swift.

**Interfaces:** Produces следующие публичные контракты; SQLiteStore реализует оба store protocols, `init(url: URL) throws`, `exportArchive() throws -> Data`, `importArchive(_ data: Data) throws`.

```swift
struct WordRule: Codable, Equatable, Sendable {
    let id: UUID; let normalized: String; let original: String
    let createdAt: Int64; let shareOptIn: Bool
}
enum AppRuleMode: String, Codable, Sendable { case allow, deny }
struct AppRule: Codable, Equatable, Sendable {
    let bundleID: String; let displayName: String; let bookmark: Data?
    let mode: AppRuleMode; let updatedAt: Int64
}
protocol WordRuleStore {
    func words() throws -> [WordRule]
    func addWord(_ text: String, at: Int64) throws -> WordRule
    func deleteWord(id: UUID) throws
    func clearWords() throws
}
protocol AppRuleStore {
    func apps() throws -> [AppRule]
    func setApp(_ rule: AppRule) throws
    func deleteApp(bundleID: String) throws
}
enum StoreError: Error {
    case invalidWord, duplicateWord, invalidArchive, unsupportedSchema
    case databaseFailure(Int32), failedIntegrityCheck
}
struct RuleArchiveV1: Codable {
    let schemaVersion: Int
    let words: [WordRule]
    let legacyWords: [WordRule]
    let apps: [AppRule]
}
```

Archive v1 содержит собственные rules, не чужую БД; export обязательно включает legacyWords целиком, decoder старого own archive без legacyWords принимает пустой массив. Legacy values из прежнего words распределяются по длине после полной валидации. Preferences экспортируются отдельно через Task2 с envelope version; интеграционный export объединяет две части после валидации. Import rules отклоняет конфликт существующего normalized/bundleID до записи; silent merge отсутствует. Legacy own archive words 21–100 graphemes сохраняются целиком отдельной категорией/таблицей `legacy_word_rules` и не обрезаются; их нельзя превратить в обычную UI-запись без явного редактирования. A получает их отдельным legacy exclusions set.

- [ ] **Step 1: Написать RED тест атомарного отказа.**

```swift
final class SQLiteStoreTests: XCTestCase {
    func testInvalidImportKeepsExistingRule() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SQLiteStore(url: dir.appendingPathComponent("rules.sqlite"))
        _ = try store.addWord("превет", at: 1)
        XCTAssertThrowsError(try store.importArchive(Data(#"{"schemaVersion":1,"words":[{}]}"#.utf8)))
        XCTAssertEqual(try store.words().map(\.original), ["превет"])
        let reopened = try SQLiteStore(url: dir.appendingPathComponent("rules.sqlite"))
        XCTAssertEqual(try reopened.words().map(\.original), ["превет"])
    }
}
```

- [ ] **Step 2: Запустить RED.** `swift test --filter SQLiteStoreTests.testInvalidImportKeepsExistingRule`; ожидается `SQLiteStore` missing. После skeleton test должен достигнуть поведенческого FAIL, если import очищает данные до проверки.
- [ ] **Step 3: Реализовать schema, prepared statements и validation.** Все значения — `sqlite3_bind_*`, statements finalize на всех путях. Sorting words по normalized/id, apps по bundleID. UI validation: trim/NFC, 1–20 graphemes, reject NUL/control, `=`, `%`, no-letter tokens containing digits; normalized uniqueness. Case-fold policy едина с A.

```sql
PRAGMA foreign_keys=ON;
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS app_rules(bundle_id TEXT PRIMARY KEY, display_name TEXT NOT NULL, bookmark BLOB, mode TEXT CHECK(mode IN ('allow','deny')) NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS daily_counters(day TEXT, kind TEXT, count INTEGER CHECK(count>=0), PRIMARY KEY(day,kind));
CREATE TABLE IF NOT EXISTS model_state(slot TEXT PRIMARY KEY, version INTEGER NOT NULL, digest TEXT NOT NULL, installed_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS legacy_word_rules(id TEXT PRIMARY KEY, normalized TEXT UNIQUE NOT NULL, original TEXT NOT NULL, created_at INTEGER NOT NULL, share_opt_in INTEGER NOT NULL DEFAULT 0);
```

- [ ] **Step 4: Реализовать transaction/backup/archive.** SQLite backup API создаёт backup целой открытой БД, включая WAL; перед migration выполнить integrity_check. Newer schema/corrupt DB не заменять пустой. Import сначала полностью JSONDecoder+validation, затем BEGIN IMMEDIATE→prepared inserts→COMMIT; throw→ROLLBACK. Слово длиной101 отвергает весь архив, длиной21–100 идёт в legacy table, byte-for-byte original сохраняется. Никакого SQL из JSON.

```swift
// Private SQLiteStore helper with the exact transaction boundary:
func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do { let result = try body(); try execute("COMMIT"); return result }
    catch { try? execute("ROLLBACK"); throw error }
}
// execute(_ sql: String) throws wraps sqlite3_exec for static schema/control SQL only.
```

- [ ] **Step 5: GREEN и rollback fixture.** Добавить тесты reopen, valid archive roundtrip, duplicate normalized, 20/21-grapheme UI boundary и 100/101 legacy boundary. Migration fixture v0 содержит старую word_rules; test-injected migration `SELECT missing_column FROM word_rules` обязан оставить старые rows и version. `swift test --filter SQLiteStoreTests` и `swift test --filter RuleValidationTests`: PASS, AC038–041/048–052. Не называть exception compatibility доказанной до Unicode differential cases.
- [ ] **Step 6: Commit после GREEN.**

```bash
git add Sources/NecarambaCore/Storage Sources/NecarambaMac/Storage Tests/NecarambaCoreTests/RuleValidationTests.swift Tests/NecarambaMacTests/SQLiteStoreTests.swift
git commit -m "feat(storage): add transactional local rules and archive migration"
```

## Task 2: Immutable preferences и публикация в runtime

**Files:** Create PreferencesController.swift, PreferencesControllerTests.swift. Modify RuleArchive.swift для собственного full-export envelope.

**Interfaces:** `@MainActor PreferencesController.init(defaults: UserDefaults, publish: @escaping (PreferencesSnapshot) -> Void)`, `private(set) var snapshot: PreferencesSnapshot`, `setAuto(_ value: Bool) throws`, `replace(_ value: PreferencesSnapshot) throws`. Snapshot A остаётся immutable; Codable DTO `StoredPreferencesV1` определён внутри C с восемью bool и служебными полями selectedColor:Int, loginPreferred:Bool, diagnosticsOptIn:Bool; ручное преобразование в snapshot. Runtime ephemeral state не сериализуется. UI defaults auto=false до quality gate, остальные значения берутся из согласованных A defaults; это собственный дизайн, не defaults другого продукта.

- [ ] **Step 1: RED тест publication после сохранения.**

```swift
@MainActor final class PreferencesControllerTests: XCTestCase {
    func testOnePublicationAndPersistentValue() throws {
        let suite = "NecarambaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var delivered: [PreferencesSnapshot] = []
        let controller = PreferencesController(defaults: defaults) { delivered.append($0) }
        try controller.setAuto(true)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(try XCTUnwrap(delivered.first).autoEnabled)
        XCTAssertTrue(PreferencesController(defaults: defaults) { _ in }.snapshot.autoEnabled)
    }
}
```

- [ ] **Step 2: Запустить** `swift test --filter PreferencesControllerTests`; RED unknown controller.
- [ ] **Step 3: Реализовать copy→encode→persist→publish.** `StoredPreferencesV1(snapshot:)` и `.snapshot` определяются в этом файле; corruption defaults даёт safe defaults+redacted warning, не crash. `setAuto` строит новый snapshot, явно сохраняя семь остальных полей.

```swift
func replace(_ value: PreferencesSnapshot) throws {
    let bytes = try JSONEncoder().encode(StoredPreferencesV1(snapshot: value))
    defaults.set(bytes, forKey: "preferences.v1")
    snapshot = value
    publish(value)
}
// Composition root:
// PreferencesController(defaults: ownDefaults) { runtime.updatePreferences($0) }
```

- [ ] **Step 4: GREEN archive integration.** Full export envelope `version=1,rules:RuleArchiveV1,preferences:StoredPreferencesV1` исключает secrets. Import предварительно валидирует обе части; SQLite rule transaction commit затем preferences publication, а recovery journal сохраняет old/new encoded settings до commit и восстанавливает завершённость после interruption. Не обещать общую ACID transaction SQLite+UserDefaults без journal. Test interruption before/after DB commit: restart завершает соответствующую целую версию, никогда silent mixed profile. `swift test --filter PreferencesControllerTests` и `swift test --filter SQLiteStoreTests`: PASS. B integration spy получает одну полную updatePreferences; pending edit при auto=false инвалидируется B до следующего события (AC046/049).
- [ ] **Step 5: Commit.**

```bash
git add Sources/NecarambaMac/Preferences Sources/NecarambaMac/Storage/RuleArchive.swift Tests/NecarambaMacTests/PreferencesControllerTests.swift
git commit -m "feat(preferences): publish immutable persisted settings"
```

## Task 3: Flutter word/app exceptions

**Files:** Create `App/lib/features/exceptions/exceptions_page.dart`, `exceptions_cubit.dart`, `App/test/features/exceptions_test.dart`, `App/integration_test/settings_flow_test.dart`, `App/lib/l10n/app_ru.arb`, `app_en.arb`; native `Sources/NecarambaMac/UI/RulesEditorModel.swift` и `Tests/NecarambaMacTests/RulesEditorModelTests.swift`.

**Interfaces:** E `NativeRepository.command(method, arguments)` и `states`; native model вызывает WordRuleStore/AppRuleStore на DB queue. Dart владеет только draft/error/busy, подтверждённые rows получает из snapshot. Commands `addWord`, `deleteWord`, `clearWords`, `chooseApp`, `setAppMode`, `deleteApp` имеют контракт E. `.app` выбирается NSOpenPanel; bundle ID проверяет Swift. Native storage validation остаётся единственным источником истины.

- [ ] RED: `flutter test test/features/exceptions_test.dart` из App. Fake repository считает вызовы `clearWords`; Cancel должен оставить0 и строки прежними. Save invalid/duplicate показывает typed error и сохраняет draft. Код behavioral assertion:

```dart
testWidgets('Cancel does not clear exceptions', (tester) async {
  final repository = FakeNativeRepository.withWords(['превет']);
  await tester.pumpWidget(TestApp(repository: repository));
  await tester.tap(find.byKey(const Key('clearWords')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('cancelClear')));
  await tester.pumpAndSettle();
  expect(repository.calls.where((c) => c.method == 'clearWords'), isEmpty);
  expect(find.text('превет'), findsOneWidget);
});
```

`FakeNativeRepository` реализует контракт E, держит список `NativeCall(method,arguments)` и начальный NativeState; `TestApp` создаёт MaterialApp с локализацией, RepositoryProvider и ExceptionsPage. Все эти test helpers находятся в `App/test/support/native_fakes.dart`.
- [ ] GREEN: ExceptionsCubit хранит draft отдельно от snapshot. Перед delete-all показать Flutter AlertDialog; только Confirm отправляет command. Две вкладки words/apps, Key IDs `wordRulesTable`, `appRulesTable`, `addWord`, `clearWords`, `cancelClear`. Save/Cancel sheets, inline errors, busy disable duplicate submission, keyboard focus order и Semantics boolean values. Legacy21–100 показывать полностью с пометкой; не truncation при сохранении.
- [ ] Проверить reopen persistence через native temporary store; одинаковый displayName с разными bundle IDs остаётся двумя строками. Native errors invalidWord/duplicateWord не теряются на bridge. `swift test --filter RulesEditorModelTests` и Flutter widget tests должны PASS.
- [ ] Host integration: `flutter test integration_test/settings_flow_test.dart -d macos` из App, synthetic profile в отдельном temp store; real profile никогда не очищается. RU/EN, VoiceOver и keyboard-only проход проверяются отдельно на macOS. Commit `feat(ui): add Flutter exceptions editor` после GREEN.

## Task 4: Native status menu, Flutter settings/onboarding/diagnostics

**Files:** Native `Sources/NecarambaMac/UI/StatusPresentation.swift`, `StatusItemController.swift`, `DiagnosticsExporter.swift`; `App/lib/features/settings/settings_page.dart`, `settings_cubit.dart`, `App/lib/features/onboarding/onboarding_page.dart`, `App/lib/features/diagnostics/diagnostics_page.dart`; `App/test/features/settings_test.dart`; native StatusPresentationTests. Window/engine host принадлежит E.

**Interfaces:** `CapabilityState(listen:Bool,post:Bool,axTrusted:Bool,secureInput:Bool)` от B; `StatusKind` active/off/permissionRequired/secureInput/licensingBlocked/updateAvailable; `StatusPresentation.resolve(autoEnabled:capabilities:licenseAllowed:updateAvailable:)`. Native DTO переводится в E NativeState. DiagnosticsReport Codable: appVersion/osVersion/architecture/modelVersion:String, reasonCodes:[String], counters:[String:Int], latencySummary:[String:Double]. DiagnosticsExporter.encode throws Data; export только по явной команде.

- [ ] RED native priority test:

```swift
func testPermissionWinsOverUpdate() {
    let state = CapabilityState(listen:false, post:false, axTrusted:false, secureInput:false)
    XCTAssertEqual(StatusPresentation.resolve(autoEnabled:true, capabilities:state,
        licenseAllowed:true, updateAvailable:true), .permissionRequired)
}
```

- [ ] GREEN native priority secureInput→permission→license→off→update→active. AX false само по себе не блокирует adapter без AX. Один NSStatusItem, действия native toggle/quit/open settings; runtime работает до открытия Flutter. Flutter switches F01–09 читают confirmed snapshot, отправляют patch и показывают pending до ack; error возвращает confirmed value.
- [ ] Flutter SettingsPage содержит явные boolean semantics, own help/privacy/support URL из D, freshness/version/offline и manual check throttle30s. Onboarding вызывает `requestPermission(kind)` только по нажатию; app activation обновляет native capability truth. FDA/Screen Recording не запрашивать; Secure Input не отключать. Share preview/paywall отображаются Flutter, действия исполняет D через E.
- [ ] RED/GREEN widget test: inject denied capability snapshot, `expect(find.byKey(const Key('permissionRequired')), findsOneWidget)`; разрешённый snapshot заменяет warning; switch pending/error не расходится с native menu. Тест fake stream disconnect показывает reconnecting и запрещает запись до resync.
- [ ] Privacy test пропускает `PRIVATE_FIXTURE_9821` через B и проверяет отсутствие строки в bridge events и DiagnosticsExporter.encode. `swift test --filter StatusPresentationTests`, `flutter test test/features/settings_test.dart`, host integration AC063–066/070–074. Permission fake не заменяет host TCC test. Commit `feat(ui): connect Flutter settings to native status and permissions` после GREEN.

## Task 5: Managed sound, палитра, картинка шапки и статистика

**Files:** Create SoundStore.swift, HeaderPalette.swift, HeaderImageStore.swift, StatisticsStore.swift, AppearanceStatisticsTests.swift, Resources/Sounds/correction.aiff и README происхождения собственного sound. Modify App/lib/features/settings/settings_page.dart и ARB.

**Interfaces:** `SoundStore.init(directory:URL)`, `importSound(from:URL) throws -> URL`, `reset() throws`, `playCorrection()`; playback вне input executor. `HeaderPalette.colors:[UInt32]`, 25 RGB, default index0. `CounterKind:String` cases layout/typo/doubleCaps/yo/manual/undo; `StatisticsStore.init(database:SQLiteStore)`, `recordCommitted(id:UUID,kind:CounterKind,day:String) throws`, `count(kind:day:) throws -> Int`, `reset() throws`. Own time weightsVersion1: layout/manual=1s, typo/doubleCaps/yo=2s, undo=0s; это открытая проектная оценка, не timing другого продукта. UI показывает «оценка» и формулу.

- [ ] **Step 1: RED duplicate event.**

```swift
final class AppearanceStatisticsTests: XCTestCase {
    func testCommittedEventCountsOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let stats = StatisticsStore(database:try SQLiteStore(url:dir.appendingPathComponent("rules.sqlite")))
        let id = UUID()
        try stats.recordCommitted(id:id,kind:.layout,day:"2026-10-14")
        try stats.recordCommitted(id:id,kind:.layout,day:"2026-10-14")
        XCTAssertEqual(try stats.count(kind:.layout,day:"2026-10-14"),1)
    }
}
```

- [ ] **Step 2: Запустить** `swift test --filter AppearanceStatisticsTests`; RED missing store.
- [ ] **Step 3: Реализовать committed-only counters и sound import.** In-memory eventID set добавляет ID после успешной DB записи; aborted/replayed events не передаются. Publisher B гарантирует one delivery, set ограничен bounded window (например последние1024 IDs), не растёт бесконечно; duplicate за пределами окна исключается producer contract, не выдуманной exactly-once гарантией.

```sql
INSERT INTO daily_counters(day,kind,count) VALUES(?,?,1)
ON CONFLICT(day,kind) DO UPDATE SET count=count+1;
```

Sound: size≤5MiB, AVAudioFile decode success, duration≤10sec; copy в managed temp, atomic rename. Ошибка сохраняет прежний sound. Security-scoped URL закрывается после копирования. sound=false не enqueue playback; каждое committed действие играет максимум один звук.
- [ ] **Step 4: Палитра и GREEN.**

```swift
let colors:[UInt32] = [0x1D3557,0x264653,0x2A9D8F,0x457B9D,0x577590,
  0x277DA1,0x4D908E,0x43AA8B,0x90BE6D,0x6A994E,0x386641,0x8D99AE,
  0x6D6875,0xB5838D,0xE5989B,0xAF5170,0x8E4162,0x7B2CBF,0x5A189A,
  0x3C096C,0x9C6644,0xB08968,0xBC6C25,0xD4A373,0x555B6E]
```

Reset выбирает index0; foreground выбирается по luminance и проверяется contrast. Header image drag/drop и remove — обязательные функции F14: статически подтверждены drag TIFF/FileURL→NSImage, сохранение TIFF и removeHeaderImage в исходном UI framework. Новый продукт хранит собственный файл в managed Application Support, а не большие image bytes в defaults. `HeaderImageStore.init(directory:URL) throws`, `importImage(data:Data) throws`, `importImage(from:URL) throws`, `loadImageData() throws -> Data?`, `remove() throws`. Design bounds: вход ≤10MiB, width/height≤8192, total decoded pixels≤16_000_000; inspect ImageIO metadata до полного decode, reject corrupt/oversized без замены прежнего файла. ImageIO читает только первый кадр, ориентация применяется при rasterization. Drop поддерживает TIFF data и local file URL через NSDraggingDestination; network URL не скачивается. Security-scoped доступ закрывается после чтения; temp→atomic rename сохраняет PNG/TIFF собственного изображения. Контекстное меню Remove и settings reset вызывают remove; отсутствие картинки показывает выбранную palette header. Перезапуск load восстанавливает картинку. Тесты 25 цветов/reset, corrupt/oversized/overduration sound сохраняет old file, estimate formula, counters reset не удаляет rules; image persistence/invalid-image preservation/remove проверяются следующим тестом; `swift test --filter AppearanceStatisticsTests`: PASS (AC065/067–069). Share-rule preview показывает только слово/язык/modelVersion/optional feedback; injected D send closure вызывается только после отдельного подтверждения, Cancel=0 calls, offline без backend не ломает local input (AC070). Сеть принадлежит D.
- [ ] **Step 4b: RED/GREEN картинки шапки.** Перед реализацией HeaderImageStore выполнить `swift test --filter AppearanceStatisticsTests.testHeaderImagePersistsRejectsInvalidAndRemoves`: ожидается missing type; после реализации PASS. Добавить в AppearanceStatisticsTests, импортировать AppKit:

```swift
func testHeaderImagePersistsRejectsInvalidAndRemoves() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:dir) }
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,
        pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,
        hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
    let source = try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    let store = try HeaderImageStore(directory:dir)
    try store.importImage(data:source)
    let stored = try XCTUnwrap(store.loadImageData())
    let reopened = try HeaderImageStore(directory:dir)
    XCTAssertEqual(try reopened.loadImageData(),stored)
    XCTAssertThrowsError(try reopened.importImage(data:Data("not an image".utf8)))
    XCTAssertEqual(try reopened.loadImageData(),stored)
    try reopened.remove()
    XCTAssertNil(try reopened.loadImageData())
}
```

Host/UI gate: TIFF pasteboard drag и local FileURL drag устанавливают видимую картинку; invalid image/over-limit pixels оставляют прежнюю; контекстное Remove и reset возвращают palette header; после restart картинка/удаление сохранены. Drop/hover не заменяет картинку до успешного decode и atomic commit. Никакие сторонние изображения/assets не копируются в приложение.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NecarambaMac/Appearance App/lib/features/settings/settings_page.dart Tests/NecarambaMacTests/AppearanceStatisticsTests.swift App/macos/Runner/Resources
git commit -m "feat(appearance): add managed sounds colors and aggregate counters"
```

## Task 6: Login item и lifecycle invalidation

**Files:** Create LoginController.swift, SystemLoginBackend.swift, LifecycleController.swift, LifecycleControllerTests.swift, App/NecarambaLoginHelper/main.swift/Info.plist. Modify login section App/lib/features/settings/settings_page.dart; AppDelegate integration передать E. Helper target embedding patch передать владельцу Xcode project.

**Interfaces:**

```swift
enum LoginStatus:Equatable { case enabled, disabled, requiresApproval, unavailable }
protocol LoginBackend {
    func status() -> LoginStatus
    func setEnabled(_ value:Bool) throws
}
@MainActor final class LoginController {
    let backend:LoginBackend
    private(set) var status:LoginStatus
    init(backend:LoginBackend) { self.backend=backend; self.status=backend.status() }
    func setEnabled(_ value:Bool) throws {
        defer { status=backend.status() }
        try backend.setEnabled(value)
    }
}
// LifecycleController.init(runtime:InputRuntimeControl)
// handle(_ reason:InvalidationReason), start(), stop().
// start/stop controls observers; handle forwards once to runtime.
```

Runtime serial executor принимает command, callback не ждёт keyboard drain. Consume A reasons: sleep→sleep; lock→sessionLock; wake/unlock→unknownInput; NSWorkspace activation→focusChanged; TIS external change→layoutChanged. B owns physical focus/secure/tap monitoring, C не устанавливает второй tap или duplicate layout observer; интегратор подключает ровно одного владельца notification source.

- [ ] **Step 1: RED для отказа системы.**

```swift
final class DeniedLoginBackend:LoginBackend {
    func status()->LoginStatus { .requiresApproval }
    func setEnabled(_ value:Bool) throws { }
}
final class RuntimeSpy:InputRuntimeControl {
    var invalidations:[InvalidationReason]=[]
    func updatePreferences(_ snapshot:PreferencesSnapshot) { }
    func invalidateContext(reason:InvalidationReason) { invalidations.append(reason) }
}
@MainActor final class LifecycleControllerTests:XCTestCase {
    func testRegisterDoesNotPretendApproval() throws {
        let controller=LoginController(backend:DeniedLoginBackend())
        try controller.setEnabled(true)
        XCTAssertEqual(controller.status,.requiresApproval)
    }
    func testSleepInvalidatesOnce() {
        let runtime=RuntimeSpy()
        let controller=LifecycleController(runtime:runtime)
        controller.handle(.sleep)
        XCTAssertEqual(runtime.invalidations.count,1)
    }
}
```

- [ ] **Step 2: Запустить** `swift test --filter LifecycleControllerTests`; RED missing controllers.
- [ ] **Step 3: Реализовать OS-selected backend.**

```swift
if #available(macOS 13.0, *) {
    if enabled { try SMAppService.mainApp.register() }
    else { try SMAppService.mainApp.unregister() }
} else {
    guard SMLoginItemSetEnabled(helperBundleID as CFString,enabled) else {
        throw LoginError.changeRejected
    }
}
// Define enum LoginError:Error { case changeRejected }.
// helperBundleID = own main bundle identifier + ".LoginHelper".
```

13+ status читается из SMAppService; успешный register не заменяет approval. 12 helper в Contents/Library/LoginItems, LSUIElement=true, запускает enclosing main app через NSWorkspace и завершается. Helper не root daemon. Проверить known bundle nesting и enclosing bundleID, не исполнять произвольный URL. Legacy setter success хранится как preference, но не выдаётся за modern status-query; `.unavailable` с пояснением допустим, фактический launch подтверждается host тестом. При переходе на13 отключить legacy helper перед mainApp registration, ошибку показать. Не открывать App Store/не делать purchase ради login test.
- [ ] **Step 4: Подключить observers и GREEN.**

```swift
func handle(_ reason:InvalidationReason) {
    runtime.invalidateContext(reason:reason)
}
// start(): if started return; retain every observer token; set started=true.
// stop(): remove each token from its originating NotificationCenter;
// clear tokens; set started=false. No new callback after stop.
```

Добавить fake notification source тест: start→start→sleep даёт1 call; stop→sleep даёт0 дополнительных; restart→sleep снова1. `swift test --filter LifecycleControllerTests`: PASS. Buffer/undo reset проверяет B, C доказывает доставку причины ровно один раз. AppDelegate wiring использует retained runtime, не создаёт его при каждом открытии окна.
- [ ] **Step 5: Host gate и полный GREEN C.** Выполнить `swift test` и `xcodebuild test -workspace App/macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS'`. Ожидается PASS C tests, без изменения текущих TCC/login. В отдельной среде macOS12/13+: enable→logout/login=1 instance, disable→login=0 auto instances; denial корректен, sleep/wake/lock/unlock не переносят старый buffer. Native Intel и arm64 обязательны; Rosetta не закрывает Intel gate. Unrun host сценарии остаются unrun, не PASS (AC063/084/093–094).
- [ ] **Step 6: Commit.**

```bash
git add Sources/NecarambaMac/Lifecycle Tests/NecarambaMacTests/LifecycleControllerTests.swift App/NecarambaLoginHelper App/lib/features/settings/settings_page.dart
git commit -m "feat(lifecycle): add login item and context invalidation wiring"
```

## Coverage и handoff

Task1: F10/F11 storage, AC038–052. Task2: настройки F01–09, AC046/049. Task3: F10/F11/F21, AC038–045/066. Task4: F16/F17/F19/F21, AC063–066/070–074. Task5: F13–15, F22 preview, AC065/067–070. Task6: F18/lifecycle, AC063/084/093–094. A/B владеют linguistic engine/gestures/replacement/clipboard; D владеет model network/share backend/licensing/distribution. F20 settings presentation потребляет D LicensingAdapter, C не делает второй receipt verifier.

Performance gates spec применяются к интеграции: tap p99≤2ms, classifier p99≤10ms/32-symbol, idle≤0,5%/5min, RSS≤100MiB без engine, ≤200MiB с открытым Flutter UI (проектные бюджеты E4); idle UI не поллит, счётчики/sound/SQLite никогда не выполняются в tap. Отдельный результат нужен на каждой архитектуре. User text не попадает в SQLite counters, diagnostics, export, defaults.

Self-review: public signatures совпадают с A/B, code snippets называют определённые types; storage import all-or-nothing, legacy100 не truncates; UI limit20 отличается от regex counting только явно проверяемым Unicode gate; assets собственные; no cloud sync, hidden auto-learning, recorder/uppercase. Commit commands — инструкции будущего исполнения. Failed/unrun host gates остаются видимыми; обязательный header-image drag/drop/remove имеет собственные persistence/rejection/reset tests. Исполнение данного плана начинается только отдельным поручением после ревью.
