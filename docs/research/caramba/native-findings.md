# Нативные механизмы: выводы из Ghidra/REA

Срез анализа 2026-10-14, основной Mach-O arm64. Источники — `decompiled/keypaths/*.c` и уже выгруженные `decompiled/main-arm64/*.c`. Это восстановленный псевдокод, не исходники. Evidence ID находится в начале каждого файла. Адреса в тексте — виртуальные адреса arm64. Проверки на устройстве не выполнялись.

Особенно важно: Ghidra местами неверно восстанавливает Swift ABI/возвращаемые регистры. Последовательности `x=0; ExternalAPI(); if(x!=0)` не доказывают мёртвый код. `unaff_x20`, `unaff_x22`, отсутствие аргументов у imported stubs и странные return types не считаются дефектами программы. Ниже сохраняется граница между вызовами/константами и интерпретацией.

## 1. Event tap, разрешения и lifecycle

`0x100049b20` создаёт основной tap после `AXIsProcessTrustedWithOptions`, если отсутствует `AppDelegate.eventTap` либо `runLoopSource`:

```c
CGEventTapCreate(0, 0, 0, 0x1c06, FUN_100049bec);
CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
```

Нулевые первые параметры соответствуют HID event tap / head insertion / active filter. Маска `0x1c06` включает bits 1,2,10,11,12: mouse down/up и keyboard down/up/flags changed. Это вывод по CoreGraphics enum, точные значения видны непосредственно. User info шестого аргумента Ghidra в этом фрагменте не восстановил.

`0x100049bec` — тонкий callback wrapper, вызывает `0x10004bff4`. Значение `return param_2` wrapper нельзя интерпретировать как возвращаемый CGEvent без проверки ABI.

`0x10004bff4`:

- повторно проверяет Accessibility trust;
- при отсутствии trust вызывает `CGEventTapEnable(tap,0)`;
- сравнение `(int)eventType + 2U < 2` ловит `0xfffffffe/0xffffffff`, после чего `CGEventTapEnable(tap,1)`; это соответствует восстановлению после tap-disabled событий;
- для типа `0x0c` вызывает `0x1000492f4` и `0x1000075ac`;
- вызывает `IsSecureEventInputEnabled`; только ветка отсутствия Secure Input передаёт событие `0x100230dd8`.

Точная обработка keys и return/suppression policy внутри `0x100230dd8` требует отдельного анализа. Сам факт Secure Input gate сильнее одних текстов уведомлений.

`0x100046c10` управляет жизненным циклом. Если `eventTapEnabled != 1` либо `forceBlockEventTap & 1`, tap отключается, source удаляется из run loop, оба хранимых reference обнуляются. Иначе создаётся/восстанавливается tap через `0x100049b20`, включается и source добавляется в текущий run loop. Режим run loop не восстановлен в imported stub.

`0x100046648` получает `NSWorkspace.sharedWorkspace.frontmostApplication`, вызывает `0x1001d4b38` для вычисления `forceBlockEventTap`, обновляет tap, читает localizedName, bundleIdentifier, executableURL/path и запрашивает per-app policy через `0x10000b524`. Результат передаётся далее на MainActor. Предикат `0x1001d4b38` ещё не исследован: нельзя объявлять точный список блокируемых приложений.

Есть второй tap: `0x1001ac678` вызывает `CGEventTapCreate(0,0,0,0x1c00,0x1001a6ca4,0)` и после успешного создания отключает его `CGEventTapEnable(...,0)`. Маска keyboard-only. Роль второго tap без callback/callers не установлена; нельзя предполагать, что он дублирует основной постоянно.

## 2. Синтез ввода: несколько путей

| Адрес | Подтверждённый механизм |
|---|---|
| `0x1000812cc` | Итерация списка key descriptors, `CGEventSourceCreate` → `CGEventCreateKeyboardEvent` → `CGEventSetFlags` → `CGEventPostToPid(processIdentifier(app),event)`. Второй event условен от bit0 аргумента |
| `0x100081568` | Аналогичный список, но глобальный `CGEventPost(0,event)` вместо PID |
| `0x1000816c8` | Сам находит frontmostApplication, при отсутствии формирует error, иначе два keyboard events на каждый descriptor и `CGEventPostToPid` |
| `0x1000818d0`, `0x100081b50`, `0x100081e14` | Дополнительные пакетные варианты `CGEventPostToPid`; flags собираются OR по таблице `DAT_1003eac38` |
| `0x1002a4d20` | Тонкий wrapper `CGEventPost(param_2,*param_1)` |

Это доказывает использование синтетических CGEvents и наличие как target-PID, так и global пути. Пара key events согласуется с down/up, но точные булевые аргументы `CGEventCreateKeyboardEvent` потеряны в части stub signatures. Нельзя заявить, что все коррекции используют один из путей, не проследив caller. Unicode insertion, маркировка synthetic event и защита от смены foreground на основании этих helpers не установлены.

## 3. Клавиатурные раскладки

`0x1001a2d08` использует cache, затем `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`, `TISGetInputSourceProperty`, `CFDataGetBytePtr`, `LMGetKbdType`, `UCKeyTranslate`. Видны key action=3, modifier=0, dead-key state и буфер до четырёх UInt16; точные аргументы keyboard type повреждены ABI recovery. Этот helper строит строковое представление key code, а не доказывает основной алгоритм языковой классификации.

`0x10022acd4` — более читаемый Rust-side wrapper. Получает байты layout CFData, вызывает:

```c
UCKeyTranslate(layout, keyCode, 0, modifiers, keyboardType, 0,
               deadKeyState, 4, &length, utf16Buffer);
```

Нулевая длина → sentinel `-1`; длина >4 → panic branch; затем преобразование результата через `0x1003a3f38`. Panic source pointer содержит `src/event_tap/layout.rs`. Большая `0x1002284ac` также читает `kTISPropertyUnicodeKeyLayoutData` и использует `UCKeyTranslate`, но её state machine не восстановлена полностью в этом отчёте.

**Вывод:** раскладка учитывается через системные TIS/Carbon APIs; одной фиксированной таблицей QWERTY→ЙЦУКЕН архитектура не ограничивается. Перечень поддерживаемых input sources, fallback для IME/dead keys и точная политика switching остаются неизвестными.

## 4. Plain paste и восстановление clipboard

Цепочка `0x10002e138` → asynchronous continuation `0x10002e414` → `0x10002e46c` либо `0x10002e4e4` → `0x10002e8a0`. Общий evidence `ev_30dae3181f5c0b3bf48a6ac96df15d19c8fdf21ed7c8911b4892324a35cb4722`.

В `0x10002e138` виден guard флага object+0x90 против повторного входа. Получаются `NSPasteboard.generalPasteboard` и `pasteboardItems`. Ветвь с текстовым типом сохраняет данные, вызывает `clearContents`, `declareTypes` только с `NSPasteboardTypeString`, `setData:forType:`, затем helper синтетических событий `0x100081568` и `Task.sleep(1000000000)` (1 секунда).

Обе continuation ветви вызывают `0x10002e8a0`, который восстанавливает набор объявленных типов и проходит словарь, выполняя `setData:forType:` для каждого сохранённого entry. Флаг повторного входа сбрасывается. Это подтверждает временную подмену clipboard с последующим восстановлением, а не только вызов Cocoa pasteAsPlainText.

Ограничения: не доказано полное сохранение всех pasteboard items (видно словарное сохранение типов/данных); точное shortcut keycode не реконструировано из enum descriptor. В просмотренной цепочке нет вызова `changeCount` и не виден guard от стороннего изменения clipboard во время 1-секундного ожидания. Это риск, требующий dynamic проверки, а не окончательное утверждение о баге. Для нового аналога предпочтительна транзакция с проверкой владения clipboard перед восстановлением.

## 5. Настройки и значения initializer

`0x10002f258` создаёт persisted wrappers через `NSUserDefaults.standardUserDefaults`, helper `0x1001d7120`/`0x1001d7794`. Bool initial values прямо присутствуют перед вызовами. Literal strings проверены дополнительно в Mach-O по сегментам arm64: Swift storage pointer +32, evidence `evidence/native-preferences-literals.json` содержит адреса и file offsets.

| Ключ | Initializer default |
|---|---|
| tech.caramba.switcher.auto-enabled | true |
| tech.caramba.switcher.singleshift-enabled | true |
| tech.caramba.switcher.autocorrect-on | true |
| tech.caramba.switcher.yofikator-on | true |
| tech.caramba.switcher.alt-enabled | false |
| tech.caramba.switcher.splitshift-enabled | false |
| tech.caramba.switcher.paste-no-format | true |
| tech.caramba.switcher.sounds.enabled | true |
| tech.caramba.switcher.last-used-version | Optional String wrapper |
| last_shown_update | Optional String wrapper |
| tech.caramba.switcher.secureinput.last-shown-at-v2 | Date.distantPast |
| caramba.header-color-name | Optional String wrapper |
| tech.caramba.switcher.sounds.main-sound-override | Optional Data wrapper |

Это initializer defaults, не текущие значения пользователя и не гарантия неизменности после migration/remote settings. Семантику исторического имени `splitshift` не следует расширять без callers.

## 6. Исключения и Core Data

`0x10000fafc` создаёт `NSPersistentContainer`, берёт store description и устанавливает:

```c
setOption(NSNumber(true), NSPersistentHistoryTrackingKey);
setCloudKitContainerOptions(nil);
setShouldMigrateStoreAutomatically(true);
setShouldInferMappingModelAutomatically(true);
loadPersistentStoresWithCompletionHandler(...);
```

Следовательно подтверждены history tracking, automatic migration и inference mapping; CloudKit явно не включён на этом description. Путь SQLite/store name и фактический recovery при повреждении из этой функции не восстановлены.

`0x10000b650` fetches AppException: `NSFetchRequest`, `setReturnsObjectsAsFaults(false)`, context fetch; записи без `path` или `bundleID` пропускаются; `enabled=nil` трактуется как false при materialization.

`0x10000b524` нормализует входной bundleID через `lowercased()`. Для собственных `tech.caramba.switcher` / `tech.caramba.switcher.dev` возвращает enum code1. Для dictionary entry false→code1, true→code2; при отсутствии entry→code0. В совокупности с UI это согласуется с policy «по умолчанию / выключено / включено», но enum names отсутствуют, поэтому числовая семантика зафиксирована отдельно от гипотезы.

`0x10000e09c` содержит `AutoswitchExceptionsStore.patternSet` и `regexCache`, `NSRegularExpression.initWithPattern(options:0)`, кеширование через objectForKey/setObject, `matchesInString(options:0,range:0..<length)`. После фильтрации обновляет Combine Published data и множество patterns. Значит есть regex-обработка исключений/фильтрации; нельзя из этой функции заключить, что пользовательский редактор везде принимает регулярные выражения или что regex применяется непосредственно на каждом keystroke. При invalid regex видна обработка NSError и дальнейший fallback `0x100230964`, чья семантика пока неизвестна.

## 7. Login item: macOS 12 и 13+

`0x10006697c` проверяет `_stdlib_isOSVersionAtLeast(13,0,0)`. На 13+ запрашивает `SMAppService.mainAppService.status` и сравнивает с 1; на старой системе вызывает `0x100067504`.

`0x100067504` использует `SMCopyAllJobDictionaries(kSMDomainUserLaunchd)`, ищет поле `Label`, сравнивает с helper identifier и читает `OnDemand`. Это подтверждает отдельный legacy path.

`0x100067788` включает/выключает mainAppService через `registerAndReturnError`/`unregisterAndReturnError`. При enable уже зарегистрированной службы видна последовательность unregister → register; ошибки логируются строкой `Failed to %s launch at login: %s`. `0x100067b6c` отдельно обращается к `loginItemServiceWithIdentifier` и unregister, вероятно cleanup legacy helper; назначение migration пока гипотеза.

## Что необходимо дочитать

1. `0x100230dd8`: dispatch основного event tap и suppression semantics.
2. `0x1001a6ca4`: callback второго tap.
3. `0x1001d4b38`: foreground predicate для forceBlockEventTap.
4. Callers `0x100081*`: точные действия/flags/keycode, варианты retyping и anti-recursion.
5. `0x1002284ac`: layout state machine, retry policy и Unicode handling.
6. `0x100230964`: fallback после regex-path.

Наличие псевдокода всех функций не означает восстановление полного поведения: нужны отдельные proofs по state machines и динамические acceptance tests. Здесь установлены конкретные API-механизмы, storage/config defaults и две важные lifecycle цепочки, без подмены неизвестного догадками.

## Дополнение: nested LoginAtLoginHelper

В отдельной REA/Ghidra session выполнен thin arm64-анализ helper из `Contents/Library/LoginItems/LaunchAtLoginHelper.app/Contents/MacOS/LaunchAtLoginHelper`. Инвентаризация обнаружила 89 процедур, из них 11 in-image `__text`, non-external, non-thunk. Все 11 получили псевдокод; ошибки — 0. Результаты: `decompiled/helper-arm64/`, identity/provenance — `evidence/nested/helper-identity.json`, `helper-procedures.json`, закрытие session target — `helper-close.json`.

Основная логика — helper address `0x1000029a0` (адресное пространство helper, не основного executable): получить собственный bundleIdentifier, заменить suffix и проверить `NSRunningApplication.runningApplicationsWithBundleIdentifier`. Если основной экземпляр отсутствует, вычислить app path из components собственного bundlePath и вызвать `NSWorkspace.launchApplication`; затем `NSApp.terminate`. Если основной экземпляр уже запущен — сразу terminate. Wrapper `0x1000026d0` соответствует Objective-C `applicationDidFinishLaunching:`. Это подтверждает назначение legacy login helper как одноразового launcher без резидентной обработки клавиатуры.

## Дополнение: framework CarambaSwitcherUI

Отдельный arm64 Mach-O framework полностью обработан в пределах discovered `__text` non-thunk functions: **1 441 / 1 441**, 0 ошибок, 23 batch; всего inventory 4 104 procedures (остальные включают thunks/external). Все 1 441 `.c` проверены по адресам inventory; missing — 0. `close_binary` успешен, REA stdio process завершён. Coverage: `decompiled/ui-arm64/coverage.json`; identity: `evidence/nested/ui-identity.json`; inventory: `decompiled/ui-arm64/inventory.json`; evidence batches сохранены и в этой директории, и в `evidence/nested/`. Воспроизведение: `tools/nested_decompile.py` использует отдельную session и не обращается к queue основного executable.

В framework адреса вида `0x2fc78` имеют собственную image base и не сопоставляются напрямую с адресами `0x100...` основного executable. Exported Swift symbols дополнительно деманглированы `nm -g | swift-demangle` в `evidence/nested/ui-exported-symbols.txt`; индекс 22 публичных типов — `ui-type-index.json`.

Сигнатуры уточняют UI-контракт:

- `SettingsPaneView.init` принимает `onToggleFeature`, `onSetOption`, `onDropSound([NSItemProvider])`, `onResetCustomSound`, `onHeaderColorChange`, `onOpenAppStore`, `onPresent(SettingsSheet)`.
- `SettingsPaneState` содержит `splitshift`, `pasteWithoutFormatting`, `optionKeySwitching`, `optionKeySwitchingAvailable`, `licenseValid`, `hasCustomSound`, `version`, `headerColor`; TileState содержит `isOn`, `isForbidden`, `badge`.
- `ExceptionsPaneView.init` принимает массив words, AppRule, handlers добавления/массового удаления через Set<String>, `onSetAppEnabled(String,Bool)`.
- `RuleCreationView.init` имеет внешний validator и completion `(String,Bool)`; значение Bool нельзя определить по одной сигнатуре.
- `PaywallView.init` принимает loading/purchasing/restoring/pending, status, subscription details и callbacks subscribe/manage/restore/retry/support.
- `AboutView`, `DebugInfoView`, `SecureInputAlertView`, `MenuHeaderView`, `RulesFreshnessRowState` подтверждают отдельные экраны и состояния, заявленные локализациями.

Есть более сильное подтверждение пользовательской картинки шапки: framework `0x2fc78`, `ColoredHeader.performDragOperation`, сначала читает `NSPasteboardTypeTIFF` и создаёт NSImage из Data; затем пробует `NSPasteboardTypeFileURL`. Успешный image передаётся `0x2f540`, где видны TIFFRepresentation и сохранение Data в `NSUserDefaults`. `0x30200`, `ColoredHeader.rightMouseDown`, добавляет context menu action `removeHeaderImage`. Таким образом импорт картинки drag-and-drop и её удаление подтверждены вызовами, а не только строкой «Убрать картинку». Точное имя preference ключа и ограничения размеров здесь не восстановлены.

Покрытие относится к декомпиляции обнаруженных функций arm64, а не восстановлению исходного Swift или доказательству runtime поведения всех экранов. x86_64 slices сохранены в исходном universal app, отдельно не декомпилировались.
