# Necaramba

Независимая реализация переключателя раскладки для macOS: Flutter/Dart интерфейс, Swift/AppKit системная часть, Clean Architecture. Целевая платформа — macOS12+, Apple Silicon и Intel.

**Текущий статус: проверяемый прототип, не готовый полный аналог Caramba.** Подробности — в [матрице готовности](docs/implementation/acceptance-status.md). Автоматическая коррекция закрыта проверкой качества и совместимости редакторов. Отчёты не подменяют испытания на реальных macOS12/Intel. Коммерческие сервисы, MAS и подписанный выпуск пока не квалифицированы.

Ручное преобразование по двойному Shift больше не ограничено списком приложений: оно проверяет активное текстовое поле. Для пустых терминальных полей есть отдельный путь по недавно набранным физическим клавишам, без подтверждённой истории отмены. Пароли, Secure Input и поля без необходимого доступа к фокусу/выделению не обрабатываются. Подробности и ограничения — в [отчёте ручной коррекции](docs/implementation/reports/manual-active-fields.md).

## Сборка

Требуются Xcode и Flutter версии из `App/.flutter-version` (Dart поставляется с Flutter).

```sh
swift test
cd App
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

Локальный результат: `App/build/macos/Build/Products/Release/Necaramba.app`. Build Release здесь — оптимизированный локальный прототип с явно помеченным development-словарём; это не production distribution. Сборка включает собственный звук и лицензии независимых словарей. Образец Caramba и результаты декомпиляции в продукт не входят.

Окно настроек создаёт Flutter-движок по требованию; меню и нативные службы живут отдельно. Приложение не выдаёт себе разрешения. Доступ к вводу и Accessibility запрашивается отдельными явными действиями пользователя. Автозапуск выключен до явного включения.

## Архитектура

- `Sources/NecarambaCore`: типы, порты, буфер/жесты, языковые решения, правила политик, проверка пакетов, измерение качества.
- `Sources/NecarambaMac`: адаптеры macOS, хранение, транзакции ввода, обновления, нативные use cases и bridge.
- `App/lib/domain`, `data`, `features/*/presentation`: доменные контракты, адаптеры каналов и интерфейс. Введённый в других приложениях текст в Dart не передаётся.
- `App/macos/Runner`: composition root, меню, Flutter-окно и drag/drop.

## Проверки и ограничения

```sh
swift run ReplayRunner
swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split holdout --output Reports/review-v3-quality.json
swift Tools/Release/validate-release-report.swift docs/release/release-report.json
```

CorpusRunner и release validator сейчас должны возвращать ненулевой код: пороги/физическая проверка и выпуск ещё не пройдены. Исторические измерения сохраняются; синтетические сценарии не объявляются испытаниями реальных редакторов.

Утверждённая [спецификация](docs/superpowers/specs/2026-10-14-necaramba-design.md), [план](docs/superpowers/plans/2026-10-14-necaramba-plan.md), [отчёты реализации](docs/implementation/reports), [условия выпуска](docs/release/release-inputs.md).
