# Necaramba

**A free alternative to Caramba Switcher and Punto Switcher for macOS.**

Fix text typed in the wrong keyboard layout, switch layouts with Shift, and keep control of automatic corrections.

[English](#english) · [Русский](#русский) · [GPLv3](LICENSE)

---

## English

### What is Necaramba?

Necaramba is an independent keyboard-layout switcher for Mac. It combines a native Swift input engine with a Flutter settings interface. Its primary use case is switching between English and Russian without retyping a word entered in the wrong layout.

```text
You type:            ghbdtn
Press Shift twice:   привет
Press Shift twice:   ghbdtn
```

The application is free to use. It has no purchase or activation screen. Necaramba is not affiliated with the developers of Caramba Switcher or Punto Switcher; their names describe the type of utility this project offers.

**Status:** an actively developed application, not a claim of complete feature parity or a fully qualified public release. Manual conversion has been confirmed by the project owner in Orca, Chrome, Safari and Spotlight on the local development Mac. Compatibility still depends on the editor and the accessibility information it exposes.

### Features

| Feature | How it works |
| --- | --- |
| Convert the last word | Press **Shift twice** to convert the last word to the other layout. Repeat to switch it back. |
| Convert selected text | Select text in an editable field and press **Shift twice**. Conversion direction is inferred from the text, rather than only the active input source. |
| Switch the input layout | Choose **Shift**, **Alt (Option) + Shift**, **Ctrl + Shift**, or **Off** in Settings. |
| Automatic layout correction | Enable it in Settings. A physical **Space** completes the word and triggers a conservative dictionary-based check. |
| Spotlight support | The app resolves the actual focused field, reads the full word before the caret and verifies the selected replacement range. |
| Word exceptions | Add words that should be excluded from automatic correction. |
| Application policies | Configure per-application behavior in Exceptions. |
| Plain-text paste | An optional **⌘⇧V** command pastes text without formatting in supported fields. |
| Additional shortcuts | Settings expose optional Option-based manual correction and left/right Shift control of automatic mode. |
| Launch at login | A switch at the top of Settings requests registration with macOS and displays the reported system status. |
| Appearance and feedback | Change the header color/image, choose a correction sound or turn sound off. |
| Local statistics and maintenance | View aggregate correction counters, export diagnostics and import/export a settings archive. |
| Interface languages | English and Russian; the interface follows the app's localization setup. |

The selected layout shortcut fires once after releasing the keys, provided no text was typed while holding them. Double Shift remains available for text conversion regardless of this setting.

#### Automatic correction is deliberately conservative

- The current automatic mode checks unambiguous dictionary matches of at least three letters after a physical Space.
- Enter and Tab do not trigger this replacement path.
- Unknown or ambiguous words are left unchanged.
- The first word after Enter is tracked without a leading space. After pasting or moving the caret, readable fields can prove the word starts at the beginning of the field or after whitespace; opaque fields use a fresh uninterrupted physical capture when no interrupted token or paste is known. They cannot verify unseen text before the captured word.
- Manual conversion is useful for words that the automatic dictionary does not recognize.
- Typo correction, double-capital correction and restoration of `ё` are not enabled in the current live automatic pipeline. Their additional-correction controls are unavailable.

Manual and automatic modes have different compatibility requirements. A working manual conversion in an editor does not automatically qualify that editor for automatic replacement.

### First launch and permissions

1. Build the application using the instructions below and launch a consistent copy of `Necaramba.app`.
2. Open **Access** or follow the permission onboarding screen.
3. Grant **Accessibility** and **Input Monitoring** access in macOS System Settings when requested.
4. Return to Necaramba and refresh the permission status. Relaunch it if macOS requires that step.
5. Enable the desired shortcuts and, optionally, automatic correction.
6. Try `ghbdtn` in an editable field and press Shift twice.

These permissions are needed to observe keyboard shortcuts and replace text in another application's focused field. Necaramba does not grant itself permissions. Password fields, Secure Input and fields whose focus/selection cannot be established safely are skipped.

Closing the settings window does not quit the native input service. Use the application menu to quit Necaramba completely.

### Launch at login

Open **Settings → Launch at login**. This means launching after you sign into your macOS account, not running before login.

On macOS 13 and later, the native backend uses `SMAppService`. macOS may require approval in its Login Items settings. The app displays that pending state instead of claiming the service is already active. An unavailable status is not confirmation that registration succeeded; inspect any returned error and the system Login Items list.

The project includes a legacy helper path for macOS 12, but its registration status cannot currently be verified authoritatively through that backend. Login behavior on macOS 12 and across real logout/login cycles remains unqualified.

### Privacy and safety

- Keyboard-layout analysis and text conversion run in the native Swift layer.
- Text entered in other applications is not forwarded to the Flutter/Dart settings interface.
- Input buffers are used for conversion; diagnostics record operation stages and status codes rather than typed text.
- Settings, explicit word exceptions and aggregate counters are stored locally.
- The current app configuration has no production rule-update or word-sharing endpoint. Optional sharing infrastructure requires a preview and explicit confirmation when configured.
- A replacement is reported as verified only after checking the resulting text, caret and field identity. Some terminal-style fields expose too little text information for that proof; their explicit manual fallback has narrower guarantees.

### Requirements and compatibility

| Item | Status |
| --- | --- |
| Platform | macOS; no Windows or Linux application is provided |
| Deployment target | macOS 12+ |
| Architectures | Universal build targeting Apple Silicon (`arm64`) and Intel (`x86_64`) |
| Primary layout pair | English ↔ Russian |
| Build toolchain | Xcode, Swift and Flutter pinned in `App/.flutter-version` |
| Verified locally | Development and interaction testing on the local Apple Silicon Mac |
| Still to qualify | Real Intel/macOS 12 execution, broader editor coverage, distribution signing/notarization and release performance |

Not every field can be edited through macOS accessibility APIs. Secure fields, active composition and unsupported custom editors may be skipped. IME and additional keyboard variants are not covered by the current compatibility claim.

### Build from source

Use macOS with Xcode and its command-line tools installed. Install the Flutter version recorded in [`App/.flutter-version`](App/.flutter-version); Dart is bundled with Flutter. See the [toolchain notes](docs/release/flutter-toolchain.md) for the qualified SDK revision.

From the repository root:

```sh
swift test
cd App
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

The resulting application is:

```text
App/build/macos/Build/Products/Release/Necaramba.app
```

For reliable permission persistence between local builds, configure your own stable signing identity as described in [local signing](docs/release/local-signing.md). The machine-specific signing file is ignored by Git. Do not commit signing credentials or private keys.

A local Release build is an optimized development artifact. It uses an explicitly marked development rule package; it is not equivalent to a notarized public release. Keep universal builds enabled when targeting Intel as well as Apple Silicon.

### Architecture

Necaramba follows **Clean Architecture**. Domain logic is separated from macOS adapters and the UI.

```text
Sources/NecarambaCore/     Platform-independent types, ports, word tracking,
                          gestures, layout conversion and rule validation
Sources/NecarambaMac/      macOS input, Accessibility, storage, application
                          use cases, lifecycle and native bridge adapters
App/lib/domain/           Dart entities and repository contracts
App/lib/data/             Native-channel implementations and state decoding
App/lib/features/         Flutter feature interfaces
App/lib/presentation/     Workspace, state orchestration and shared UI
App/macos/Runner/         Composition root, app menu and settings window
Tests/                    Swift tests
App/test/                 Flutter tests
Corpora/                  Independent dictionaries and evaluation fixtures
Tools/                    Replay, corpus, packaging and release tools
```

The native service owns keyboard processing. Opening Settings creates the Flutter interface on demand; text conversion does not depend on keeping that window open.

### Development and verification

The main checks are `swift test`, `flutter analyze` and `flutter test`. From the repository root, additional tools include:

```sh
swift run ReplayRunner
swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split holdout --output Reports/review-v3-quality.json
swift Tools/Release/validate-release-report.swift docs/release/release-report.json
```

Corpus and release gates may intentionally fail while quality targets or required evidence are incomplete. Passing unit tests is not proof of compatibility with every application or of release readiness. See [acceptance status](docs/implementation/acceptance-status.md) and [implementation reports](docs/implementation/reports).

For bug reports, include the macOS version, application and field type, active input layouts, the shortcut sequence and a harmless example of expected/actual output. Avoid passwords or personal text. New input-engine changes should include a regression test and preserve secure-field and focus checks.

### License and acknowledgements

Necaramba is free software licensed under the **GNU General Public License, version 3 only** (`GPL-3.0-only`). See [LICENSE](LICENSE) for the full terms. Copyright © 2026 Necaramba contributors.

You may use, modify and redistribute the program, including commercially, under GPLv3. When distributing covered versions, provide the corresponding source code under the same license and preserve the required notices. The program is provided without warranty.

Independent dictionary sources retain their own notices; see [corpus provenance](Corpora/README.md), [English notices](Corpora/Sources/en/README_en_US.txt) and [Russian notices](Corpora/Sources/ru_RU/README_ru_RU.txt). Those notices must be preserved regardless of the license selected for Necaramba's own code.

Some specifications and historical reports describe an earlier commercial design. They document project history; the current user-facing application has no purchase or subscription screen.

---

## Русский

### Что такое Necaramba?

**Necaramba — бесплатная альтернатива Caramba Switcher и Punto Switcher для macOS.** Это независимый переключатель раскладки для Mac: системная часть написана на Swift, интерфейс настроек — на Flutter. Основной сценарий — переключение между английской и русской раскладками без повторного набора слова.

```text
Вы набрали:             ghbdtn
Дважды нажали Shift:     привет
Ещё раз двойной Shift:   ghbdtn
```

Приложение бесплатно: в интерфейсе нет покупки и активации. Проект не связан с разработчиками Caramba Switcher и Punto Switcher; их названия используются для описания назначения программы.

**Статус:** приложение активно развивается. Полное совпадение возможностей с другими переключателями и готовность публичного релиза пока не заявляются. Владелец проекта подтвердил ручное переключение в Orca, Chrome, Safari и Spotlight на локальном Mac. Совместимость зависит от конкретного редактора и доступности его текстового поля через Accessibility.

### Возможности

| Функция | Как работает |
| --- | --- |
| Исправление последнего слова | **Двойной Shift** переводит слово в противоположную раскладку. Повторное нажатие возвращает его обратно. |
| Преобразование выделенного текста | Выделите текст в редактируемом поле и дважды нажмите Shift. Направление определяется по самому тексту, а не только по текущей раскладке. |
| Смена системной раскладки | В настройках можно выбрать **Shift**, **Alt (Option) + Shift**, **Ctrl + Shift** или **Выключено**. |
| Автоматическая коррекция | После физического нажатия **пробела** приложение проверяет завершённое слово по словарю. |
| Поддержка Spotlight | Определяется настоящий владелец фокуса, полное слово читается из поля, диапазон замены проверяется перед вставкой. |
| Слова-исключения | Добавляйте слова, которые не должны исправляться автоматически. |
| Правила для приложений | Настраивайте поведение для отдельных приложений в разделе исключений. |
| Вставка без форматирования | Дополнительное сочетание **⌘⇧V** вставляет обычный текст в поддерживаемых полях. |
| Дополнительные сочетания | Доступны настройки ручной коррекции через Option и управления автоматическим режимом через левый/правый Shift. |
| Автозапуск | Тумблер в начале настроек запрашивает запуск при входе в macOS и отображает системный статус. |
| Оформление и звук | Цвет и изображение шапки, собственный звук исправления или отключение звука. |
| Статистика и обслуживание | Счётчики исправлений, экспорт диагностики, импорт и экспорт архива настроек. |
| Языки интерфейса | Английский и русский. |

Выбранное сочетание переключает раскладку один раз после отпускания клавиш, если во время удержания не набирался текст. Двойной Shift для преобразования текста работает независимо от этого выбора.

#### Особенности автоматической коррекции

- Текущий режим исправляет однозначно распознанные словарём слова длиной от трёх букв после физического пробела.
- Enter и Tab не запускают этот сценарий замены.
- Неизвестные и неоднозначные слова остаются без изменений.
- Первое слово после Enter отслеживается без начального пробела. После вставки текста или перемещения курсора в читаемых полях проверяется начало слова: начало поля или пробельный символ перед ним. В полях, не раскрывающих текст, используется новый непрерывный набор, если не было известной вставки или прерванного слова. Проверить невидимый текст перед набранным словом в таких полях невозможно.
- Для слов, которых нет в словаре, можно использовать ручное переключение.
- Исправление опечаток, двух заглавных букв и восстановление `ё` пока не включены в действующий автоматический режим. Соответствующие дополнительные настройки недоступны.

Ручная и автоматическая коррекция имеют разные требования к совместимости. Успешный двойной Shift в редакторе ещё не означает, что для него квалифицирована автоматическая замена.

### Первый запуск и разрешения

1. Соберите приложение по инструкции ниже и запускайте одну и ту же копию `Necaramba.app`.
2. Откройте раздел **Доступы** или следуйте экрану первоначальной настройки.
3. По запросу предоставьте **Универсальный доступ / Accessibility** и **Мониторинг ввода / Input Monitoring** в системных настройках macOS.
4. Вернитесь в Necaramba и обновите статус разрешений. Если macOS требует перезапуск, перезапустите приложение.
5. Включите нужные сочетания клавиш и, при желании, автоматическую коррекцию.
6. Наберите `ghbdtn` в редактируемом поле и дважды нажмите Shift.

Разрешения нужны для обработки сочетаний клавиш и изменения текста в активном поле другого приложения. Necaramba не выдаёт себе доступ самостоятельно. Поля паролей, Secure Input и поля с неподтверждённым фокусом или выделением пропускаются.

Закрытие окна настроек не завершает нативную службу ввода. Для полного выхода используйте меню приложения.

### Автозапуск

Откройте **Настройки → Запускать при входе в систему**. Речь идёт о запуске после входа в учётную запись macOS, а не до авторизации пользователя.

На macOS 13 и новее используется системный механизм `SMAppService`. Если macOS требует подтверждения в разделе объектов входа, приложение показывает ожидающий статус. Недоступный статус не означает, что регистрация прошла успешно: проверьте полученную ошибку и список объектов входа в системных настройках.

Для macOS 12 в проекте есть старый механизм через вспомогательное приложение, но его состояние пока нельзя достоверно прочитать через этот адаптер. Автозапуск на macOS 12 и после реального выхода/входа в систему ещё не квалифицирован.

### Конфиденциальность и безопасность ввода

- Анализ раскладки и преобразование текста выполняются в нативной части на Swift.
- Ввод из других приложений не передаётся в интерфейс Flutter/Dart.
- Буферы ввода используются для преобразования; диагностика записывает этапы операции и коды состояния, а не набранный текст.
- Настройки, явно добавленные исключения и агрегированные счётчики хранятся локально.
- В текущей конфигурации нет production-адресов обновления правил и отправки слов. Предусмотренный механизм отправки требует предварительного просмотра и явного подтверждения, если он настроен.
- Замена считается подтверждённой после проверки итогового текста, курсора и идентичности поля. Некоторые терминальные поля скрывают текст от Accessibility; для них предусмотрен отдельный ручной путь с более ограниченными гарантиями.

### Требования и совместимость

| Параметр | Состояние |
| --- | --- |
| Платформа | macOS; приложения для Windows и Linux нет |
| Минимальная целевая версия | macOS 12+ |
| Архитектуры | Universal-сборка для Apple Silicon (`arm64`) и Intel (`x86_64`) |
| Основная пара раскладок | Английская ↔ русская |
| Инструменты сборки | Xcode, Swift и Flutter из `App/.flutter-version` |
| Локальные проверки | Разработка и интерактивные проверки на Apple Silicon Mac |
| Ещё требуется проверить | Реальную работу на Intel/macOS 12, дополнительные редакторы, подпись и notarization публичного выпуска, показатели производительности |

Accessibility не предоставляет одинаковых возможностей во всех приложениях. Защищённые поля, активный составной ввод и нестандартные редакторы могут пропускаться. IME и дополнительные варианты раскладок не входят в текущие заявления о совместимости.

### Сборка из исходников

Нужны Mac, Xcode с command-line tools и версия Flutter из [`App/.flutter-version`](App/.flutter-version). Dart входит в Flutter. Точная квалифицированная ревизия SDK описана в [документе об инструментах](docs/release/flutter-toolchain.md).

Из корня репозитория:

```sh
swift test
cd App
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

Результат сборки:

```text
App/build/macos/Build/Products/Release/Necaramba.app
```

Для стабильного сохранения разрешений между локальными сборками настройте собственную подпись по [инструкции](docs/release/local-signing.md). Машинный файл подписи исключён из Git. Закрытые ключи и учётные данные не должны попадать в репозиторий.

Локальная Release-сборка — оптимизированный артефакт разработки с явно помеченным development-пакетом правил. Она не равнозначна нотарифицированному публичному релизу. Сохраняйте universal-режим сборки, если нужна поддержка Intel вместе с Apple Silicon.

### Архитектура

Проект использует **Clean Architecture**: доменная логика отделена от адаптеров macOS и интерфейса.

| Каталог | Назначение |
| --- | --- |
| `Sources/NecarambaCore/` | Независимые типы и порты, буферы слов, жесты, преобразование раскладки, проверка правил |
| `Sources/NecarambaMac/` | Ввод и Accessibility macOS, хранение, прикладные сценарии, жизненный цикл и bridge |
| `App/lib/domain/` | Dart-сущности и контракты репозиториев |
| `App/lib/data/` | Реализации нативных каналов и декодирование состояния |
| `App/lib/features/` | Интерфейсы отдельных функций на Flutter |
| `App/lib/presentation/` | Общее окно, управление состоянием и общие компоненты UI |
| `App/macos/Runner/` | Сборка зависимостей, меню и окно настроек |
| `Tests/`, `App/test/` | Swift- и Flutter-тесты |
| `Corpora/` | Независимые словари и корпуса проверки |
| `Tools/` | Инструменты воспроизведения событий, оценки качества, упаковки и выпуска |

Клавиатуру обрабатывает нативная служба. Flutter-интерфейс создаётся при открытии настроек; держать окно открытым для работы переключателя не требуется.

### Разработка и проверки

Основные команды — `swift test`, `flutter analyze` и `flutter test`. Дополнительные проверки из корня репозитория:

```sh
swift run ReplayRunner
swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split holdout --output Reports/review-v3-quality.json
swift Tools/Release/validate-release-report.swift docs/release/release-report.json
```

Проверки корпуса и выпуска могут завершаться с ошибкой, пока пороги качества или обязательные свидетельства не собраны. Успех unit-тестов не подтверждает работу во всех приложениях и готовность релиза. Подробности — в [матрице готовности](docs/implementation/acceptance-status.md) и [отчётах реализации](docs/implementation/reports).

В сообщении об ошибке укажите версию macOS, приложение и тип поля, активные раскладки, последовательность нажатий и безопасный пример ожидаемого/полученного текста. Не включайте пароли и личные данные. Изменения механизма ввода должны сопровождаться регрессионными тестами и сохранять проверки фокуса и защищённых полей.

### Лицензия и сторонние материалы

Necaramba — свободное программное обеспечение под **GNU General Public License, только версия 3** (`GPL-3.0-only`). Полный текст находится в [LICENSE](LICENSE). Copyright © 2026 Necaramba contributors.

Программу можно использовать, изменять и распространять, в том числе коммерчески, на условиях GPLv3. При распространении охватываемых лицензией версий необходимо предоставлять соответствующие исходники под той же лицензией и сохранять обязательные уведомления. Программа предоставляется без гарантий.

Независимые словари имеют собственные условия использования: [происхождение корпуса](Corpora/README.md), [английский словарь](Corpora/Sources/en/README_en_US.txt), [русский словарь](Corpora/Sources/ru_RU/README_ru_RU.txt). Эти уведомления сохраняются независимо от лицензии собственного кода Necaramba.

Некоторые спецификации и старые отчёты описывают предыдущий коммерческий вариант проекта. Это история разработки: в текущем пользовательском интерфейсе экранов покупки и подписки нет.
