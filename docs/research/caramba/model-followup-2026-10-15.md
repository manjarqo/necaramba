# CLM1: воспроизводимое локальное извлечение и структура модели

Дата: 2026-10-15. Read-only анализ установленного Caramba Switcher Pro 2026.09.22 (build 20260922.2) и ранее сохранённых артефактов. Приложение не запускалось для извлечения; пользовательские настройки, лицензия, TCC, сеть разработчика и продукт Necaramba не использовались и не менялись. Словари, ключевой материал и полные правила в этот отчёт не включены.

Это уточнение к `resources-report.md` и `core-model-findings.md`: прежнее ограничение «payload не расшифрован» теперь снято для конкретного bundled asset. Полная поведенческая эквивалентность оригиналу этим не доказана.

## Доказательства и воспроизводимость

Все 56 файлов установленного bundle, перечисленных в `evidence/resources-inventory.json`, повторно проверены по SHA-256: совпадают. Источник модели — `Contents/Resources/Assets.car`, NSDataAsset `model.macos`, ранее извлечённый в `evidence/resources-assets/model.macos.bin`.

Локальные инструменты и выходы находятся только в ignored `docs/research/caramba/evidence/model-followup/`:

- `extract_local.py`: статически читает сохранённый Mach-O и CLM1, восстанавливает обработку bundled model, пишет `model.zst` и `model.protobuf`.
- `inspect_wire.py`: ограниченный protobuf wire parser, агрегаты размеров без печати слов.
- `inspect_graph.py`: независимый читатель double-array графов, локальные `*-graph-records.json`.
- `model-wire.json`: упорядоченные top-level wire fields с точными base64 payloads, включая любые неизвестные вложенные поля; обратная сборка побайтово совпала с исходным plaintext.
- `export_neutral.py`: семантическое представление `model-neutral.json`. Оно сохраняет извлечённые правила, признаки, вставки и графовые записи, но не объявляется побайтовым сериализатором исходного protobuf.
- `extraction-summary.json`, `wire-summary.json`, `graph-summary.json`, `semantic-summary.json`, `validation-summary.json`: размеры, хэши и результаты проверок.

Запуск из корня репозитория: последовательно `python3 docs/research/caramba/evidence/model-followup/{extract_local,inspect_wire,inspect_graph,export_neutral}.py` — каждый файл отдельной командой. Использованы уже установленные Python-модули `Crypto.Cipher.ChaCha20` и `zstandard`; новое ПО не устанавливалось. Оригинальный executable не исполняется. Extractor проверяет заранее установленные SHA-256 executable и модели, semantic exporter — SHA-256 plaintext. Wire parser отклоняет усечённые/переполненные varints, недопустимые tags и wire types, выход за длину; пять malformed fixtures отклонены. Graph reader проверяет размер, bounds, cycles, глубину <512 и лимит миллиона records/stack entries. Эти исследовательские инструменты и outputs не включать в distribution.

## Pipeline

1. `0x1002af5dc` проверяет magic/version/reserved, размер и идентификатор записи ключа; затем вызывает проверку подписи над header+payload.
2. `0x1002b6598` получает 32-байтный материал из Mach-O, выполняя четыре сложения по модулю 2⁶⁴. Его helper `0x1002a5c3c` разрешает адрес. Декомпилятор неверно восстановил ABI этого вызова: возврат адреса, реально используемый через `x0`, подтверждён `otool -tvV` по диапазону `0x1002b6598…0x1002b6654`. Не следует буквально переносить неверный псевдокод с неизменяемым `plVar1`.
3. `0x1002b9e20`: ChaCha20, 10 двойных раундов, 32-битный counter в слове 12, начальный counter 0, 96-битный nonce. Побайтовая локальная реконструкция даёт валидную стандартную zstd frame (`28 b5 2f fd`).
4. `0x1002a764c`: распаковка. Независимая zstd-библиотека успешно распаковывает полный payload без дополнительного словаря; frame dictionary ID 0, checksum отсутствует, content size в frame не указан, window size 134 217 728 байт.
5. `0x1002af994` и `0x1002a8ea0`: protobuf wire decode, tag/wire validation, вложенные сообщения. Структура полностью разобрана локальным reader; top-level decode/re-encode побайтово совпал.

| Часть | Размер, байт | SHA-256 |
|---|---:|---|
| CLM1 | 1 565 707 | `3f411eef7a1a6d502c1029924a9c982761d319fc67d23f16b34c725fdfcb3f69` |
| Расшифрованная zstd frame | 1 565 617 | `2fceb0ac3040de3d7bf52f8d71889f1823fd1c31aa4f408e30cc495cc919eaf2` |
| Protobuf plaintext | 3 048 802 | `56748978947d16fa70ac336ff1a3977e756869d4e09c9b51e65cb6615827ce38` |

CLM1 header: magic [0,4), version [4]=1, reserved [5]=0, big-endian identifier [6,10)=1, nonce [10,22), big-endian payload length [22,26), payload [26,26+N), 64-байтная подпись в хвосте; полный размер N+90.

**Ограничение:** исследовательский extractor не реализует проверку подписи. Оригинальный parser выполняет её перед расшифровкой; локальное успешное распаковывание и ссылки между таблицами не являются независимой криптографической аутентификацией. Ключевой материал не опубликован в отчёте. Никакой проверки/модификации платной лицензии не выполнялось.

## Схема и объёмы

Root `Logos`, все присутствующие поля wire type 2:

| Tag | Поле | Размер вложенного payload | Состав |
|---|---|---:|---|
| 1 | version | 11 | `26.09.22.01` |
| 2 | kbm | 851 686 | DAWG + index feature sets + languages |
| 3 | appex | 11 637 | DAWG + index app-rule sets |
| 4 | feats | 112 | behaviors, focus settings, timings |
| 5 | autocorrect | 2 185 340 | graph + rules + insert pool |

### KBM

Tags: 1 version (отсутствует в bundled message, protobuf default), 2 dawg bytes, 3 repeated map entry, 4 repeated language map entry. Entry tag1 — integer key; tag2 — FeatureSet. FeatureSet tag1 — repeated Feature. Feature tags: 1 lang, 2 signed weight (negative values представлены обычным protobuf signed-int varint, не zigzag), 3 is_known_word, 4 is_case_sensitive, 5 is_double_caps_preventative. Language entry tag1 — ID, tag2 — UTF-8 string.

Граф 830 468 байт, 207 616 units, **165 913 pattern keys**, **607 feature sets**, **1 700 features**. Все terminal IDs графа точно разрешаются в 607 записях index. Вес от −20 до 5. 59 features с known_word, 862 с case_sensitive, 69 с double_caps_preventative. Это количества признаков, а не количества известных слов.

Языковые пары: 0 `ru-en`, 1 `el-en`, 2 `ru-de`. Наличие этих данных не доказывает доступность всех пар в UI установленной macOS-сборки.

### Appex

Tags: 1 version (отсутствует), 2 dawg, 3 repeated index entry. Entry: tag1 ID, tag2 RuleSet; RuleSet tag1 — packed repeated integer rule codes.

Граф 11 268 байт, 2 816 units, **486 patterns**, **29 rule sets**; все terminal IDs разрешаются. Обнаружены 16 разных кодов: 4353, 4354, 4356, 4357, 4358, 4359, 4361, 5122, 8449, 8450, 8453, 8454, 8457, 8705, 8706, 8710. Их полная семантика здесь не восстановлена; нельзя автоматически считать их boolean app exclusions.

### Autocorrect

Tags: 1 graph bytes, 2 repeated AutocorrectRule, 3 repeated UTF-8 insert_pool.

Rule tags: 1 prefix_len, 2 suffix_len, 3 insert_id, 4 case_sensitive, 5 is_yofikator. Отсутствующие scalar поля имеют default 0/false. Граф 1 544 196 байт, 386 048 units, **72 595 patterns**, **72 595 rules**, **2 419 вставок**. Terminal values ровно 0…72 594, взаимно однозначно соответствуют индексам rules. Все insert_id находятся внутри insert_pool. 19 071 rules case_sensitive, 6 593 rules is_yofikator. prefix_len 0…28; suffix_len 0…26.

Это набор операций над совпадениями и общий пул вставок, а не готовый список независимых пар «плохое слово → хорошее слово». До подтверждения вызывающего кода нельзя выдавать prefix_len/suffix_len за число символов для удаления, удержания или за UTF-16 offsets.

### Feats

Tags: 1 repeated SpecialBehavior, 2 repeated switch_to_en_on_focus strings, 3 delay_between_layout_activation_and_backspaces, 4 delay_between_backspaces_and_retyping, 5 layout_switch_num_retries, 6 layout_switch_retry_delay, 7 splitshift_delay.

Bundled значения: 3 special behaviors; 7 строк focus switching; delays 25 / 25; retries 2; retry delay 25; splitshift_delay 100. Единицы времени и применение последних значений следует связывать с конкретными callers; сами protobuf integers не являются доказательством миллисекунд. SpecialBehavior записи в нейтральном JSON сохранены как три отдельные группы raw wire fields, без выдуманной enum-семантики.

## DAWG encoding и независимый matcher

Формат подтверждён и bytes, и `0x1002b0cf0` / `0x1002b0e38`:

- uint32 little-endian N, затем N uint32 little-endian units; длина каждого файла ровно 4+4N.
- root index 0; offset(unit) = `(unit >> 10) << ((unit >> 6) & 8)`.
- Для входного UTF-8 byte c: `next = current XOR offset(unit[current]) XOR c`.
- Переход допустим, если `(unit[next] & 0x800000ff) == c`, с обязательными bounds checks.
- bit8 означает terminal. Value читается из `unit[next XOR offset(unit[next])] & 0x7fffffff`.
- `0x1002b0cf0` возвращает значения всех terminal-prefix совпадений, `0x1002b0e38` также сохраняет длину совпадения. Iterators `0x1002b85b8` / `0x1002b7914` вызывают их для последовательных стартовых позиций.
- Все извлечённые ключи валидны как UTF-8. Контрольный byte 0x02 встречается только в начале, 0x03 — только в конце ключа. Это согласуется с boundary anchors; окончательный контракт подготовки строки требует caller analysis.

Ключи KBM распределены: без anchors 42 169; только end 22; только start 68 350; оба 55 372. Autocorrect: без anchors 8 229; только end 3 854; только start 29 243; оба 31 269. Следовательно, подсчёт keys нельзя называть количеством отдельных слов: часть ключей — внутренние/начальные/конечные фрагменты.

Независимый движок может реализовать этот формат декларативно: валидировать units и IDs, готовить вход согласно подтверждённому Unicode/boundary контракту, получать совпадения, разрешать feature/rule references, применять отдельно реализованные операции. Перенос машинного кода не нужен. Однако extractor и matcher ещё не определяют порядок правил, сравнение языковых scores, tie-breaking, порог переключения, регистровую политику и безопасную доставку результата в поле ввода.

## Evidence IDs и границы

- `ev_91cb3b37c66e6d9e3a064de80dc69a6c3f1893f4438e89398615f7e6c97acbcd`: `0x1002af5dc`, `0x1002a764c`, `0x1002af994`, `0x1002a8ea0`, `0x1002b0cf0`, `0x1002b0e38`, `0x1002b0fa8`, `0x1002b1280`.
- `ev_76e1cde49eb22601d9aa34d608b185cb16081110c909580bbafe3a6902f4cd3e`: `0x1002b6598`, `0x1002b9e20`, `0x1002b71a8`, `0x1002b7914`, `0x1002b85b8`.
- `ev_9961908752ad1ed810679a79ef7b7cba951646a7a575b73c171c560a30c5049f`: `0x1002a5c3c`.

Файлы псевдокода: `docs/research/caramba/decompiled/main-arm64/<address>.c`. Скрипты и агрегаты — новое локальное воспроизводимое доказательство, не новый REA Evidence ID. Новая REA native session не создавалась.

Происхождение словарного корпуса, условия его лицензии и право распространения модельных данных остаются **не установлены**. В установленном Contents не найдено license/notice/copying/copyright/legal-named файлов; общая EULA-строка не является отдельной лицензией на корпус. Публичный GPLv3 Necaramba не получает автоматически прав на эти данные. Модель и полный нейтральный JSON остаются локальными исследовательскими артефактами и не добавляются в продукт или публичный git.
