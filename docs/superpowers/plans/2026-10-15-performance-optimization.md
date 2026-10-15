# Necaramba Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Снизить задержки исправлений, блокировки главного потока и расход ресурсов, сохранив точность и безопасность ввода.

**Architecture:** Сохранить Clean Architecture, Flutter UI и Swift runtime. Измерения отделить от решений, стабильные языковые данные готовить заранее, периодические таймеры заменить планированием по необходимости. Правки текста выполнять одной последовательной асинхронной транзакцией с проверками фокуса и поколения.

**Tech Stack:** Swift, XCTest, AppKit/Accessibility/Carbon, Flutter, Instruments и OSLog; macOS 12+, arm64/x86_64.

**Spec:** `docs/implementation/reports/performance-audit-2026-10-15.md`; обязательные ограничения — `AGENTS.md` и `docs/superpowers/specs/2026-10-14-necaramba-design.md`. Состояние открытой модели — `docs/implementation/reports/open-model-v2.md`.

## Global Constraints

- Clean Architecture; Flutter UI; Swift native runtime; macOS 12+; arm64/x86_64.
- Domain entities and repository ports must not import Flutter, AppKit, SQLite or channel APIs.
- No keyboard data crosses into Dart.
- Never modify installed Caramba, user TCC, login items or personal documents in tests.
- Не менять окно двойного Shift 300 мс, не расширять ownership lease 100 мс и существующие deadlines readback.
- Не повторять разрушительную операцию после частичной отправки. Успешный API return не заменяет подтверждение результата.
- Не кешировать AX-текст и доказательства фокуса для последующей правки. При неопределённости отменять правку.
- Сохранять все текущие исправления Safari/Zen/Chrome/Spark/Spotlight, повторного двойного Shift, выделения и версий `1.3.166`.
- Не переписывать приложение на C++/Rust и не менять словарь в рамках этого плана.
- Не коммитить чужие незавершённые изменения. Перед исполнением зафиксировать базовый diff и согласовать владение файлами; коммиты включают только изменения задачи. Публикация релиза — отдельная задача.

## Что уже сделано и что ещё не доказано

Open Model 2 уже использует `PackedOpenLexicon`, `OpenWordLookup` и загрузку вне потока ввода. Повторно реализовывать эти пункты старого аудита не нужно. Около 39,45 MB индекса и около 105 мс загрузки в CLI — не измерения памяти и старта всего приложения.

AX refresh 118–125 мс в старом аудите — отдельные наблюдения. Они обосновывают исследование, но не дают p95. Сначала нужен baseline текущей открытой Release-сборки. Сравнение со старым закрытым процессом не считается доказательством ускорения.

## Приоритеты и зависимости

| Этап | Результат | Зависимость / риск |
|---|---|---|
| 1 | Измеримый baseline и диагностика | Первый; низкий риск |
| 2 | Подготовленные языковые данные | После 1; низкий риск |
| 3 | Таймер жестов по deadline | После 1; средний риск |
| 4 | Единый планировщик focus recovery | После 1; средний риск |
| 5 | Асинхронная транзакция замены | После интеграции 2–4; высокий риск |
| 6 | Асинхронное подтверждение раскладки; эксперимент Spark | После 5; средний/высокий риск |
| 7 | Сравнение Release и приёмка | После каждого этапа короткий прогон, в конце полная матрица |

Этапы 2–4 можно раздать отдельным агентам после стабилизации контрактов этапа 1. Общие `NativeInputController.swift`, `InputRuntime.swift`, `Package.swift` и Xcode-конфигурацию изменяет интегратор. Агент таймеров владеет recognizer/tap, агент focus — monitor/polling, агент подготовки — новым immutable configuration и тестами. Пересекающиеся интеграционные изменения выполняются последовательно.

## Этап 1. Измерения и ограниченная диагностика

**Файлы:** изменить `Sources/NecarambaMac/Input/InputDiagnostics.swift`; создать `Sources/NecarambaMac/Input/InputPerformanceMetrics.swift`, `Tests/NecarambaMacTests/InputPerformanceMetricsTests.swift`, `Tools/Performance/README.md`; точки измерения добавить в `NativeInputController.swift`, `EventTapAdapter.swift`, `ContextMonitor.swift`, `Replacement/AXSelectionAdapter.swift`. Итоги — `docs/implementation/reports/performance-baseline.md`.

**Контракт:** фиксированный enum стадий, монотонное время, счётчики и гистограммы ограниченного размера. Никакого произвольного текстового payload. Proposed interface:

```swift
enum InputPerformanceStage: CaseIterable {
  case commandQueue, classification, preflight, posting, verification, total
}
// Methods on InputPerformanceMetrics; synchronization stays inside the adapter.
// record(_ stage: InputPerformanceStage, durationNanos: UInt64)
// snapshotAndReset() -> [InputPerformanceStage: [UInt64]]
// Fixed histogram boundaries: 1, 2, 5, 10, 20, 50, 100, 200, 500 ms, overflow.
```

- [ ] Сначала тест граничных buckets, reset и отсутствия роста хранения при миллионе записей. Минимальная проверка: записать 1_000_000 ns в `.classification`, проверить один sample в bucket ≤1 ms и ноль после reset. `swift test --filter InputPerformanceMetricsTests` должен показать RED до реализации.
- [ ] Реализовать фиксированные buckets и безопасную синхронизацию; в tap не добавлять блокирующий экспорт или дисковую запись. Замер overhead входит в baseline.
- [ ] Разделить время ожидания жеста и выполнения команды: total начинается на recognized command, отдельная метрика — от release до recognition. Для auto — от boundary event. Записывать причины отмены, но не текст, keycodes, заголовки окон, URL и пути документов.
- [ ] Обычные AX stage traces сделать opt-in через `NECARAMBA_PERF_TRACE=1`, по умолчанию выключено; ошибки и агрегаты сохранить. Диагностический режим автоматически заканчивается через 10 минут, его таймер существует только при включении режима.
- [ ] Повторить тесты диагностики и полного native пути; провести короткий A/B с инструментированием включённым/выключенным, чтобы оценить его собственную стоимость.
- [ ] Снять baseline по протоколу этапа 7 и записать build revision, dirty diff hash, model manifest hash, оборудование, ОС, настройки, версии приложений и сырые обезличенные результаты. Один baseline нельзя смешивать с разными моделями.
- [ ] Отдельный коммит: `perf: add bounded input latency metrics`.

## Этап 2. Подготовленные языковые данные

**Файлы:** создать `Sources/NecarambaCore/Language/PreparedWordPolicy.swift`, `Tests/NecarambaCoreTests/PreparedWordPolicyTests.swift`; изменить `Sources/NecarambaMac/Input/NativeInputController.swift`, `Sources/NecarambaCore/Language/{OpenCorrectionEngine,PatternCorrectionEngine,LinguisticEngine}.swift` только в части передачи заранее нормализованной политики. Существующие публичные convenience-вызовы сохранить.

**Контракт:** immutable `PreparedWordPolicy` с `init(excluded: Set<String>, protected: Set<String>)` и `contains(_ word: String) -> Bool`. Нормализация должна дословно соответствовать текущей реализации. Подготовленная RU/EN-пара остаётся в Mac-слое рядом с captured tables. Конфигурация публикуется целиком, а не по отдельным полям.

- [ ] Написать RED-тест равенства старого и подготовленного пути на casing/Unicode/excluded/protected; проверить, что обновление исключений влияет на следующую команду, а устаревшее поколение не применяется. Пример проверки: `XCTAssertTrue(PreparedWordPolicy(excluded: ["HELLO"], protected: []).contains("hello"))`.
- [ ] Реализовать нормализацию один раз при смене правил/исключений. Не добавлять второй большой индекс словаря.
- [ ] Подготовить RU/EN-пару при захвате таблиц; перечитывать при изменении доступных input sources, не на каждом слове. При смене активной раскладки сохранить корректное направление конверсии.
- [ ] Добавить тесты install/updateWordPolicies/input-source-change и замены модели во время команды. Выполнить `swift test --filter 'PreparedWordPolicyTests|NativeInputControllerTests|OpenCorrectionEngineTests|LayoutCaptureTests'`.
- [ ] Сравнить classification duration/allocations и решения на неизменном corpus с baseline. Новые ошибки решений недопустимы.
- [ ] Отдельный коммит: `perf: prepare immutable word and layout policies`.

## Этап 3. Таймер tap по ближайшему deadline

**Файлы:** изменить `Sources/NecarambaCore/Input/GestureRecognizer.swift`, `Sources/NecarambaMac/Input/{InputRuntime,EventTapAdapter}.swift`; расширить `Tests/NecarambaCoreTests/GestureRecognizerTests.swift`; создать `Tests/NecarambaMacTests/InputDeadlineTests.swift`.

**Контракт:** `GestureRecognizer.nextDeadlineNanos: UInt64?`; runtime объединяет его со всеми отложенными действиями. Tap выбирает минимум runtime deadline и срока shortcut ownership. Временная шкала — monotonic nanoseconds; нулевое число pending obligations означает отсутствие таймера.

- [ ] Инвентаризировать все обязанности `tick()` и `advance(to:)`, включая Spark deferred boundary, ownership и replay; перечислить их в тесте как отдельные сценарии. Удалять 20-ms tick до этого нельзя.
- [ ] RED fake-clock проверки: idle→нет timer; single release→deadline ровно через300ms; double release→manual один раз; новая клавиша/смена контекста→отмена; ownership expiry→replay/abort ровно один раз; одновременные deadlines; stop/restart; сон и пробуждение.
- [ ] Добавить `nextDeadlineNanos` и one-shot CFRunLoopTimer. Перепланировать после каждого события и изменения обязательств. Просроченный deadline обрабатывать один раз, без бесконечного zero-delay цикла.
- [ ] Выполнить `swift test --filter 'GestureRecognizerTests|InputDeadlineTests|KeyBatchPostingTests'`, затем полную Swift suite.
- [ ] Измерить 10 минут idle: постоянного timer 50 Гц больше нет; window double Shift и replay safety не изменились. Измерить callback p99 под нагрузкой.
- [ ] Отдельный коммит: `perf: schedule input deadlines on demand`.

## Этап 4. Уменьшение AX refresh и recovery polling

**Файлы:** изменить `Sources/NecarambaMac/Input/{ContextMonitor,FocusRefreshPolling}.swift`; создать `Sources/NecarambaMac/Input/FocusRefreshScheduler.swift`; расширить `Tests/NecarambaMacTests/{FocusRefreshPollingTests,ContextRecoveryTests,ContextStateTests}.swift`.

**Контракт:** один scheduler владеет pending refresh и recovery timer; `requestRefresh()` объединяет уведомления в одном обороте main run loop, `stop()` отменяет поколение. Событие фактической смены фокуса немедленно инвалидирует старую безопасность, даже если чтение объединено.

- [ ] RED-тест: 100 одинаковых уведомлений до выполнения scheduler дают один refresh, а смена focus/security немедленно запрещает edit. Отдельно проверить stop→stale callback и новый активный процесс.
- [ ] Объединить overlay и recovery scheduling. При здоровом observer и валидном контексте не держать polling timer. На activation, permission recovery и invalidation немедленно запрашивать refresh.
- [ ] При отсутствующем observer сохранить период250ms. При недоступном контексте со здоровым observer использовать250→500→1000ms backoff; любое новое authoritative notification сбрасывает backoff. Если измерения покажут ухудшение восстановления, оставить250ms в recovery и принять только idle/coalescing изменения.
- [ ] Добавить счётчик capture invalidation во время reconcile. Не возвращать старый ContextToken и не вводить pending capture в этом этапе: такая функция требует отдельного дизайна.
- [ ] Выполнить `swift test --filter 'FocusRefreshPollingTests|ContextRecoveryTests|ContextStateTests'`. Проверить первый word после переключения окна, overlay Spotlight, потерю/возврат permission через test double и реальное sleep/wake без изменения TCC.
- [ ] Сравнить AX calls/second, recovery latency и missed corrections с baseline. Коммит: `perf: coalesce focus refresh and idle recovery`.

## Этап 5. Последовательная асинхронная замена

**Файлы:** создать `Sources/NecarambaMac/Replacement/EditTransactionCoordinator.swift`, `Tests/NecarambaMacTests/EditTransactionCoordinatorTests.swift`; изменить `Replacement/AXSelectionAdapter.swift`, `Input/{NativeInputController,EventTapAdapter}.swift`; проверить потребителей `Sources/NecarambaCore/Ports/Editing.swift` и `Tests/NecarambaMacTests/{AXSelectionProofTests,SelectionTests,ReplacementTests,KeyBatchPostingTests}.swift`.

**Контракт:** одна активная транзакция; состояния idle→preflight→posting→verifying→finished/cancelled. Все completion доставляются на main ровно один раз. Новый публичный async путь использует существующие `ApplyResult`, `ContextToken`, `SelectionEvidence`; синхронный production путь не должен блокировать ожиданием async результата. AX остаётся на main на этом этапе.

```swift
// Proposed coordinator entry point, called on main:
// func start(token: ContextToken,
//            operation: @escaping () async -> ApplyResult,
//            completion: @escaping (ApplyResult) -> Void)
// func cancel()
// A second start while active completes as .aborted; never queues stale text edits.
```

- [ ] RED-тесты на fake clock/reader/poster: delayed AX; torn snapshot; deadline; focus change; Secure Input; физическая клавиша; permission loss; partial posting; отмена между шагами; поздний completion. Проверить инварианты `activeMutations <= 1`, `postCount <= 1`, `completionCount == 1`.
- [ ] Перенести polling readback из цикла с `Thread.sleep` в scheduled observation. Deadline фиксируется при старте и не продлевается. Перед/после каждой асинхронной границы повторять generation/focus/security checks.
- [ ] Заменить main-thread semaphore ожидание posting на completion; destructive block по-прежнему выполняется на tap с существующим100ms lease и локальными проверками. Timeout не означает разрешение повторить отправку.
- [ ] Перевести все пути manual/selection/repeat/auto/undo/plain paste, использующие изменённый контракт, без sync-over-async мостов. Сохранить существующую логику quarantine uncertain результата.
- [ ] Отдельным изменением испытать batch AX attribute reads: сохранять индивидуальные ошибки атрибутов и финальную identity-проверку. Batch не считать атомарным снимком. Принять только при измеренном уменьшении IPC без потери proof.
- [ ] Выполнить целевые proof/coordinator/posting тесты, затем `swift test`. Провести host smoke matrix перед объединением. Не переносить AX на отдельный executor и не вводить bounded-range replacement без отдельной квалификации.
- [ ] Коммиты отдельно: `refactor: coordinate asynchronous edit verification`, затем при подтверждённом эффекте `perf: batch accessibility observations`.

## Этап 6. Подтверждение раскладки и Spark

**Файлы:** изменить `Sources/NecarambaMac/Layout/TISLayoutAdapter.swift`, `Input/{NativeInputController,InputRuntime}.swift`; расширить `Tests/NecarambaMacTests/{LayoutAdapterTests,ConservativeAutomaticTests}.swift`.

**Контракт:** асинхронный select сохраняет текущие default3 attempts и20ms интервал retries, завершает результат только после readback. Его ожидание не удерживает main. Spark readiness использует фиксированный общий deadline и generation транзакции этапа5.

- [ ] RED-тесты: уже выбранная раскладка; позднее подтверждение; все попытки неуспешны; неподдерживаемая раскладка; cancellation между попытками. Подтверждение только после `access.current() == target`.
- [ ] Убрать sleep из VerifiedLayoutSwitcher через injected scheduler; не менять задержку распознавания одиночного Shift.
- [ ] Сначала измерить, сколько Spark-команд действительно ждут все60ms и когда AX становится достоверным. Затем отдельным экспериментом заменить фиксированное ожидание на bounded readiness observation. Не применять раньше получения полного proof и не увеличивать общий deadline; число AX обращений также сравнить.
- [ ] Выполнить `swift test --filter 'LayoutAdapterTests|ConservativeAutomaticTests'`, затем реальные Spark plain/rich-text сценарии. Если качество или IPC ухудшились, сохранить60ms и зафиксировать результат эксперимента; это не блокирует остальные оптимизации.
- [ ] Коммит TIS отдельно от условного Spark изменения: `perf: verify layout changes without blocking main`.

## Этап 7. Протокол измерений и критерии приёмки

**Файлы:** создать `Tools/Performance/scenarios.md`, `docs/implementation/reports/performance-results.md`; дополнить `Tools/Performance/README.md` командами и условиями измерений. Новые fixtures содержат только специально созданный тестовый текст.

- [ ] Build/check commands из корня:

```sh
swift test
cd App
flutter analyze
flutter test
env -u NECARAMBA_LOCAL_PATTERN_MODEL NECARAMBA_OPEN_MODEL=YES flutter build macos --release --build-name=1.0.0 --build-number=2
```

- [ ] Сравнить baseline и candidate на одном Mac, одинаковых приложениях/настройках/словаре, без debugger; чередовать A/B/A/B. Не запускать два перехватчика клавиатуры одновременно. Выполнить отдельно ARM64 и настоящий Intel; Rosetta не выдавать за Intel hardware qualification.
- [ ] Матрица: Orca, TextEdit, Safari (адрес и страница), Chrome, Zen, Spark (plain/rich), Spotlight. На каждом сценарии минимум30 повторов, результаты отдельно по host. Для p99 hot path собрать не менее1000 событий в выделенном нагрузочном прогоне; на30 повторах p99 не использовать как устойчивый SLA.
- [ ] В каждом host: первое слово в новом поле; auto RU→EN и EN→RU (`ground`, `connector`, `тоже`, `переключилось`); повтор двойного Shift30раз; выделение; версия `1ю3ю166`; быстрое продолжение печати; смена фокуса во время проверки. Никаких отправок сообщений/форм. Длинное поле и приватные/secure поля проверять в созданных fixtures.
- [ ] Отдельно:10мин idle с настройками закрытыми/открытыми,10мин печати,20циклов открытия/закрытия UI;10cold и30warm запусков модели. Зафиксировать p50/p95, распределение tails, error/cancel counts, physical footprint/peak, CPU, wakeups, AX calls и startup-ready time. Использовать Instruments Time Profiler/Allocations/Energy; `vmmap -summary <PID>` для footprint. RSS не подменяет footprint.
- [ ] Обязательные gates: ноль повреждённых/чужих/двойных правок; нет новых ошибок на frozen corpus; нет потерянных gesture deadlines; нет роста missed corrections на одинаковых fixtures; нет периодического50Hz idle timer; нет собственных `Thread.sleep`/semaphore waits на main в edit/layout пути.
- [ ] Предлагаемые performance gates: ухудшение callback p99 или end-to-end p95 более5% требует повторного A/B и расследования; устойчивое ухудшение блокирует изменение. При шуме больше5% увеличить sample count. Экспериментальная цель — снизить p95 в выявленных медленных сценариях минимум20%, но не объявлять её достигнутой заранее и не требовать её от host, где задержка полностью внешняя.
- [ ] Рост steady-state footprint более5% относительно той же открытой baseline требует объяснения; проверить отсутствие монотонного роста после20циклов UI. Старые205MiB закрытого процесса не использовать как baseline новой модели.
- [ ] В отчёте разделить measured, inferred и unrun. Если нет Intel/host, пометить соответствующую квалификацию непройденной. Принимать независимые успешные оптимизации отдельно; регрессирующий этап откатывать собственным коммитом, не чужими изменениями.
- [ ] Финальный review безопасности ввода и сравнительного отчёта. Коммит результатов: `docs: record measured input performance qualification`.

## Завершение

План считается выполненным после реализации и проверки основных этапов1–5, TIS части6 и отчёта7; Spark эксперимент может закончиться сохранением текущей задержки с измеренным обоснованием. Ускорение заявляется только по конкретным измеренным сценариям. GitHub release и смена публичной версии в этот план не входят.
