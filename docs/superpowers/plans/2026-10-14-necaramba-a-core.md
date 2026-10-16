# Necaramba A: Core and Language Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Построить независимое детерминированное ядро раскладок, языка, политик и жестов с воспроизводимыми тестами.

**Architecture:** Pure Swift package не зависит от AppKit и сети. Immutable snapshots поступают в classifier и policy resolver; результат — решение, которое исполняется только системным runtime из плана B.

**Tech Stack:** Swift tools 5.9, Swift 6 compiler в Swift 5 language mode, Foundation, XCTest, macOS 12.0.

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

## Порядок и файлы

Пустой workspace пока содержит только исследование и документы. Не считать research scripts продуктовым кодом. На этапе реализации создать git repository/ветку по выбранному пользователем workflow; в этот план входит код будущего продукта, а не импорт декомпиляции.

```
Package.swift
Sources/NecarambaCore/Types/{InputTypes,RuleTypes,PreferencesSnapshot}.swift
Sources/NecarambaCore/Layout/LayoutConverter.swift
Sources/NecarambaCore/Input/{WordBuffer,GestureRecognizer}.swift
Sources/NecarambaCore/Language/{LinguisticEngine,TokenGuard,RuleIndex}.swift
Sources/NecarambaCore/Policy/PolicyResolver.swift
Tests/NecarambaCoreTests/{ContractTests,LayoutConverterTests,WordBufferTests,
  LinguisticEngineTests,PolicyResolverTests,GestureRecognizerTests}.swift
Tests/NecarambaCoreTests/Fixtures/RulesV1.json
Tools/CorpusRunner/main.swift
Corpora/{README.md,manifest.json,calibration.jsonl,holdout.jsonl}
```

Каждая Task ниже заканчивается тестируемым результатом. Сначала выполнить показанный RED test, затем реализацию, затем GREEN; примеры правил синтетические. Их прохождение не заменяет production corpus gate.

## Task A1: Package и общие value contracts

**Files:** create Package.swift; три Types файла; ContractTests.swift. **Produces:** нижеуказанные публичные типы для B/C/D.

- [ ] Написать ContractTests до production файлов:

```swift
import XCTest
@testable import NecarambaCore
final class ContractTests: XCTestCase {
    func testDefaultsAndSnapshotRoundTrip() throws {
        XCTAssertTrue(PreferencesSnapshot.defaults.autoEnabled)
        XCTAssertFalse(PreferencesSnapshot.defaults.optionEnabled)
        let model = RuleSnapshot(modelVersion: 7)
        XCTAssertEqual(try JSONDecoder().decode(RuleSnapshot.self,
            from: JSONEncoder().encode(model)), model)
        XCTAssertNotEqual(LayoutID(rawValue: "com.apple.keylayout.Russian"),
                          LayoutID(rawValue: "com.apple.keylayout.RussianWin"))
    }
}
```

- [ ] `swift test --filter ContractTests` → RED: module/type отсутствует. Создать package:

```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Necaramba", platforms: [.macOS(.v12)],
 products: [.library(name: "NecarambaCore", targets: ["NecarambaCore"])],
 targets: [.target(name: "NecarambaCore"),
           .testTarget(name: "NecarambaCoreTests", dependencies: ["NecarambaCore"],
                       resources: [.copy("Fixtures")])],
 swiftLanguageVersions: [.v5])
```

- [ ] Реализовать типы по единому контракту; все public structs получают явный public initializer. Codable/Equatable синтезируются, где заявлены:

```swift
public struct LayoutID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
public enum Language: String, Codable, Sendable { case english, russian }
public enum Modifier: String, Codable, Hashable, Sendable {
    case shift, option, command, control, capsLock, function
}
public enum EventKind: String, Codable, Sendable { case down, up, flagsChanged }
public enum EventOrigin: String, Codable, Sendable { case physical, ours, foreignSynthetic, unknown }
public struct ContextToken: Codable, Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let focusEpoch: UInt64
    public let layoutEpoch: UInt64
}
public enum InvalidationReason: String, Codable, Sendable {
    case focusChanged, layoutChanged, secureInput, permissionRevoked
    case mouseNavigation, unknownInput, sleep, sessionLock
}
public struct InputEvent: Sendable, Equatable {
    public let kind: EventKind
    public let keyCode: UInt16
    public let modifiers: Set<Modifier>
    public let timestampNanos: UInt64
    public let layout: LayoutID
    public let context: ContextToken
    public let origin: EventOrigin
    public let text: String?
    public let isRepeat: Bool
}
public struct Lexeme: Codable, Equatable, Sendable {
    public let word: String
    public let language: Language
    public let frequencyBand: UInt8
}
public struct ReplacementRule: Codable, Equatable, Sendable {
    public let source: String
    public let target: String
    public let caseSensitive: Bool
}
public struct LayoutMapping: Codable, Equatable, Sendable {
    public let source: LayoutID
    public let target: LayoutID
    public let pairs: [String: String]
}
public struct RuleSnapshot: Codable, Equatable, Sendable {
    public let modelVersion: UInt64
    public let lexicon: [Lexeme]
    public let typos: [ReplacementRule]
    public let yoRules: [ReplacementRule]
    public let protectedTokens: Set<String>
    public let mappings: [LayoutMapping]
    public init(modelVersion: UInt64, lexicon: [Lexeme] = [],
                typos: [ReplacementRule] = [], yoRules: [ReplacementRule] = [],
                protectedTokens: Set<String> = [], mappings: [LayoutMapping] = []) {
        self.modelVersion = modelVersion; self.lexicon = lexicon
        self.typos = typos; self.yoRules = yoRules
        self.protectedTokens = protectedTokens; self.mappings = mappings
    }
}
```

`PreferencesSnapshot: Sendable, Equatable` имеет восемь immutable Bool: `autoEnabled, typoEnabled, yoEnabled, singleShiftEnabled, optionEnabled, splitShiftEnabled, plainPasteEnabled, soundEnabled`. Default true для всех, кроме option/splitShift=false; constructor все поля с указанными defaults; `static let defaults = PreferencesSnapshot()`.

- [ ] Повторить `swift test --filter ContractTests` → PASS. Проверить `swift build --arch arm64` и `swift build --arch x86_64` на поддерживающем SDK; это compile, не runtime Intel test.
- [ ] Commit: `git add Package.swift Sources/NecarambaCore/Types Tests/NecarambaCoreTests; git commit -m "feat: define deterministic core contracts"`.

**Gate:** production validator в D отвергает пустую модель; разрешение empty init в unit tests не означает production-ready rules.

## Task A2: Преобразование раскладки и регистр

**Files:** LayoutConverter.swift; LayoutConverterTests.swift; Fixtures/RulesV1.json.
**Consumes:** LayoutID, LayoutMapping. **Produces:** `LayoutConverter.convert(_ text: String, mapping: LayoutMapping) -> String` и `convert(keys: [InputEvent], to: LayoutID, mappings: [LayoutMapping]) -> String?`.

- [ ] Написать тест реальной keyboard mapping, не транслитерации:

```swift
func testLayoutConversionAndUnknownCharacters() {
    let map = LayoutMapping(source: LayoutID(rawValue: "US"),
        target: LayoutID(rawValue: "RU"),
        pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])
    XCTAssertEqual(LayoutConverter.convert("ghbdtn🙂", mapping: map), "привет🙂")
    XCTAssertEqual(LayoutConverter.convert("Ghbdtn", mapping: map), "Привет")
}
```

- [ ] `swift test --filter LayoutConverterTests` → RED. Создать converter: iterating grapheme clusters, direct lookup; case-preserving uppercase fallback лишь для one-grapheme mapping; неизвестные graphemes неизменны. Для physical events использовать `keyCode/modifiers/layout`, а character pairs только для selection/manual и fixtures; если physical mapping неизвестен → nil.

```swift
public static func convert(_ text: String, mapping: LayoutMapping) -> String {
    text.map { character -> String in
        let value = String(character)
        if let direct = mapping.pairs[value] { return direct }
        if value == value.uppercased(), value != value.lowercased(),
           let lower = mapping.pairs[value.lowercased()] { return lower.uppercased() }
        return value
    }.joined()
}
```

- [ ] Добавить явные fixtures физических ANSI/ISO/JIS клавиш от TIS из B; Russian/Russian-PC punctuation не выводить из названия. AC001–008,019. Проверить обратный проход только для bijective subset; коллизии mapping не разрешать случайно.
- [ ] `swift test --filter LayoutConverterTests` → PASS; commit `feat: add layout conversion with Unicode preservation`.

## Task A3: Доверенный буфер слова и контекст

**Files:** WordBuffer.swift, TokenGuard.swift, WordBufferTests.swift.
**Produces:** `WordBuffer.consume(_ event: InputEvent) -> BufferedWord?`, `invalidate(_ reason: InvalidationReason)`, `BufferedWord(text:String,events:[InputEvent],context:ContextToken,layout:LayoutID,delimiter:String)`.

- [ ] RED tests: 128 graphemes accepted, 129 resets/pass; 512 UTF16 limit; focusEpoch mismatch resets; ours/foreignSynthetic не обучают buffer; Space создаёт token ровно с одним delimiter; mouse/unknown input invalidates.

```swift
func testFocusChangeNeverReusesWord() {
    var buffer = WordBuffer(maxGraphemes: 128, maxUTF16: 512)
    let first = fixtureEvent("g", focusEpoch: 1)
    XCTAssertNil(buffer.consume(first))
    XCTAssertNil(buffer.consume(fixtureEvent(" ", focusEpoch: 2)))
}
```

`fixtureEvent(_:focusEpoch:)` объявить в тесте: InputEvent down, keyCode=0, modifiers=[], timestampNanos=1, layout=US, ContextToken(pid:42,bundleID:"test.editor",focusEpoch:argument,layoutEpoch:1), origin=.physical,isRepeat=false. Никаких скрытых глобальных fixture dependencies.

- [ ] `swift test --filter WordBufferTests` → RED. Реализовать state пусто/собирает/недоверенный. Переходы: start при physical letter; append same-context; boundary emits; backspace only confirmed suffix; newline сбрасывает после emission; Cmd/Ctrl, navigation, foreignSynthetic/unknown, mismatched epochs → clear. Paste никогда не превращать в последовательность набранных клавиш.
- [ ] `swift test --filter WordBufferTests` → PASS; добавить AC018–022,075–080 из matrix по фактическим IDs, сверяя названия. Commit `feat: bound typed context and invalidate stale input`.

## Task A4: Rules index и консервативные решения

**Files:** RuleIndex.swift, LinguisticEngine.swift, LinguisticEngineTests.swift, Fixtures/RulesV1.json.
**Consumes:** RuleSnapshot, BufferedWord, PreferencesSnapshot. **Produces:** `LinguisticEngine.init(snapshot: RuleSnapshot)`, `decide(word: BufferedWord, preferences: PreferencesSnapshot, excludedWords: Set<String>) -> LinguisticDecision`.

Объявить `LinguisticDecision: Equatable, Sendable` cases `.unchanged(DecisionReason)` и `.replace(Correction)`. `DecisionReason` cases correct, ambiguous, protectedToken, excludedWord, disabled, unsupportedLayout. `Correction` поля original/replacement:String, sourceLayout/targetLayout:LayoutID, modelVersion:UInt64, kind:CorrectionKind; CorrectionKind cases layout, typo, doubleCaps, yo, combined.

- [ ] Написать пять RED fixtures: `ghbdtn `→`привет `; `teh `→`the `; `елка `→`ёлка `; `все` unchanged(.ambiguous); word exception `елка` unchanged(.excludedWord). Каждый fixture самостоятельно создаёт RuleSnapshot c нужными lexeme/rules/maps. Добавить API/URL/email/path no-change tests.

```swift
func testAmbiguousYoAbstains() {
    let model = RuleSnapshot(modelVersion: 1,
        lexicon: [Lexeme(word: "все", language: .russian, frequencyBand: 5)],
        yoRules: [], protectedTokens: ["все"])
    let engine = LinguisticEngine(snapshot: model)
    let word = BufferedWord(text: "все", events: [],
        context: ContextToken(pid: 42, bundleID: "test.editor", focusEpoch: 1, layoutEpoch: 1),
        layout: LayoutID(rawValue: "RU"), delimiter: " ")
    XCTAssertEqual(engine.decide(word: word, preferences: .defaults, excludedWords: []),
                   .unchanged(.protectedToken))
}
```

- [ ] `swift test --filter LinguisticEngineTests` → RED. RuleIndex хранит NFC case-fold lookup и original case policy, строится вне callback. Выполнить pipeline spec §5; для первой working slice auto conversion только known target + unknown source + unprotected token, без случайных typo edit-distance догадок. Exact typo/yo lookup и case-shape preservation; doubleCaps только lexical target known, не all-caps abbreviation. Если исходный/target оба known → abstain.
- [ ] Расширить scoring в отдельной revision `ScoringParameters` только с corpus calibration из A7; feature до gate остаётся disabled в release config. Это явный шаг этой задачи, не неопределённое «улучшить алгоритм».
- [ ] AC001–022 и UTF8/NFC property roundtrip → PASS, `swift test --filter LinguisticEngineTests`. Commit `feat: add conservative lexical corrections`.

## Task A5: Приоритеты app/word policy

**Files:** PolicyResolver.swift, PolicyResolverTests.swift.
**Produces:** `PolicyInput(preferences:PreferencesSnapshot,appOverride:AppOverride?,profileAllowsAuto:Bool,secureInput:Bool,canListen:Bool,canPost:Bool,supportedContext:Bool)`; `AppOverride` enum allow/deny; `PolicyDecision(autoAllowed:Bool,manualAllowed:Bool,reason:PolicyReason)`; `PolicyResolver.resolve(_:)`.

- [ ] RED test: explicit app allow при secureInput true не включает auto/manual; explicit deny выключает auto, не ломает явно доступную manual; global auto false оставляет manual. Preferences typo/yo independent после auto gate.

```swift
func testAppAllowCannotOverrideSecureInput() {
    let input = PolicyInput(preferences: .defaults, appOverride: .allow,
        profileAllowsAuto: true, secureInput: true, canListen: true,
        canPost: true, supportedContext: true)
    let decision = PolicyResolver.resolve(input)
    XCTAssertFalse(decision.autoAllowed)
    XCTAssertFalse(decision.manualAllowed)
}
```

- [ ] `swift test --filter PolicyResolverTests` → RED. Implement ordered decisions: safety reasons first; manual=safe; appOverride determines auto if present; otherwise profile&&preferences.autoEnabled. Word exclusions applied by A4 after candidate generation. Preferences snapshot changes do not mutate executing transaction.
- [ ] Table-driven tests every pair of priorities, app rename/same name different IDs in C; `swift test --filter PolicyResolverTests` → PASS. Commit `feat: resolve correction policies deterministically`.

## Task A6: Чистая машина жестов

**Files:** GestureRecognizer.swift, GestureRecognizerTests.swift.
**Produces:** `GestureRecognizer.consume(_ event: InputEvent) -> [GestureAction]`, `advance(to timestampNanos:UInt64)->[GestureAction]`, `invalidate()`; GestureAction cases switchLayout, manualCorrection, toggleAuto. Config `GestureConfiguration(singleShift:Bool,option:Bool,splitShift:Bool,doubleWindowNanos:UInt64=300_000_000)`.

- [ ] RED tests с fake monotonic clock: one Shift release at20ms → no action until320ms; second press/release at200ms → manual only; mixed sides sequential → manual; simultaneous sides+split enabled → toggleAuto once; Shift+A cancels; repeat ignored; option disabled passes.

```swift
func testPendingSingleCancelledByInvalidation() {
    var recognizer = GestureRecognizer(configuration:
        GestureConfiguration(singleShift: true, option: false, splitShift: false))
    _ = recognizer.consume(shiftEvent(down: true, nanos: 0))
    _ = recognizer.consume(shiftEvent(down: false, nanos: 20_000_000))
    recognizer.invalidate()
    XCTAssertEqual(recognizer.advance(to: 500_000_000), [])
}
```

`shiftEvent` локальный test helper возвращает flagsChanged InputEvent keyCode56 (left Shift), modifiers [.shift] при down иначе[], context42/test/editor epochs1, US, origin physical, text nil,isRepeat false. Right Shift keyCode60. Реализация читает физическую сторону из keyCode, не только общего flag.

- [ ] `swift test --filter GestureRecognizerTests` → RED. Реализовать states idle/shiftHeld/pendingSingle/secondShiftHeld/splitChord/cancelledChord. `advance` выполняется runtime scheduler, не Timer внутри core. Любой unrelated input инвалидирует pending. Одновременность — overlap down states, не просто разница timestamp.
- [ ] AC023–036 → PASS; быстрый replay1M событий без retained buffer growth; commit `feat: recognize modifier gestures without stealing chords`.

## Task A7: Corpus и язык до release quality

**Files:** Tools/CorpusRunner/main.swift; Corpora files; Tests/NecarambaCoreTests/CorpusRunnerTests.swift; Reports/quality.json generated.
**Produces:** `CorpusCase(id:String,input:String,layout:LayoutID,expected:String,shouldChange:Bool,split:CorpusSplit,sourceLicense:String)` Codable; `QualityReport(total:Int,truePositive:Int,falsePositive:Int,falseNegative:Int,precision:Double?,falseChangeRate:Double?,recall:Double?)`.

- [ ] Добавить executable target CorpusRunner зависимый Core. RED test synthetic metrics: TP=199, FP=1, FN=1 → precision .995, recall .995; отсутствие expected change cases → metric `undefined`, не искусственный PASS. В report поля optional для неопределённого знаменателя; type Double? вместо Double и strict gate отвергает nil. Зафиксировать это в type сразу.
- [ ] `swift test --filter CorpusRunnerTests` → RED. Реализовать JSONL input decoder, uniqueness check id, split leakage check normalized word families, per-category confusion counts и exact mismatch list. Output не содержит настоящих пользовательских данных.
- [ ] Собрать >=10k размеченных synthetic/лицензированных примеров, manifest с источником, лицензией, SHA256, количеством; holdout>=2k/no-change>=1k. Происхождение словаря — release gate. Не использовать извлечённые сторонние модели и не объявлять четыре test pairs production-моделью.
- [ ] `swift run CorpusRunner --manifest Corpora/manifest.json --split holdout --output Reports/quality.json` → все пороги spec §5 либо nonzero exit с числами. Порог calibrated only on calibration, holdout не менять ради прохода.
- [ ] Выполнить собственный differential run по physical-input-test-protocol в отдельном профиле; записать unrun editor/OS combinations. Commit `test: add frozen language corpus and quality gates`.

## Финальная проверка A

- [ ] `swift test` → все Core tests PASS; `swift build -c release --arch arm64` и x86_64 compile PASS.
- [ ] Проверить F01–08/F10–11 на уровне core и AC001–044, включая новые guard cases. Системные результаты B ещё не выполнены.
- [ ] Зафиксировать manifest всех constants как design parameters; ни один не выдаётся за значение, полученное из другого продукта.
- [ ] Передать B/C/D реальные public interfaces и изменения signatures. Реализация A сама по себе ещё не переключает раскладку в чужом приложении.
