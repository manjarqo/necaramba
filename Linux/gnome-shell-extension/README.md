# Necaramba for Fedora / GNOME

[English](#english) · [Русский](#русский)

## English

A GNOME Shell extension that brings Necaramba to Linux:

- **Double Shift converts the last word** to the other layout: `ghbdtn` → `привет`, `руддщ` → `hello`. With a selection, the selection is converted. The direction comes from the text, and the target layout is selected afterwards, so you can keep typing. Pressing double Shift again converts back.
- **Layout switching** with a configurable shortcut:

| Setting | Keys |
| --- | --- |
| Shift (default) | tap either Shift |
| Alt + Shift | press both, release |
| Ctrl + Shift | press both, release |
| Super + Shift | press both, release (the macOS Command + Shift equivalent) |
| Off | nothing is bound |

The rule matches the macOS app: **the shortcut fires once after the keys are released, provided nothing else was typed or pressed while holding them.** Shift+letter still types a capital letter, and Ctrl+Shift+T or Alt+Shift+S do not switch.

Each switch moves to the next source from *Settings → Keyboard → Input Sources*, without the switcher popup.

#### Double Shift details

- The second Shift press must come within 300 ms of the first release (as on macOS). With the Shift layout shortcut, the first tap already switches; the second tap converts and selects the target layout.
- The last word is the text before the caret back to the previous space or line break; spaces typed after it are kept. Russian letters on punctuation keys (`` [ ] ; ' , . ` ``) are converted too.
- Supported pair: XKB `us` ↔ `ru` input sources (variants and IBus engines are not converted).
- Two methods, chosen automatically:
  - **Surrounding text** — apps that report the text around the caret (GTK 3/4, Qt, Firefox): the word is read and replaced through GNOME Shell's input method. Works even after moving the caret with the mouse. Password fields are skipped.
  - **Retype** — terminals (Ptyxis, GNOME Terminal, Console), XWayland apps and Chromium/Electron apps (VS Code, Chrome, Telegram Desktop, …): Necaramba remembers the physical keys of the word being typed, erases it with BackSpace, selects the other layout and types the same keys again — as the macOS app does. No clipboard is used.
- Retype knows only what was typed since the caret last moved: a click, an arrow key, Enter, Tab or a shortcut forgets the word. Editors that insert text by themselves (auto-closing brackets, autocomplete) can make the erase count wrong.
- Retype cannot see whether an XWayland/Electron field is a password field.

Automatic correction and the Flutter settings UI remain macOS-only.

### Requirements

- GNOME Shell 51 (Fedora 45, Wayland session).
- At least two input sources.
- No root access, no `input` group and no system configuration changes.

### Install

```bash
Linux/gnome-shell-extension/install.sh --install
```

On Wayland GNOME discovers a newly installed extension only after the next login. Log out, log back in, then:

```bash
gnome-extensions enable necaramba@local.necaramba.app
```

Choose the shortcut in *Extensions → Necaramba → Settings*, or:

```bash
gsettings --schemadir ~/.local/share/gnome-shell/extensions/necaramba@local.necaramba.app/schemas \
  set org.gnome.shell.extensions.necaramba layout-switch-shortcut altShift
```

`install.sh` without `--install` only builds `build/necaramba@local.necaramba.app.shell-extension.zip`.

### Interaction with existing GNOME settings

- **XKB group toggles.** If *Settings → Keyboard* already has an XKB option for the same keys (for example `grp:alt_shift_toggle` for Alt + Shift), both would switch and cancel each other out. Necaramba stays inactive for that shortcut and the settings page shows a warning. The native option switches on key press; remove it to get the release-based behavior.
- **Other shortcuts.** `switch-input-source` (Super+Space by default) and other extensions keep working. Avoid binding the same keys twice.
- **The Shift key event itself** is consumed by GNOME Shell while the Shift shortcut is selected, in the same way as the Super key for the overview. Applications still see Shift as a held modifier (capitals, Shift+click, Shift+arrows work), but an application that reacts to a bare Shift press (for example "double Shift" search in some IDEs) will not receive it. Choose another shortcut if you rely on that.

### How it works

GNOME on Wayland gives applications no global keyboard access. The extension runs inside the compositor:

1. A mutter keybinding for the configured keys (bare `Shift_L`/`Shift_R` for taps) (`Shift_L`, `<Alt>Shift_L`, …) **arms** the gesture when the last key goes down.
2. The core idle monitor reports the next input event; the live modifier mask tells whether that event released a chord key (continue / fire) or was anything else — a key, button or extra modifier (cancel).
3. When every chord key is released, the next input source is activated through GNOME Shell's input-source manager.
4. For double Shift, the word is taken from the surrounding text that the focused application reports to the input method, converted by physical key position, then replaced with `delete_surrounding` + `commit`.
5. Without surrounding text, the idle-monitor notification also exposes the key event being processed (`Clutter.get_current_event()`), so the physical keys of the current word are buffered for any window. Conversion erases them through a compositor virtual keyboard, selects the target layout and sends the same key codes; synthetic events are recognized from an exact queue and never re-enter the buffer.

### Architecture

Clean Architecture inside the extension; dependencies point inward.

```
necaramba@local.necaramba.app/
  domain/          pure JS: shortcut policy, release gesture, us/ru key tables, word range
  application/     ShortcutController (gestures -> actions), ConvertLastWord, switchToNextLayout
  data/            adapters: mutter keybinding + idle monitor, key observer, virtual keyboard,
                   input sources, input method, GSettings
  presentation/    preferences page, strings (en/ru)
  extension.js     composition root (shell)
  prefs.js         composition root (preferences window)
```

Shortcut values (`singleShift`, `altShift`, `controlShift`, `commandShift`, `disabled`) are the raw values of `NecarambaCore.LayoutSwitchShortcut`.

### Tests

```bash
cd Linux/gnome-shell-extension
gjs -m tests/unit/run.js     # domain + use case, no GNOME session needed
tests/headless/run.sh        # end-to-end in an isolated headless gnome-shell
```

The end-to-end test builds and installs the zip into a temporary `HOME` under `$XDG_RUNTIME_DIR`, uses `GSETTINGS_BACKEND=keyfile` and a private D-Bus session, starts `gnome-shell --headless`, and injects keys through mutter's RemoteDesktop API into three clients: a Wayland GTK4 text field, a VTE terminal and a GTK4 text field through XWayland (no surrounding text, like Electron). The typed text proves the result. It covers layout switching, double-Shift conversion on both paths (both directions, trailing space, capitals, BackSpace while typing, selection, toggling back, only the last word, caret moved, feature off, chord shortcut), and smoke-tests the preferences page. Your own dconf settings, extensions and input sources are not touched.

Not covered by automated tests: a physical keyboard in a real logged-in session, GNOME versions other than 51, X11 sessions, and IBus input-method engines other than plain XKB layouts.

## Русский

Расширение GNOME Shell, которое переносит Necaramba на Linux.

- **Двойной Shift конвертирует последнее слово** в другую раскладку: `ghbdtn` → `привет`, `руддщ` → `hello`. Если есть выделение — конвертируется оно. Направление определяется по тексту, после конвертации включается нужная раскладка. Повторный двойной Shift возвращает обратно.
- **Переключение раскладки** настраиваемым сочетанием:

| Настройка | Клавиши |
| --- | --- |
| Shift (по умолчанию) | нажать и отпустить любой Shift |
| Alt + Shift | нажать оба, отпустить |
| Ctrl + Shift | нажать оба, отпустить |
| Super + Shift | нажать оба, отпустить (аналог Command + Shift на Mac) |
| Выключено | ничего не назначено |

Правило такое же, как в macOS-версии: **сочетание срабатывает один раз после отпускания клавиш, если пока они были нажаты, ничего не набиралось.** Shift+буква печатает заглавную, Ctrl+Shift+T и Alt+Shift+S раскладку не меняют.

Переключение идёт на следующий источник из *Параметры → Клавиатура → Источники ввода*, без всплывающего окна.

#### Двойной Shift

- Второе нажатие должно быть не позже 300 мс после отпускания первого (как в macOS). При сочетании «Shift» первый тап уже переключает раскладку, второй — конвертирует слово и включает нужную раскладку.
- Пара раскладок: XKB `us` ↔ `ru`.
- Способ выбирается автоматически:
  - **по тексту вокруг курсора** — приложения, которые его сообщают (GTK 3/4, Qt, Firefox): слово читается и заменяется через метод ввода GNOME Shell. Работает и после перемещения курсора мышью. Поля паролей пропускаются.
  - **перенабором** — терминалы (Ptyxis, GNOME Terminal, Console), приложения XWayland и Chromium/Electron (VS Code, Chrome, Telegram Desktop…): Necaramba запоминает физические клавиши набираемого слова, стирает его Backspace, включает другую раскладку и набирает те же клавиши заново — как в macOS-версии. Буфер обмена не используется.
- Перенабор знает только то, что набрано после последнего перемещения курсора: клик, стрелка, Enter, Tab или сочетание клавиш сбрасывают слово. Редакторы, которые сами вставляют текст (автозакрытие скобок, автодополнение), могут сбить число стираемых символов.
- При перенаборе нельзя узнать, что поле в XWayland/Electron — поле пароля.

Автокоррекция и интерфейс на Flutter остаются только в macOS-версии.

### Установка

```bash
Linux/gnome-shell-extension/install.sh --install
```

На Wayland GNOME видит новое расширение только после повторного входа. Выйдите из сеанса, войдите снова и выполните:

```bash
gnome-extensions enable necaramba@local.necaramba.app
```

Сочетание выбирается в *Расширения → Necaramba → Настройки*.

### Совместимость с настройками GNOME

- Если в *Параметры → Клавиатура* уже включена опция XKB на те же клавиши (например, `grp:alt_shift_toggle` для Alt + Shift), Necaramba для этого сочетания не активна, чтобы не переключать дважды, а в настройках показывается предупреждение. Штатная опция переключает по нажатию; уберите её, чтобы переключение срабатывало по отпусканию.
- При выбранном Shift само событие нажатия Shift забирает GNOME Shell (как Super для обзора). Приложения по-прежнему видят Shift как зажатый модификатор, но программа, реагирующая на одиночное нажатие Shift (например, поиск по двойному Shift в некоторых IDE), его не получит.
- Root-права, группа `input` и изменения системных настроек не нужны.
