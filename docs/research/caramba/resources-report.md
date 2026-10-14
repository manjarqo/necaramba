# Caramba Switcher Pro: ресурсы, декларации UI и модели

Дата исследования: 2026-10-14. Только статическое чтение установленного `.app`; приложение не запускалось, пользовательские данные не читались. Этот отчёт не доказывает исполнение обработчиков, точность алгоритма и доступность каждого экрана во время работы.

## Объект и доказательства

`Contents/Info.plist`: bundle `tech.caramba.switcher`, версия `2026.09.22`, build `20260922.2`, минимум macOS `12.0`, `LSUIElement=true`, `NSMainStoryboardFile=Main`. Это приложение-агент с меню, без обычного обязательного Dock UI. Метаданные сборки: Xcode 27.0, macOS SDK 27.0; эти поля не повышают minimum deployment target.

Сохранены файлы в `evidence/`:

- `resources-inventory.json`: относительные пути, размеры и SHA-256 56 файлов ресурсов/Info.plist.
- `resources-info.json`: Info.plist.
- `resources-localizations.json`: русские и английские таблицы `.strings`, включая вложенные bundles.
- `resources-assets.json`: полный результат `xcrun assetutil --info` двух каталогов.
- `resources-models.json`: разобранные keyed archives всех восьми `.mom`, без запуска кода приложения.
- `resources-nib-strings.json`: сырые строки семи nib.
- `resources-rea-ib.json`: REA `decode-interface-builder`, evidence ID `ev_6cd81b33280f8dd1b0fbee6a09dca065efecec515a655d7de45cc6974b5ba56c`; семь nib, 350 объектов и 74 связи. Все семь документов отмечены `hierarchy_complete=true`. Это полнота распознанных полей архива, а не динамического UI.
- `resources-rea-ui-labels.json`: компактная проекция ключей, development captions и actions из REA графа.

Сокращения ниже: **U** = `Resources/CarambaSwitcherUI_CarambaSwitcherUI.bundle/Contents/Resources/ru.lproj/Localizable.strings`; **L** = `Resources/ru.lproj/Localizable.strings`; **E** = `Resources/ru.lproj/Exceptions.strings`; **M** = `Resources/Base.lproj/Main.storyboardc/MainMenu.nib`. Полные таблицы сохранены с точными путями.

## Каталог функций, заявленных ресурсами

| Функция/сценарий | Точный источник | Что доказано и что остаётся неизвестным |
|---|---|---|
| Автоматическая смена раскладки | U `Autoswitching`, `Autoswitching on`, `Autoswitching off`; asset `feature-tiles/autoswitching` | Есть настройка и состояния; алгоритм/порог не в ресурсах |
| Исправление опечаток | U `Mistype`; asset `feature-tiles/autocorrect` | Есть отдельная функция; набор замен неизвестен |
| Ёфикатор | U `Yofikator`; asset `feature-tiles/yofikator` | Есть функция; словарь и политика неоднозначных слов неизвестны |
| Один Shift меняет активную раскладку | U `**Single Shift** — change currently active keyboard layout` | Точная пользовательская подсказка; тайминги и стороны Shift не установлены |
| Double Shift либо Option переключает набранное слово или выделение | U `**Double Shift** or Option — switch typed word or selection`, `**Option** — switch the typed word or selection` | Два варианта подсказок; их режимы выбора нужно исследовать в коде/динамике |
| Left Shift + Right Shift включает/выключает auto | U `**Left Shift + Right Shift** — turn automatic switching on and off` | Есть жест и UI-индикация; одновременность/окно времени неизвестны |
| Вставка без форматирования | U `**Command + Shift + V** — paste text without formatting` | Подсказка относится к Switcher; широкий выбор любой клавиши в рекламе Clear не доказан для Switcher |
| Звук переключения и собственный звук | U `Sound`, `Remove custom sound`; asset главного bundle `switch_sound` | Есть встроенный звук и удаление пользовательского; форматы/импорт неизвестны |
| Пользовательские правила для слов | U `For words`, `Caramba will not autocorrect these words`, `Word`, `This word is untouchable`; E `DeG-P5-Gzn.title`, `S2x-DJ-lQj.title` | Слова/сочетания можно исключить из исправления; точная семантика matching неизвестна |
| Добавление/удаление/очистка правил | L `Add a new rule`, `Add to Rules`, `Add to User Rules`, `Are you sure you want to delete this rule?`, `Delete all rules?`, `This action cannot be undone.` | Подтверждены UI-тексты действий и предупреждений |
| Поделиться правилом с разработчиками | L `Share this word to improve the app`, `Send to developers`; E `oEz-5I-PaU.title` | Есть отдельный opt-in текст отправки; канал и payload неизвестны |
| Правила для приложений | U `In apps`; E `Wp8-nN-1kz.title`; L `Select Application`, `appex.autoswitching-on/off` | Тексты поддерживают настройку поведения по приложению, вкл/выкл; старый development caption nib говорит только об отключении — не считать это пределом нового UI |
| Обновляемые правила | L `rules.freshness.checking/current/today/yesterday`, `rules.freshness.a11y.hint`; U `Click to check for rule updates now`, `Updated %@` | Есть ручная проверка и отображение свежести; фоновые интервалы/подпись пакета не установлены |
| Автозапуск | M `toggleLaunchAtLogin:`, caption `bRd-nP-Zzs.title`; L `trouble.notification.launch-at-login` | Есть действие и предупреждение о ненастроенном запуске |
| Accessibility onboarding | L `setup.accessibility.permission.*`, `setup.accessibility.success.*`; отдельный `CarambaKit_CarambaAccessibility.bundle` | Инструкция открыть настройки, drag icon, ожидание разрешения, переход в настройки приложения |
| Диагностика Secure Input | L `trouble.notification.secure-input`, `.extended.app`, `.extended.loginwindow`, `.action` | Тексты различают блокирующую программу и loginwindow; метод определения владельца неизвестен |
| Диагностика разрешений и лицензии | L `trouble.notification.universal-access`, `.license`, `.license-trial`, `.version` | Есть уведомления и переход `attemptTroubleshooting:` в M |
| Статусы в строке меню | Главный Assets.car: `statusbar`, `_inactive`, `_error`, `_warning`, `_update` | Есть пять визуальных состояний; приоритеты неизвестны |
| Всплывающий feedback auto on/off | `SplitshiftEnabled.nib`, `SplitshiftDisabled.nib`, соответствующие view nib | `PopupWindow`; development captions ✅/❌, цвета `PopupBackgroundColor`, размер view 47×32 и шаблон окна 64×32; фактический runtime layout не проверен |
| Настройки, исключения, о программе, выход | M `showSettings:`, `showUserDictionary:`, `orderFrontStandardAboutPanel:`, `manualExit:` | Доказаны target-action декларации |
| Техническая информация и копирование | U `Debug information`, `Copy to clipboard`, `Copied`, `Send this to support when requested by us.`; L `preferences.debug-info-copied` | Состав диагностических данных не установлен |
| Поддержка и информационные ссылки | U `Feedback`, `contact support`, `Privacy Policy`, `End User License Agreement`, `Caramba Switcher Pro website` | Есть UI; URL здесь не содержатся |
| Лицензирование | U `LICENSE`, `subscribe`, `restore purchases`, `manage subscriptions`, pending/loading/purchasing/refunded/expired/next-renewal тексты | Есть состояния покупки и восстановления; ресурсы одновременно содержат старую годовую непродлеваемую лицензию и подписку, поэтому фактические продукты не определены |
| Пробный период | L `buy.fourteen-day-trial.*`, U `trial valid until`, `trial expired on %@` | Есть текст 14 дней; фактическое StoreKit предложение не проверялось |
| Изменение условий покупки, ошибки | L `licensing-error.purchase-conditions-changed*`, `purchase-failed`, `purchase-restoration-failed` | Предусмотрены ошибки и повторное подтверждение новых условий |
| Family sharing approval | U `Awaiting Family Organizer's approval` | Есть состояние ожидания; доступность семейного доступа отдельно не доказана |
| Оформление | U `preferences.remove-image`; assets `header-colors/*`, 25 именованных цветов | Есть удаление картинки и палитра; импорт картинки/механизм выбора цвета по ресурсам не доказаны |
| Статистика экономии времени | L `time-saved-days/hours/minutes/weeks-short` | Есть форматтеры; наличие актуального экрана/расчёт неизвестны |

## Ресурсы, которые нельзя ошибочно включать в feature parity

U содержит `More apps from Caramba Lab`, `Caramba Timer`, `Time and Day`, `Caramba Clear`, `Secret project`; assets содержат `promo/timer`, `promo/timeday`, `promo/clear`, `promo/secret`. Таймер на одной клавише, полноэкранные часы и произвольный hotkey plain paste описывают рекламируемые отдельные приложения. Их нельзя объявлять функциями Switcher только по соседству строк.

M включает типовое меню AppKit: Find/Replace, Spelling and Grammar, Substitutions, Speech, Upper/Lower/Capitalize, Cut/Copy/Paste. Эти декларации могут работать только в собственных text controls через responder chain. Они не доказывают глобальную коррекцию грамматики, озвучивание текста других приложений либо отдельные продуктовые модули.

`CarambaKit_CarambaKeyboardShortcuts.bundle` содержит строки проверки конфликта системного shortcut и пункта меню, режима записи и «Пробел». Наличие recorder-компонента не доказывает, какие именно действия Switcher допускают произвольное переназначение.

## Модель локального хранения

`Resources/Caramba.momd/VersionInfo.plist` объявляет текущую модель `Caramba.8`. В приложении есть восемь `.mom` и optimized `Caramba.8.omo`. Модель подтверждает Core Data, но не путь store, настройки миграции или шифрование.

| Entity / поле | Тип декларации | Optional / default |
|---|---|---|
| AppException.enabled | Boolean (800) | optional, no default |
| AppException.bundleID | String (700) | optional |
| AppException.path | String (700) | optional |
| AutoswitchException.pattern | String (700) | optional; validation length >= 1, <= 100 |
| AutoswitchException.additions | Integer32 (200) | optional; 0 |
| AutoswitchException.visible | Boolean (800) | optional; false |
| AutoswitchException.disabled | Boolean (800) | optional; no default |

Валидация `pattern` закодирована через NSComparisonPredicateOperator 3 (>=) с 1 и 1 (<=) с 100. Optional=true означает, что правило модели о длине не равно безусловному запрету nil во всех путях кода. Семантика `additions` не выводится из имени поля. `Caramba.2` содержит историческую entity `AppStats`, в текущей модели её нет; текущую статистику нельзя приписать этой таблице.

## Прочие наблюдения и границы

Основные локализации — en/ru. Recorder bundle дополнительно содержит de/ar/zh-Hans/ja/zh-TW/es/sk/cs/ko/hu/pt-BR/fr/nl; это не доказывает перевод всей программы на эти языки. В UI bundle есть шрифт `Sen.ttf`. В главном Assets.car есть asset `model.macos`, но имя не доказывает нейросетевую модель; его формат нужно исследовать отдельно.

В перечисленных loose resources нет текстовых словарей, help/html, JSON-конфигурации правил, xib или исходных storyboard. Отсутствие loose файла не доказывает отсутствие данных: они могут быть встроены в код, asset catalog, загружаться по сети или генерироваться.

Для спецификации ресурсы дают широкий каталог заявленных сценариев, но недостаточны для точного восстановления поведения: требуются доказательства алгоритма переключения, буфера слова/выделения, клавиатурных mapping, cancellation/undo, работы в Secure Input, сетевого протокола и приоритетов app/word rules. Новая реализация должна использовать собственные строки/иконки/звуки, сохраняя функциональное назначение.

## Дополнение: извлечение встроенной модели и звука

Из `Assets.car` системным `NSDataAsset(name:bundle:)` извлечены два ресурса. Воспроизводимый Swift-скрипт: `evidence/resources-assets/extract.swift`. Он создаёт `Bundle(url:)` и читает данные asset; не вызывает `Bundle.load`, `dlopen`, executable приложения либо пользовательские cache. Сетевые запросы к разработчику не выполнялись. Извлечённые bytes сохранены в исследовательских evidence для локальной проверки; переносить их в новый продукт не требуется.

| Ресурс | Размер | Формат / SHA-256 |
|---|---:|---|
| model.macos | 1 565 707 B | Magic `CLM1`; `3f411eef7a1a6d502c1029924a9c982761d319fc67d23f16b34c725fdfcb3f69` |
| switch_sound | 10 031 B | UTI `public.mp3`; MPEG layer III v1, 128 kbps, 44.1 kHz, joint stereo; `2c815e607c254411a3134f33b62c9e50a4aadea1bf8db362a9cc589e9d7e480c` |

Первые 16 байт модели: `43 4c 4d 31 01 00 00 00 00 01 00 51 df 0b b9 b9`. Значения полей после magic здесь не интерпретируются без кода парсера. Стандартная zstd frame magic `28 b5 2f fd` не встречается ни в одной позиции файла; это не исключает raw compressed blocks, контейнерную обработку или шифрование. Высокая энтропия payload сама по себе также не различает эти варианты. Полные параметры и первые 128 байт — в `evidence/resources-assets/inspection.json`.

**Вывод:** дистрибутив действительно содержит готовый payload начальной модели `model.macos` формата `CLM1`, доступный локально без скачивания. Это существенно сильнее прежнего наблюдения одного имени asset и подтверждает наличие bundled offline модели. Успешную загрузку этой модели, fallback при сетевой ошибке и конкретный состав словарей надо подтвердить путём исполнения либо чтения парсера. Предыдущая оговорка о неизвестном формате asset выше уточняется этим извлечением; утверждать нейросетевую архитектуру оснований по-прежнему нет.
