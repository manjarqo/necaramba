# Caramba: уточнение поведенческих правил, 2026-10-15

## Метод и границы

Read-only анализ уже сохранённой REA/Ghidra декомпиляции arm64 сборки 2026.09.22 (20260922.2). Новая REA-сессия и оригинальное приложение не запускались; пользовательские данные, настройки и документы не читались. Изменён только этот отчёт. Проприетарные ресурсы и псевдокод в продукт не переносились.

Retained image: `evidence/binaries/caramba-arm64`, SHA-256 `814173224502cb0c40d8dadc01fa7f73c6fbcf98336067c10d9fc453780bf27e`. Псевдокод содержит неверно восстановленные Rust/Swift ABI, переменные-регистры и предупреждения type propagation. Ниже отделены непосредственно читаемые условия от интерпретации. «Доказано» означает статическое доказательство конкретной ветви, не подтверждённое исполнение полного пользовательского сценария.

## Источники REA

Каждый адрес соответствует `decompiled/main-arm64/<address>.c`; Evidence ID взят из заголовка файла.

| Метка | Процедуры | Evidence ID |
|---|---|---|
| E1 | `0x1001d4b38` foreground predicate | `ev_a0d76538b6cdd7086a167c715fd3f3edb0705c210fb8d86e3cec5ce709e9197f` |
| E2 | `0x100224414`, `0x100227778`, `0x100227d6c`, `0x100222440` | `ev_c6c2a1d89bfd8a6c9d9ee547301799329271a9201f9e3f7a74d832e9f489fafb` |
| E3 | `0x100230964` fallback | `ev_9f3544eb6be3228a8fc0dc9aaad1da07010914c4c61c172b75dda17cb2c050a7` |
| E4 | `0x1002b6384`, `0x1002b6404` token gates | `ev_76e1cde49eb22601d9aa34d608b185cb16081110c909580bbafe3a6902f4cd3e` |
| E5 | `0x1002abe88`, `0x1002b36b4`, `0x1002abc80`, `0x1002b20c8`, `0x1002b5d18`, `0x1002ae3fc`, `0x1002b153c` | `ev_91cb3b37c66e6d9e3a064de80dc69a6c3f1893f4438e89398615f7e6c97acbcd` |
| E6 | `0x10022a2f4` layout conversion support | `ev_753b2a9116934a36b80240968ba17c28445d0a4f5e3315fa252f84331ce02e8d` |

## B01. Foreground blocking: конкретное приложение

E1: при отсутствии bundle identifier predicate возвращает false. Иначе выполняются lowercase и trimming через `CharacterSet.whitespaces`, затем сравнение с одной константой.

Константа проверена непосредственно в retained Mach-O: Swift storage `0x1004a03a0`, строковые bytes по `+32`, длина 27: `com.apple.systempreferences`. Для проверки адрес был переведён в file offset по `LC_SEGMENT_64`; приложение не исполнялось. Следовательно predicate истинный для этого нормализованного ID, а не для произвольного перечня приложений. Caller `0x100046648` использует predicate для `forceBlockEventTap`, lifecycle `0x100046c10` снимает tap при этом флаге (предыдущий `native-findings.md`, §1).

Независимый тест: missing ID → false; uppercase/окружающие обычные пробелы → true; `com.apple.systempreferences.other` → false. Не следует объявлять неизвестный ID разрешением на редактирование: это лишь конкретный original predicate. В Necaramba безопасность и app-policy устроены отдельно; глобально отключать все функции Settings без собственного продуктового решения не требуется.

## B02. Точный набор байтов границы

E4, `0x1002b6384`: пустая строка → false. Иначе проверяется последний byte: меньше 46 и соответствующий бит маски `0x200100002600` установлен. Декодирование маски даёт **TAB (9), LF (10), CR (13), Space (32), hyphen-minus (45)**. Точка, запятая, `!`, `?`, NBSP сюда не входят.

E4, `0x1002b6404` использует эту же проверку как один из двух альтернативных путей принятия. Второй путь декодирует UTF-8, отклоняет uppercase после первого символа и сравнивает результат вспомогательного подсчёта с 2. Константа минимального количества и uppercase scan видны, но Ghidra смешивает указатель с возвращённым count; нельзя уверенно объявить единицей длины graphemes вместо scalars.

E2, state machine, строки 735–745, вызывает `0x1002b6404` перед `0x100227778` и дальнейшим преобразованием. `0x1002b6384` также вызывается в нескольких других ветвях. Это доказывает **предикат кандидата**, а не утверждение, что каждый Enter/Tab обязательно исправляет слово. Порядок подавления/воспроизведения Enter и отправки сообщения не восстановлен.

Necaramba conservative runtime принимает только физический Space и минимум три символа. Тестируемое расширение: отдельная политика границ с различием Space, hyphen и submit/navigation keys. Не включать обработку Enter путём простой замены `keyCode == 49`: редактор мог уже отправить сообщение.

## B03. Gate автоматического решения: функции, Backspace, модификаторы

E2, `0x100227778`:

- Если все три feature bytes по смещениям `0x153`, `0x154`, `0x155` неактивны, возвращается false до дальнейшего анализа. Конкретные имена трёх полей из этой процедуры не доказаны.
- Key code `0x33` (Backspace) приводит к false; отдельный state bit `0x151` ведёт в ту же запретительную ветвь.
- При Control разрешённый путь требует самого Control key (`0x3b`/`0x3e`) и отсутствия Option; при Option — самого Option key (`0x3a`/`0x3d`) и отсутствия Command. Command имеет отдельные исключения для самих modifier keys (`0x37`/`0x36`). Обычный символ с Command/Control/Option отвергается.
- При определённом варианте сохранённого состояния выполняются два `memcmp`: если сохранённый текст является префиксом текущего **или** текущий является префиксом сохранённого, возвращается false. Сравниваются bytes и длины, не только полное равенство.

Последний guard пригоден как основание для собственного предотвращения повторного исправления при допечатывании или удалении хвоста. Нельзя пока назвать его гарантированно «отмена пользователем»: кто записывает соответствующий вариант состояния и когда он очищается, полностью не прослежен. В Necaramba нужны свои regression cases: изменение после исправления, Backspace, продолжение слова, reset после разделителя/смены поля. Не копировать числовые offsets или enum tags.

## B04. Double capitals выполняются раньше последующих стадий

E5, `0x1002b36b4`, строки 157–288: при включённом field byte `+0x2b`, успешной проверке через vtable `+0x28` и длине не менее трёх декодируются первые три символа. Проверяются uppercase первого и второго (ASCII и Unicode helper), lowercase третьего. Затем создаётся преобразованный кандидат и передаётся в `0x1002b153c`; устанавливается флаг выполненной стадии.

Статический порядок: эта стадия предшествует вызову следующей стратегии через vtable `+0x18`, а затем обработке через `0x1002ae3fc` под двумя другими flags. Имена/полный mapping flags к UI autocorrect/yofikator не установлены. Проверка первых трёх символов **не равна** доказательству, что весь хвост обязан быть lowercase: такого scan в данной ветви нет. Не доказаны также словарный критерий vtable `+0x28` и точное преобразование всего Unicode-хвоста.

Necaramba `RuleIndex.doubleCapsCandidate` требует lowercase **всего** хвоста, а `LinguisticEngine` выполняет эту стадию после layout и exact typo. Поэтому интересные differential cases: `HEllo`, `HElloWorld`, `ПРивет`, `ПРиветМир`, аббревиатуры, неизвестные слова и сочетание двойных заглавных с неправильной раскладкой. Без наблюдения не менять tail policy на основании одного положительного prefix test.

## B05. Нет изменения — нет повторной downstream-обработки результата

E5, `0x1002b36b4`, строки 288–339: после стратегии vtable `+0x18` сравниваются обе пары length+bytes исходного и возвращённого представлений. Если обе равны, флаг изменения остаётся нулевым, временные результаты освобождаются. При различии запрашивается дополнительное состояние через vtable `+0x20` и заменяется кандидат. Аналогичная проверка length+memcmp видна после `0x1002ae3fc`.

Независимо реализуемый инвариант: no-op правило не должно создавать исправление, переключать раскладку или увеличивать статистику. Necaramba уже проверяет различие candidate/result в Core; полезно сохранить этот инвариант при добавлении комбинированной коррекции. Семантика двух представлений и статистики оригинала из этих ветвей не следует.

## B06. Общий префикс — физические записи, не просто буквы

E2, `0x100222440`: при разрешённом состоянии и непустом диапазоне функция проходит пары записей с шагом 32 bytes. Совпадение требует равенства 64-bit поля записи и равенства преобразованного набора modifier bits. Возвращает количество начальных совпавших записей, останавливаясь на первом различии; запретительный флаг или пустой диапазон → 0.

E2, state machine строки 900–982: оптимизация вызывается только после дополнительного predicate `0x10022ed0c` и включённого state byte по `param_1 + 0x2b`. Ненулевой результат ведёт к отбрасыванию общего префикса перед `0x10022c820`, журналируя `Optimizing retyping: skipping...`.

Нельзя заменить это произвольным longest-common-prefix строк без собственного доказательства Unicode/keyboard/selection корректности. Для Necaramba пригодна независимая оптимизация по **проверенному AX тексту** и UTF-16 диапазону, но это другой механизм. Тесты должны сохранять весь префикс, выделение, combining sequences и повторное переключение; сначала нужен correctness, затем сокращение событий.

## B07. Fallback исключений не является ещё одним regex

E3, `0x100230964`: входной CF-объект удерживается/преобразуется в строку; запрашиваются две раскладки через `0x1002282ec`, языковые literals **ru** и **en**. `ru` подтверждён bytes по VA `0x1003fa055`; `en` виден в псевдокоде. `0x10022a2f4` пробует получить физическое представление; при отсутствии успешного варианта возвращается 0. Далее варианты переводятся через `0x100229f60`, проверяются через `0x100227d6c`, и результат определяет возврат 0/1. Внутри этого fallback не обнаружено вызова NSRegularExpression.

E2, `0x100227d6c`: single-count результат сразу отклоняется; затем вызывается model helper `0x1002abc80`; при его отрицательном результате подключается `0x1002b5d18`. Последний содержит порог count <8 и несколько matcher calls; семантика matcher tables и полное правило не восстановлены. E5, `0x1002b20c8`: результаты обходятся; наличие item с установленным low bit поля +24 возвращает 1. Значение этого флага без схемы нельзя называть known-word/exclusion.

Caller `0x10000e09c` действительно имеет regex cache, compile, `matchesInString`, а при ошибке компиляции попадает в этот fallback. Он также выполняет публикацию/фильтрацию store. Поэтому пока нельзя заявлять, что пользовательские исключения во время набора имеют regex matching или что fallback означает literal match. Практический следующий шаг — восстановить caller аргументы и model flag schema. Добавлять regex в Necaramba на этих основаниях преждевременно.

## Что можно внедрять независимо и что ещё исследовать

1. Уже достаточно точны для собственных тестов: no-op инвариант; запрет корректировки при обычных Command/Control/Option chords; Backspace не запускает автоматическую коррекцию; отдельный delimiter predicate; нормализация bundle ID.
2. Требуют проектного решения и qualification: hyphen/Tab/Enter correction, prefix suppression после ручной правки, объединённые typo/layout/double-caps стадии, сокращение retyping.
3. Пока не восстановлены: classifier weights/confidence, модель app profiles, точная семантика fallback исключений, Unicode double-caps tail policy, точный порядок подавления submit keys, ранняя коррекция и все тайминги жестов.
4. Текущий `Resources/Rules/independent-v1.json` содержит 179000 lexemes, 4 typo rules и 3 ё rules. `RuleIndex` использует membership, не frequency classifier; production conservative path выключает typo/ё. Эти реальные пробелы не закрываются чтением имён схемы CLM1. Нужны независимо созданные правила/корпус; proprietary CLM1 остаётся вне продукта.

## Проверка отчёта

Evidence IDs сверены с headers перечисленных `.c`. Маска границ декодирована программно по каждому byte 0…45. Swift string и ru/action labels прочитаны из retained image посредством сегментной адресации; исходный image SHA-256 вычислен выше. Полные правила оригинала, runtime parity, физических тестов и новых тестов Necaramba этот отчёт не объявляет пройденными.

## Дополнение: модель декодирована, classifier ABI уточнён

Позже в этой же исследовательской сессии другой исследователь декодировал модель в локальный ignored `evidence/model-followup/model-neutral.json`. Поэтому прежние сообщения о невосстановленном payload — исторический статус, не состояние после этого дополнения. Здесь использованы схема и типы, а не перенос proprietary pattern records в продукт. KBM schema: graph → feature-set ID; feature содержит `lang`, signed `weight`, `is_known_word`, `is_case_sensitive`, `is_double_caps_preventative`; languages связывает ID с парой языков. Autocorrect: graph → rule ID, rule содержит prefix/suffix byte counts, insert ID и два флага. Проверка самой расшифровки принадлежит отдельному отчёту владельца модели.

Дополнительные процедуры E5: `0x1002b4398`, `0x1002b1280`, `0x1002b0cf0`, `0x1002b2630`, `0x1002b32ec`, `0x1002b2e3c`, `0x1002b1e04`, `0x1002b24b4`, `0x1002b5020`, `0x1002ae134`, `0x1002b0fa8`, `0x1002b5124`. Дополнительные процедуры E4: `0x1002b85b8`, `0x1002b8f18`, `0x1002b8724`, `0x1002b8a14`. Evidence IDs прежних групп сверены по заголовкам.

### C01. Feature layout и case matching

`0x1002b8f18` преобразует compact12-byte model feature в runtime40-byte record: flags по +24, language ID по +32, signed32 weight по +36. Flags формируются из compact bytes8/9/10 как bits0/1/2 соответственно. Сопоставление compact bytes с полями подтверждено parser `0x1002a8ea0`: **bit0 known word, bit1 case sensitive, bit2 double-caps preventative**.

`0x1002b4398`:

1. Преобразует вход через lowercase helper `0x1003a43c4`, собирает graph matches, пропускает только features с case-sensitive bit=0.
2. Сканирует исходный ввод, пропускает только features с bit=1.
3. Для каждого feature разрешает language ID лишь если его пара строк равна текущей паре либо её перестановке. Одного числового lang ID без language table недостаточно.

Две ветви разделены флагом, поэтому одна case-insensitive feature не считается ещё раз в original pass. Другие дубли сохраняются.

### C02. Overlap и кратность

`0x1002b85b8` вызывает graph lookup для каждого **byte offset** от начала до конца входа, увеличивая начало на один byte. `0x1002b0cf0` проходит successive bytes и выдаёт ID каждого terminal prefix по мере его достижения, а не только longest prefix. `0x1002b1280` собирает iterator в vector без deduplication. `0x1002b4398` расширяет каждый такой ID в список features, также без множества уникальности.

Следствие для этой цепочки: overlapping matches допустимы; одинаковый feature-set ID, встретившийся в разных местах или через разные graph patterns, вносит свой список features повторно. Scores суммируются **по occurrences**, не по unique IDs. Case passes фильтруются, как описано выше. Для независимых тестов нужны repeated-pattern и overlapping-prefix случаи; замена этой логики на `Set` неверна.

### C03. Score действительно вычисляется; Ghidra его потеряла

`0x1002b32ec` в псевдокоде ошибочно представлен как возвращающий только enum. Прямое disassembly retained arm64 image закрывает ABI gap:

- `0x1002b3460` загружает weight из +0x24; `0x1002b3464` проверяет ноль; `0x1002b3468` добавляет nonzero weight в 32-bit accumulator w19.
- `0x1002b347c…3488`: только zero-weight features объединяют known/unknown flags.
- `0x1002b3540…3554`: выбирается category в w0.
- `0x1002b34ac`: score возвращается отдельно через x1. Callers читают его как signed32.

Контракт для разрешённой language pair:

| Условие | Category | Score |
|---|---:|---|
| Нет zero-weight assertions | 1 | сумма всех nonzero weights |
| Есть zero-weight known=true, нет zero-weight known=false | 2 | та же сумма |
| Есть хотя бы один zero-weight known=false | 3 | та же сумма |

Unsupported language pair возвращает category0. Category3 побеждает category2 при наличии обеих assertions. `is_known_word` у **nonzero** feature не влияет на category в этой функции. Arithmetic машинная int32; overflow policy для новой реализации следует определить явно, а не зависеть от Swift trap.

### C04. Выбор RU/EN, ties, отсутствие положительного порога

`0x1002b1e04` находит именно RU и EN представления и передаёт их `0x1002b2e3c` в порядке **RU, затем EN**. Наличие других language pairs в модели не доказывает, что эта стратегия их использует.

`0x1002b2e3c` обходит два кандидата:

- Category0 пропускается.
- Category1: сохраняется первый; последующий заменяет его только при **строго большем signed score**. Disassembly `0x1002b2fb4…2fb8` — signed compare и branch `le`, сохраняющий прежний кандидат при равенстве. Фиксированного positive threshold или minimum margin в этом выборе нет; отрицательные scores тоже сравниваются.
- Category2 хранится отдельно и предпочитается category1; следующий category2 заменяет предыдущий. Поэтому два category2 здесь выбирают второй, EN, а не сами по себе образуют collision.
- Любой category3 устанавливает блокирующее состояние; окончательно возвращается специальный blocked/collision variant, независимо от прочих кандидатов.
- Отдельный флаг отмечает путь, где все реально рассмотренные scored candidates имели нулевой score; пропуск category0 сбрасывает этот флаг. Caller `0x1002b1e04` не принимает обычный выбранный результат с этим флагом. Это точнее, чем правило «maxScore должен быть >0».

Таким образом equal nonzero scores в этой RU-first стратегии сохраняют RU; два нулевых scored результата приводят к abstain. Не следует превращать ни tie preference, ни class3 в универсальный алгоритм «исходное слово известно — ничего не делать»: это другая политика Necaramba.

State machine `0x100224414`, строки1098–1174, проверяет collision byte результата; при нём не идёт обычная replacement chain, а обновляет сохранённое состояние и пишет `caramba_collision`. Это связывает blocked variant с поведением, но не доказывает все последующие условия снятия блокировки.

### C05. Feature gating double caps

`0x1002b24b4` собирает features и возвращает false, если хотя бы у одного установлен bit2; иначе true. С учётом подтверждённой схемы это `is_double_caps_preventative`. Независимая реализация может иметь собственный prevent-list/flag, но потребуется отдельная проверка wiring вtable: наличие helper не является полным доказательством, что каждая double-caps ветвь вызывает именно его.

## Дополнение: точная часть autocorrect interpreter

### A01. Pattern material и anchors

`0x1002ae3fc` получает matches через `0x1002ae134`: сначала исходная форма, затем при наличии uppercase — lowercase; второй набор дополняет первый, отбрасывая совпадения с тем же matched byte string и rule ID. Это deduplication **autocorrect**, а не описанного выше KBM score iterator.

`0x1002b5020` выбирает один из formatting templates: start marker и, для завершённого слова/forced boundary, end marker. Retained image содержит у `0x1004a59d5` bytes `01 02 c0 01 03 00`, у `0x1004a59db` — `01 02 c0 00`: Rust format-template encoding со STX (U+0002), placeholder, optional ETX (U+0003). Эти bytes сами по себе не являются буквальным префиксом всей строки. `0x1002ae3fc` явно удаляет scalars U+0002/U+0003 из matched material до построения replacement (условие mask `0x1ffffe`, строки423–445), подтверждая роль sentinel markers.

Дополнительная disassembly проверка всей `0x1002b5020` и чтение `0x10021ddc8` (E2) уточняют **primary framing полностью**: сначала trim whitespace обоих концов; далее `STX + trimmed + ETX`, если mode byte ненулевой либо последний Unicode scalar **исходного** текста входит в TAB/LF/CR/Space/hyphen; иначе `STX + trimmed`. Оригинальные pointer/length сохраняются до trim и используются для boundary decision, возвращённые x0/x1 — для placeholder. Таблица whitespace по VA `0x10044739f` и ветви helper дают набор U+0009…000D,0020,0085,00A0,1680,2000…200A,2028,2029,202F,205F,3000. Поэтому NBSP с концов удаляется, но сам по себе не добавляет ETX; конечный hyphen добавляет ETX и сохраняется в material. Empty input без force даёт только STX; whitespace-only input с конечным обычным Space — STX+ETX.

Если первичный набор пуст, есть fallback нормализация входа и повторный lookup. Видны ветви удаления конечной пунктуации и начальных `-`/`(`; полный набор punctuation mask и смысл всех branch combinations здесь ещё не формализованы. Поэтому простое `STX + rawInput + ETX` не объявляется полным original preprocessing contract.

### A02. Prefix/suffix — bytes, не scalars и не UTF-16

`0x1002ae3fc`, строки462–518, загружает rule как16-byte запись: uint32 prefix_len, uint32 suffix_len, uint32 insert_id, два flag bytes. Требует существующий insert и `prefix_len + suffix_len <= matchedMaterialByteLength`.

Построение однозначно: **первые prefix_len bytes очищенного matched material + bytes insert_pool[insert_id] + последние suffix_len bytes material**. Копирование выполняется `memcpy` с byte lengths; после сборки `0x1003a96f8` проверяет UTF-8. Несуществующий ID, слишком длинные сохраняемые края или невалидная UTF-8 строка не должны превращаться в текстовую замену. Для собственной реализации обязательны tests на Cyrillic/emoji и разрез внутри multibyte scalar.

### A03. Применение и порядок

Список matches строится до применения правил. Затем цикл `0x1002ae3fc` идёт по этому списку, меняя current text после каждого принятого правила. На следующем шаге модели заново не запрашиваются. В этой цепочке не видно longest-match sort или сортировки по weight (autocorrect rule вообще не имеет weight).

Case-sensitive branch применяет exact substring replacement к текущему тексту: single-byte fast path меняет все совпадающие bytes; general path использует substring iterator и собирает префиксы, replacement и остаток. Это global nonoverlapping application данного matched material, а не только исходный occurrence offset. Перекрытия между **разными** правилами зависят от порядка списка и уже выполненных изменений.

Case-insensitive branch вызывает `0x1002b5124`, который декодирует Unicode, сравнивает case-normalized scalars и переносит регистр через Unicode conversion helpers. Это значительно точнее literal case-insensitive string equality, но полный контракт регистровой проекции при изменении длины ещё не восстановлен. Не заменять его простым «весь lowercase/title/uppercase» и не называть такую упрощённую реализацию parity.

Отдельные typo/ё flags проверяются перед применением; кроме `is_yofikator` ветви имеется проверка изменения, отличающегося одним U+0451. Полная Unicode diff/case ветвь не закрыта, поэтому один флаг модели пока не объясняет все способы классификации замены как ё.

## Оставшиеся точечные gaps после нового анализа

- KBM basic scanner, кратность, case flags, language-pair filter, score и RU/EN selector достаточно конкретны для независимого generic core с **собственными synthetic fixtures**. Полное приложение всё ещё включает дополнительные gates и иной preprocessing fallback.
- Autocorrect byte-splice и exact application достаточно конкретны; preprocessing fallback, Unicode case projection, dynamic ё detection и порядок исключений ещё требуют анализа. Не объявлять весь interpreter восстановленным.
- Основной ABI blocker score снят именно disassembly: Ghidra утрачивала второе return register. Primary framing/trim также уточнён disassembly. Остальные проблемные места локализованы: trait vtable target mapping в `0x1002b36b4`, preprocessing fallback `0x1002b2630` и Unicode replacement helper `0x1002b5124`.
- Для воспроизведения machine-code проверки использован `xcrun llvm-objdump -d --start-address=0x1002b3430 --stop-address=0x1002b355c evidence/binaries/caramba-arm64`, плюс диапазон `0x1002b2f90…0x1002b3090`. Это дополнительная локальная сверка retained image, а не новый REA Evidence ID или runtime test.

## Следующий проход: fallback classifier и dynamic ё

### C06. Fallback preprocessing теперь восстановлен

Источник E5 `0x1002b2630`, E4 `0x1002b6d7c`, `0x1002baf90`, `0x1002b8724`. Это уточняет прежний открытый вопрос C02/A01. Речь о classifier fallback; похожую autocorrect fallback ветвь не следует автоматически считать идентичной по всем маскам.

1. Выполняется primary framing и сбор features. **Любой непустой feature vector возвращается сразу**. Нулевой итоговый score, unknown assertion или отсутствие known feature не запускают fallback.
2. Если vector пуст, выполняется Unicode whitespace trim исходного текста. Complete/incomplete состояние берётся из forced mode/конечного scalar исходного ввода, как в A01; оно не пересчитывается по очищенному тексту.
3. У trimmed текста удаляется максимальный конечный run символов из одного из двух наборов:

| Режим | Набор trailing scalars | Исходная маска со смещением U+0021 |
|---|---|---|
| Incomplete | `!`, `(`, `)`, `+`, `=`, `_` | `0x4000000010000581`, допустимое смещение ≤62 |
| Complete | `!`, `$`, `&`, `(`, `)`, `*`, `+`, `-`, `/`, `?`, `@`, `^` | `0x20000000c00057a9`, допустимое смещение ≤61 |

4. Затем удаляется максимальный начальный run только `-` и `(`. После обоих удалений ещё раз выполняется Unicode whitespace trim. Это один проход стадий: после второго trim punctuation removal заново не запускается.
5. Создаются два framed strings: сначала очищенная форма, затем исходная whitespace-trimmed форма. Оба получают тот же complete/incomplete framing.
6. `0x1002b6d7c → 0x1002baf90` выполняет stable uniqueness **строк** по длине и bytes; равные варианты не сканируются дважды.
7. `0x1002b8724` последовательно получает features для этих строк и конкатенирует их. Unique strings не означают unique feature IDs: overlaps/повторы features внутри lookup остаются.

Наборы punctuation декодированы программно из констант; это не предположение по категории Unicode punctuation. Например dot/comma не входят ни в один набор. Не следует заменять их `CharacterSet.punctuationCharacters`. Synthetic cases: same prepared variants сканируются один раз; разные variants сохраняют порядок; первичный отрицательный/нулевой feature предотвращает fallback; leading/trailing runs и whitespace между ними проверяются отдельно.

### A04. Dynamic ё — difference относительно множества, не edit distance

Источники: E5 `0x1002ae3fc` строки594–807; `0x1002a52c8`, Evidence `ev_9961908752ad1ed810679a79ef7b7cba951646a7a575b73c171c560a30c5049f`.

Если `rule.is_yofikator` установлен, сразу выбирается ё-категория. Если нет:

1. Код строит hash set lowercase Unicode scalars **текущего полного текста**, а не только matched material. Unicode mapping helper `0x1003a9fe4` может возвращать до трёх scalars на исходный scalar; результаты добавляются в множество.
2. `0x1002a52c8` перечисляет lowercase scalars построенного replacement, пропуская scalars, присутствующие в source set. В этой ветви список результата не превращается в отдельное множество: повторные новые scalars могут выдаваться повторно.
3. Dynamic ё-категория выбрана, только если первый выданный scalar равен U+0451 и следующий вызов iterator возвращает конец.
4. Effective ё требует включённый второй flag argument `param_6`; обычное исправление — первый `param_5`. Отключённая соответствующая категория пропускает правило до изменения текста. Metadata принятого изменения хранит effective category.

Следствие: этот predicate **не доказывает** позиционное `е → ё`, равную длину, отсутствие удалений или ровно одну изменённую позицию. Если исходный полный текст уже содержит ё, replacement ё отфильтруется. Если replacement приносит две новые ё, iterator выдаст две и dynamic predicate не сработает. Это непривычные, но существенные условия для проверки, а не повод переименовать алгоритм в знакомый diff.

Synthetic tests для независимой интерпретации: explicit flag bypasses inference; одно новое ё без других новых scalars; новое ё плюс другой scalar; повторные новые ё; source уже содержит ё; uppercase Ё нормализуется; typo disabled/ё enabled и обратное. Точная версия Unicode casing tables оригинала пока не зафиксирована; стандартное Swift lowercase может отличаться на отдельных Unicode версиях.

### Остаток неопределённости autocorrect

Блокер dynamic ё существенно закрыт на уровне predicate. Основной незавершённый механизм — `0x1002b5124`: он сопоставляет Unicode scalar sequences и переносит регистр при замене, включая расширения case mappings и различающуюся длину pattern/replacement. Путь содержит несколько уровней iterators и indexed case conversion. Это не требует копирования всей Rust Unicode table, но требует восстановления условий переноса регистра и проверки собственными adversarial fixtures. До этого exact-only independent interpreter допустимо описывать как ограниченный; нельзя подставлять простой title/uppercase heuristic и заявлять full parity.

## Следующий проход: Unicode case projection — политика восстановлена

Этот раздел уточняет предыдущий blocker: семантическая политика `0x1002b5124` теперь восстановлена; не восстановлена только точная версия Unicode tables, которая не мешает независимой реализации основного RU/EN subset. Источник E5, дополнительный scalar-array helper `0x1002b6f5c` (E4). Политика подтверждена чтением всех ветвей helper и локальным disassembly диапазона `0x1002b55c0…0x1002b5630` retained image.

### U01. Поиск совпадений

Входы: current text, pattern material и replacement. Пустой pattern возвращает неизменённую копию current text. Pattern и replacement предварительно декодируются в массивы Unicode **scalars**, не grapheme clusters.

Поиск движется слева направо по scalar boundaries current text. Для каждой позиции сравниваются соответствующие pattern/source scalars:

1. Полностью равные scalar values совпадают сразу.
2. Для двух ASCII scalars сравнивается ASCII lowercase, то есть только A…Z переводятся в a…z.
3. Если хотя бы один scalar non-ASCII, сравниваются **полные lowercase expansion sequences каждого из двух отдельных scalars**. Число scalars в этих двух expansions и значения должны совпасть.
4. Если любой scalar не совпал либо source закончился до конца pattern, в output копируется **один исходный scalar в начальной позиции попытки**, cursor продвигается на его UTF-8 byte length и поиск повторяется.
5. При полном совпадении заменяется весь matched source span; после вывода replacement cursor продвигается за весь span. Уже заменённый output не сканируется повторно. Следовательно matches nonoverlapping.

Это не full-string casefold/normalization: сопоставление сохраняет соответствие «один исходный scalar ↔ один pattern scalar», даже если lowercase expansion конкретного scalar содержит несколько значений. Например `ß` не эквивалентно двухскалярному `ss`, а composed/decomposed формы не нормализуются этим helper. Нет основания применять locale-sensitive comparison или NFC автоматически.

### U02. Проекция регистра и длины

Для каждого matched source span определяются:

- `n` — количество **всех** source scalars, включая punctuation/digits;
- `u` — количество uppercase scalars (ASCII uppercase или Unicode uppercase predicate);
- `majorityUpper = 2*u > n` — строго больше половины, не ≥ и не «весь текст uppercase».

Для replacement scalar с индексом `i`:

- Если `majorityUpper`, вывести uppercase mapping replacement scalar.
- Иначе, если `i < n` и source scalar с тем же индексом uppercase, вывести uppercase mapping replacement scalar.
- Иначе вывести replacement scalar **как есть**. Lowercase-преобразования в этой ветви нет: uppercase, уже заданный правилом replacement, сохраняется.

Если replacement длиннее source, оставшиеся replacement scalars uppercase только при majorityUpper, иначе копируются. Если replacement короче source, лишние source scalars не копируются: весь source match уже потреблён. Если uppercase mapping одного replacement scalar расширяется до нескольких scalars, все они выводятся, но следующий индекс сравнения продвигается только на **один исходный replacement scalar**. Граница исходного match от расширения output не меняется.

Disassembly `0x1002b55fc` загружает очередной **replacement scalar в w0**, `0x1002b5600` — source scalar для проверки uppercase, а `0x1002b5614` вызывает uppercase helper. Это снимает неоднозначность аргумента, потерянного в C-псевдокоде. Ветки `0x1002b5918` и последующие различают positional uppercase и majority; хвост replacement использует только majority.

### U03. Независимые synthetic examples

Это выведенные из ветвей ожидаемые результаты helper, **не выполненные runtime-тесты Caramba**. Для каждого примера pattern совпадает с source case-insensitively.

| Matched source | Replacement | Результат | Причина |
|---|---|---|---|
| `HEllo` | `world` | `WOrld` | 2/5 uppercase: positional, не majority |
| `HElLo` | `world` | `WORLD` | 3/5: strict majority |
| `Ab` | `xyz` | `Xyz` | 1/2 — tie; extra scalar копируется |
| `ABc` | `wxyz` | `WXYZ` | 2/3: majority распространяется на tail |
| `ab` | `XyZ` | `XyZ` | Не lowercases заданный replacement |
| `ABcd` | `xy` | `XY` | 2/4 — tie; только positional; source tail удаляется |
| `ПРивет` | `работа` | `РАбота` | RU positional policy, 2/6 |
| `Ёж` | `ежик` | `Ежик` | Ё — uppercase scalar; extra suffix без majority |

Для nonoverlap нужно отдельно проверить repeated input, pattern с self-overlap, mismatch после частичного префикса и empty replacement. Для Unicode expansion — source/pattern, где lowercase одного scalar расширяется; replacement с uppercase expansion; composed/decomposed несовпадение. Это проверяет механизм, не требует копировать Rust tables.

### U04. Реализуемый RU/EN subset и границы

Для ASCII Latin A…Z/a…z, Russian А…Я/а…я и Ё/ё casing mappings стабильны и односкалярны. Описанного контракта достаточно для независимого Swift scalar interpreter, включая длиннее/короче replacement и смешанный регистр. Unicode whitespace/punctuation не должны исключаться из n при вычислении majority.

За пределами этого subset Swift можно использовать собственные Unicode scalar casing mappings с явно указанным поведением. Отличия Unicode version возможны; это граница таблиц, **не причина оставлять RU/EN case projection нереализованным**. Остались проверки integration/wiring, model-preprocessing нюансов и оригинального runtime, но центральный алгоритм case projection больше не является неизвестным.

### A05. Autocorrect fallback отличается от classifier

Повторный просмотр `0x1002ae3fc` строки210–330 закрывает точное отличие:

- Primary lookup использует framing с forced mode=0. Внешнего forced-complete аргумента в этом вызове нет.
- При непустом списке matches fallback не выполняется, даже если позднее все найденные правила окажутся выключены toggles либо не дадут замены.
- При пустом списке и incomplete input lookup повторяется на STX+whitespace-trimmed input **без punctuation cleanup**.
- При пустом списке и complete input сначала Unicode whitespace trim, затем trailing maximal run только `!`, `)`, `,`, `-`, `.` (маска `0x720200000000`), затем leading maximal run `-`/`(`, затем повторный whitespace trim; далее STX+cleaned+ETX. Complete по-прежнему определяется последним scalar исходного input.
- Здесь lookup получает **один** fallback variant. Двухвариантная stable uniqueness из C06 относится только к KBM classifier.
- Очистка применяется к lookup input. Actual current text остаётся исходным; пробелы, пунктуация и прочее окружение сохраняются при global replacement.

В `0x1002ae134` lower-pass additions deduplicate по exact matched bytes + rule ID относительно накопленного original-first списка. Original-pass occurrences сами по себе не deduplicate этим wrapper. Case-sensitive flag не фильтрует lower-pass lookup: его эффект возникает при последующем exact substring replacement. Поэтому запрещено механически использовать KBM case-pass feature filtering для autocorrect. Порядок matches должен сохраняться, список не пересканируется после применения каждого правила.

Полный поддержанный pipeline: framing → original-first/lower-additions matching → при отсутствии matches autocorrect-specific fallback → fixed match list → удалить sentinel scalars из material → UTF-8 byte splice → effective ё detection → соответствующий toggle → global exact/case-projected replacement текущего текста → следующий элемент исходного списка.

## Проверка независимой реализации и предел runtime claims

Read-only review `Sources/NecarambaCore/Language/PatternAutocorrector.swift` после появления реализации: для RU/EN описанный выше scalar contract соблюдён; блокирующих расхождений при статическом просмотре не найдено. Разработчику переданы дополнительные regression cases: shorter replacement и отдельный autocorrect fallback mask. Whole-string lowercase в dynamic ё рекомендовано заменить per-scalar expansion для точного соответствия вне RU/EN; contextual Unicode casing может отличаться. Это ревью кода, не результат запущенных этим исследователем тестов.

Повторный финальный static review: dynamic ё уже использует per-scalar lowercase expansions. Также проверен `PatternClassifier.swift`: emptiness primary определяется после фильтрации language/case; cleanup masks, порядок cleaned/original variants и их byte uniqueness соответствуют C06. Блокирующих RU/EN расхождений не обнаружено. Empty-text shortcut согласован с запретом anchor-only patterns в компиляторе независимого Core, но это ограничение поддерживаемого subset, а не доказанное ограничение оригинала. Int32 overflow обрабатывается fail-closed вместо исходного машинного wrapping; native selector из C03 остаётся вне classifier primitive. Дополнительные тесты и их выполнение принадлежат разработчику; исследователь их повторно не запускал.

Независимый Core вводит собственные resource bounds/control-input rejection и явный forceComplete override; эти ограничения/расширение не следует выдавать за ограничения оригинала. Interpreter не включает AX/TCC/editor transaction proof, app exclusion policy, gesture timings, event suppression и collision-state lifecycle. Подключение его к CLI не доказывает full native-runtime parity.

Название decoded секции `appex` и число её graph records **не доказывают набор bundle-ID app profiles**. Input domain графа и смысл rule codes не прослежены до callers. Аналогично `feats.special_behaviors` с числовыми значениями не следует автоматически трактовать как готовые browser/Spark compatibility switches. Быстрый просмотр `0x1002ade40` и его использования перед `0x1002b07e4` установил модельную структуру и matcher, но не mapping enum→action. Spark-specific правило этим исследованием не подтверждено.
