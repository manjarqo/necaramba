# Проверка исследовательских артефактов

Дата: 2026-10-14. Это проверка документов и результатов декомпиляции, не тесты будущего продукта.

Команда воспроизведения: `python3 docs/research/caramba/tools/verify_artifacts.py` из корня проекта. Машинный результат: `evidence/artifact-verification.json`; SHA-256 manifest всех17753 отдельных псевдокодов: `evidence/decompiled-sha256.txt`.

Проверены: coverage.complete, число сохранённых функций, наличие их адресов в inventory и Evidence ID в каждом файле, уникальность103AC, локальные Markdown-ссылки, баланс code fences, неизменность SHA-256 исходного executable. Все проверки артефактов пройдены; ошибки0.

REA main evidence экспортирован перед закрытием: `evidence/rea-main-final-bundle.json`,41680790 bytes,286 records. Nested UI/helper sessions закрылись успешно. Main `close_binary` вернул `cleanup_incomplete`: macOS sysctl ownership check не смог подтвердить завершение PID32849. Последующий `ps -p 32849` не обнаружил процесса (exit1); исходный ответ сохранён в `evidence/rpc/zz999-close.result.json`. Чужие процессы не завершались, временный каталог принудительно не удалялся.

Выполнен review согласованности: F14 импорт/удаление картинки перенесён из provisional в обязательные функции по новым UI framework evidence; AC041 согласован с UI20/legacy100; общие типы A/B/C/D и UI bridge E согласованы; combined import конкретизирован recovery journal; неизвестные timings/пороговые значения отмечены как design. После выбора Flutter планы содержат28 задач и неотмеченные execution checkboxes; они ещё не исполнены.

**Не выполнялись:** Swift build/test продукта (кода нет), физические/аппаратные клавиатурные сценарии оригинала, матрица macOS12/Intel/Apple Silicon, тесты StoreKit/покупок, notarization, production networking, полная декодировка CLM1, отдельная x86_64 декомпиляция. Эти проверки не имеют статуса PASS. Значения precision/performance в spec — цели, не измерения.

Редакция Flutter: актуализированы spec/планы A–D и добавлен E; проверены28 task headings, единые Global Constraints, paths Runner workspace, Flutter UI вместо NSTableView, native ownership и4 дополнительных release gates. Исследовательские выводы о самом Caramba не менялись. Flutter/Swift compilation не выполнялась: изменены только документы.
