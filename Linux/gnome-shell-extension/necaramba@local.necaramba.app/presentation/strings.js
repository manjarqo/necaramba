// Presentation: interface strings. English and Russian, like the macOS app.

const STRINGS = {
    en: {
        page: 'Layout switching',
        group: 'Switch the input layout',
        groupDescription: 'The shortcut fires once after the keys are released, provided nothing was typed while holding them. Shift+letter still types a capital letter.',
        shortcut: 'Shortcut',
        singleShift: 'Shift',
        altShift: 'Alt + Shift',
        controlShift: 'Ctrl + Shift',
        commandShift: 'Super + Shift',
        disabled: 'Off',
        conflictTitle: 'GNOME already switches layouts on this shortcut',
        conflictBody: 'The XKB option(s) %s in Settings → Keyboard switch on key press. Necaramba stays inactive for this shortcut to avoid switching twice. Remove the option to use the release-based switch.',
        conversionTitle: 'Convert the last word with double Shift',
        conversionBody: 'ghbdtn → привет. Converts the selection, if any, and selects the other layout. Works in apps that support Wayland text input (GTK, Qt, Firefox); password fields are skipped.',
        sourcesTitle: 'Input sources',
        sourcesBody: 'Layouts are taken from Settings → Keyboard → Input Sources. Each switch moves to the next source without the switcher popup.',
    },
    ru: {
        page: 'Переключение раскладки',
        group: 'Переключать раскладку',
        groupDescription: 'Сочетание срабатывает один раз после отпускания клавиш, если пока они были нажаты, ничего не набиралось. Shift+буква по-прежнему печатает заглавную.',
        shortcut: 'Сочетание',
        singleShift: 'Shift',
        altShift: 'Alt + Shift',
        controlShift: 'Ctrl + Shift',
        commandShift: 'Super + Shift',
        disabled: 'Выключено',
        conflictTitle: 'GNOME уже переключает раскладку этим сочетанием',
        conflictBody: 'Опция XKB %s в Параметры → Клавиатура переключает по нажатию. Чтобы не переключать дважды, Necaramba для этого сочетания не активна. Уберите опцию, чтобы переключение срабатывало по отпусканию.',
        conversionTitle: 'Двойной Shift — конвертировать последнее слово',
        conversionBody: 'ghbdtn → привет. Если есть выделение, конвертируется оно, и включается другая раскладка. Работает в приложениях с поддержкой ввода текста Wayland (GTK, Qt, Firefox); поля паролей пропускаются.',
        sourcesTitle: 'Источники ввода',
        sourcesBody: 'Раскладки берутся из Параметры → Клавиатура → Источники ввода. Каждое переключение выбирает следующий источник без всплывающего окна.',
    },
};

export function localizedStrings(languageNames) {
    const russian = (languageNames ?? []).some(name => name === 'ru' || name.startsWith('ru_'));
    return russian ? STRINGS.ru : STRINGS.en;
}
