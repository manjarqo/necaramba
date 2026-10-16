# Necaramba E — Flutter Runner and Native Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Подключить Flutter UI к автономному Swift runtime без передачи клавиатурного потока в Dart.

**Architecture:** Flutter macOS Runner является оболочкой. Native composition root живёт до завершения процесса, Swift package содержит input/storage/delivery services. MethodChannel принимает UI-команды; EventChannel передаёт полные версии агрегированного состояния. Flutter engine привязан к окну, native runtime — к приложению.

**Tech Stack:** Flutter/Dart, flutter_bloc Cubit, MethodChannel/EventChannel со StandardMethodCodec, Swift/AppKit, XCTest, Flutter widget/integration tests. Конкретные SDK/dependency версии фиксируются в Task1 по результатам qualification.

**Spec:** [Спецификация](../specs/2026-10-14-necaramba-design.md), раздел3. Этап добавлен по прямому выбору пользователем Flutter. Код ещё не написан, команды ниже не выполнены.

## Global Constraints

- Flutter/Dart для UI, Swift/AppKit для нативного ядра; минимальная macOS 12.0; архитектуры arm64 и x86_64.
- Основной цикл ввода работает локально и без сети.
- Callback event tap не выполняет сеть, файловый ввод-вывод или блокирующие AX-вызовы.
- Не сохранять и не отправлять набранный текст по умолчанию.
- При неопределённом фокусе, Secure Input, IME/composition или недоступных разрешениях пропускать ввод без изменения.
- Синтетические события маркируются и не обрабатываются повторно.
- Код, идентификаторы сервисов, модели, звуки, графика и аккаунты сторонних переключателей не входят в распространяемый продукт.
- Не выпускать функцию как совместимую без соответствующего теста и результата в матрице приёмки.

## Ownership и контракт

Интегратор E владеет `App/pubspec.yaml`, `App/pubspec.lock`, `App/analysis_options.yaml`, `App/macos/Runner.xcodeproj`, workspace/schemes, Runner AppDelegate/MainFlutterWindow/FlutterWindowHost, `App/lib/main.dart`, `App/lib/bridge/`, `App/macos/Runner/Bridge/`, `App/test/bridge/`, `App/macos/RunnerTests/`, `docs/release/flutter-toolchain.md`. A/B/C/D не изменяют эти файлы параллельно; их package products/resources интегрирует E. Отдельный native TestHost B остаётся `App/TestHost/` и не зависит от Flutter.

A1 создаёт Swift package. E1 создаёт Flutter app во временном каталоге и переносит scaffold в `App` без перезаписи существующего TestHost/helper. Локальный package подключается из repository root. Xcode scheme Runner включает RunnerTests и test bundles из package, нужные D; standalone XCTest package выполняется `swift test` из корня. Это одна app identity и один экземпляр native runtime, без второго фонового процесса.

### Wire v1

Каналы: `necaramba/control.v1` / `necaramba/state.v1`. Map payload — codec primitives; decoder проверяет schema/types/limits на обеих сторонах. Все Int на wire ограничены signed64; revision монотонный within session. Swift UInt64 versions вне signed64 передаются decimal strings, не Double. Swift services не зависят от FlutterMacOS.

`NativeState`: schema=1, sessionID:String(UUID), revision:int≥0, preferences:Map<String,bool> (8 флагов A), capabilities:Map(listen,post,axTrusted,secureInput bool), status:String(enum C), words:List<WordRuleDTO>, apps:List<AppRuleDTO>, model:Map(version:String,lastChecked:String?,state:String), license:Map(state:String,expiresAt:String?), statistics:Map<String,int>, appearance:Map(colorIndex:int,hasCustomSound:bool,hasHeaderImage:bool), login:Map(enabled:bool,status:String). Word DTO содержит id/normalized/original/createdAt/legacy; app DTO bundleID/displayName/mode. Bookmarks, license proof и filesystem paths наружу не выходят. Header preview передаётся отдельным ограниченным thumbnail, не полным изображением.

Commands envelope `{requestID:String, expectedSessionID:String, expectedRevision:int, arguments:Map}`. `getState` и `getThumbnail` — read-only без expected revision. Остальные mutating commands сначала проверяют session/revision. Сериализованный native coordinator выполняет storage commit, публикует новую revision и возвращает `{requestID,state:NativeState,result:Map}` (result пустой для обычных mutations; previewShare содержит previewID и immutable preview, getThumbnail содержит bytes≤256KiB); failed command не меняет confirmed state. Stale command возвращает `conflict`, клиент загружает state и требует повторного действия, не перезаписывает соседнее изменение. Native requestID cache128 последних результатов на session предотвращает duplicate submission; purchase/share повторно автоматически не отправляются после timeout/reconnect.

| Command | arguments и владелец |
|---|---|
| setPreferences | patch:Map<String,bool>, только8 ключей A; C |
| addWord/deleteWord/clearWords | text:String / id:String / confirmed:bool; C storage validation |
| chooseApp/setAppMode/deleteApp | empty / bundleID:String,mode:allow-or-deny / bundleID:String; native NSOpenPanel C |
| requestPermission/refreshCapabilities | kind:listen-or-post-or-ax / empty; B, запрос только user action |
| setLoginEnabled | enabled:bool; C |
| setHeaderColor/importHeaderImage/removeHeaderImage/getThumbnail | index0..24 / native drop handle / empty / empty; C |
| chooseSound/resetSound/resetCounters | empty / empty / confirmed:bool; C |
| checkRules | empty; D throttle |
| previewShare/confirmShare/cancelShare | word+language+modelVersion+optional feedback / previewID / previewID; D explicit consent |
| purchase/restore/manageSubscription | own productID / empty / empty; D |
| exportDiagnostics/exportArchive/importArchive | native panels, empty; C |

File drops: native NSDraggingDestination получает TIFF/fileURL только при реальном drop над header region, выдаёт одноразовый opaque handle привязанный к engine session, с TTL60sec. Flutter не отправляет произвольный путь для чтения. NSView overlay покрывает только header drop region, координаты обновляются при resize; consume handle валидирует размер/тип C. Native file panels используют тот же managed import C. Preview-share даёт immutable previewID; Confirm не меняет содержимое preview.

Ошибки `invalidArgument`, `conflict`, `permissionDenied`, `unavailable`, `cancelled`, `ioFailure`, `unsupportedSchema`, `timeout` имеют redacted message, requestID и retryable. Исходные NSError/user text не логировать. Timeout клиента10sec для обычных команд; purchase/dialog ожидают явного завершения/Cancel без автоматического retry. Timeout не доказывает отмену native mutation: resync перед следующим действием.

EventChannel при listen сразу выдаёт полный state; изменения coalesce максимум10Hz вне input executor. Cancel снимает listener и timer. Reconnect пересоздаёт подписку до getState, фильтрует older revisions; session change сбрасывает старый revision. Ни одно UI событие не содержит InputEvent, token buffer, clipboard или набранную строку. Explicit words пользователя в exceptions/share допустимы.

## Task 1: Runner и квалификация SDK

**Files:** ownership scaffold/toolchain files; `App/test/smoke_test.dart`, native `App/macos/RunnerTests/CompositionRootTests.swift`.
**Consumes:** A1 products. **Produces:** Runner workspace/scheme и NativeCompositionRoot с single-instance `start()/stop()`, dependency injection для synthetic profile.

- [ ] Зафиксировать `flutter --version --machine`, `dart --version`, `xcodebuild -version`; выбрать доступный stable SDK с macOS12/arm64/x86_64 engine artifacts. Сохранить version+commit в toolchain.md и CI pin; pubspec.lock commit обязателен. Не использовать floating latest в release.
- [ ] RED native test: два вызова root.start() дают tapFactory.createCount==1; повторное открытие UI не создаёт root. Widget smoke test запускает bootstrap при fake NativeRepository без платформы.
- [ ] Создать scaffold командой `flutter create --platforms=macos --project-name necaramba <empty-staging-directory>`, merge в App без перезаписи owned files. Deployment12.0 во всех configurations, `LSUIElement=true`, Runner composition root стартует до UI. Один NSStatusItem; launch at login без открытия окна. Обеспечить `applicationShouldTerminateAfterLastWindowClosed=false`.
- [ ] `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build macos --release` из App; `swift test` из root. Собранные executable, FlutterMacOS/App frameworks и каждый native plugin проверить `lipo -archs`, `vtool -show-build`; реальные launch на macOS12 Intel и Apple Silicon. Отсутствие architecture/OS совместимости блокирует выбор SDK, не меняет user target.
- [ ] Commit `build: add qualified Flutter macOS runner` после GREEN. CI имеет separate SDK qualification и не считает Rosetta эквивалентом Intel host.

## Task 2: Versioned bridge и resynchronization

**Files:** `App/lib/bridge/native_repository.dart`, `native_state.dart`, `platform_native_repository.dart`; `App/macos/Runner/Bridge/NativeBridge.swift`, `WireCodec.swift`; `App/test/bridge/native_repository_test.dart`, `App/macos/RunnerTests/NativeBridgeTests.swift`.
**Consumes:** services B/C/D. **Produces:** Dart контракт:

```dart
abstract interface class NativeRepository {
  Stream<NativeState> get states;
  Future<NativeState> refresh();
  Future<NativeReply> command(String method, Map<String, Object?> arguments);
  Future<void> dispose();
}
```

`NativeReply(requestID:String, state:NativeState, result:Map<String,Object?>)` — immutable command result; repository публикует его state в общий reducer до возврата. getThumbnail также возвращает NativeReply; preview bytes ограничены256KiB, max512×512pixels. NativeState immutable model содержит перечисленные Wire v1 поля; `fromMap` отвергает invalid schema/missing fields/unknown enum, `toMap` симметричен. `NativeFailure(code,requestID,retryable)` — typed exception. Репозиторий генерирует envelope, возвращает confirmed state, Cubit не знает revision transport.

- [ ] RED tests: decoder отвергает schema2; older revision не откатывает state; native conflict не записывает prefs; duplicate requestID share делает transport call ровно1. Fixture helpers создают полный Wire v1 map, не частичный production DTO.

```dart
test('older state does not overwrite newer state', () {
  final reducer = NativeStateReducer();
  reducer.accept(NativeState.fixture(sessionID: 's', revision: 9));
  reducer.accept(NativeState.fixture(sessionID: 's', revision: 8));
  expect(reducer.current!.revision, 9);
});
```

`NativeState.fixture` — test-only extension в support, reducer public `accept(NativeState)`/`current` определён в native_state.dart. Смена session принимает новый full snapshot даже при меньшем revision.
- [ ] GREEN MethodChannel handler принимает whitelist, валидирует и ставит работу на native coordinator; тяжёлые storage/network операции вне main. Callback результата/Flutter events возвращаются на main thread. InputRuntime не ждёт coordinator или Dart. getState возвращает authoritative snapshot, errors mapped явно.
- [ ] Channel fake tests имитируют cancel/relisten, timeout-after-commit, unsupported schema и out-of-order events. Native channel тесты используют fake B/C/D и callback spy; privacy asserts запрещают raw input fields/fixture typed text. `flutter test test/bridge` и RunnerTests/NativeBridgeTests → PASS.
- [ ] Commit `feat: add versioned Flutter native bridge` после GREEN.

## Task 3: Cubit, локализация и полная UI-интеграция

**Files:** `App/lib/main.dart`, `app.dart`, `App/lib/features/settings/settings_cubit.dart`, `App/lib/l10n/`, `App/test/support/native_fakes.dart`, `App/integration_test/settings_flow_test.dart`. Feature widgets и native adapters — C ownership, координировать изменения.
**Consumes:** NativeRepository, C/D feature contracts. **Produces:** bootstrap injection, Cubit subscription/dispose, RU/EN delegates, Feature routes settings/exceptions/onboarding/diagnostics/paywall/sharePreview.

- [ ] RED widget scenario: native auto=true→UI toggle→command pending→native permission error; final visible toggle=true, error shown. FakeNativeRepository records NativeCall(method,arguments), can emit states/fail next command; TestApp injects repository and localization delegates.
- [ ] GREEN Cubit имеет confirmed NativeState, pending set и redacted error; subscriptions отменяются в close. Настройки/rules никогда не persist в Dart самостоятельно. Flutter dialogs поддерживают Cancel, keyboard navigation, Semantics role/value. Native menu toggle приходит тем же state stream, без отдельного shadow preference.
- [ ] Native image drag overlay E2/C5, собственный звук, статистика, update freshness, login/permissions/paywall проходят реальные команды. StoreKit view состояние отображается Flutter, account/payment API остаются Swift. Preview share показывает exact word/language/modelVersion/feedback и собственный host до confirm.
- [ ] `flutter gen-l10n`, `flutter analyze`, `flutter test`, `flutter test integration_test/settings_flow_test.dart -d macos` из App. Пройти AC038–090 для synthetic profile, VoiceOver/Reduce Motion/dark/keyboard-only вручную с evidence. Не заменять host checks widget-тестами.
- [ ] Commit `feat: compose localized Flutter feature flows` после GREEN.

## Task 4: UI lifecycle, background autonomy и release qualification

**Files:** `App/macos/Runner/FlutterWindowHost.swift`, `App/macos/RunnerTests/FlutterLifecycleTests.swift`, `Tools/Release/measure_flutter_lifecycle.sh`, `docs/release/flutter-lifecycle.md`.
**Consumes:** B replay runner, C native shell, D release gates. **Produces:** background/window lifecycle measurements и release qualification E-01–E-04.

- [ ] RED native test scenario: root.start→open→close→open100cycles; tapCreated==1, activeListener≤1, closed engine listener0. Fake runtime получает100000 events и ту же последовательность решений с закрытым UI. Freeze Dart на5sec не блокирует capture/replacement; не заявлять crash isolation — native и Flutter находятся в одном процессе.
- [ ] GREEN host держит engine/controller только пока окно открыто; close cancels Flutter channel subscriptions, отключает handlers, освобождает controller/engine/window согласно pinned embedder API. Проверить deallocation/native instrumentation; запретить polling/rendering при закрытом окне. Не просто прятать окно и считать engine освобождённым.
- [ ] Измерить release hardware/OS/SDK/hash: tap p99≤2ms, classifier≤10ms, idleCPU≤0.5% при закрытом UI; RSS≤100MiB без engine, provisional ceiling≤200MiB с UI. Эти бюджеты — design, не обещанная характеристика Flutter. Если engine memory не освобождается или ceiling нарушен, gate FAIL и явное изменение архитектуры/бюджета до выпуска.
- [ ] E-01: реальный Intel/macOS12 и Apple Silicon запуск всех engine/plugin slices. E-02: channel revisions/timeout/reconnect. E-03: F01–22 UI coverage + accessibility. E-04: closed/reopened/frozen Dart и memory/replay. D5 агрегирует103AC **и** эти4 обязательных Flutter gates.
- [ ] `flutter build macos --release` перед archive; подписывать вложенные Flutter frameworks вместе с app по D, проверить notarized clean install обеих архитектур. Commit `test: qualify Flutter background lifecycle and universal release` после GREEN.
