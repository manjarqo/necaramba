// Domain: layout-switch shortcut policy. Pure JavaScript, no GNOME imports.

/** Raw values intentionally match NecarambaCore `LayoutSwitchShortcut`. */
export const LayoutSwitchShortcut = Object.freeze({
    SINGLE_SHIFT: 'singleShift',
    ALT_SHIFT: 'altShift',
    CONTROL_SHIFT: 'controlShift',
    COMMAND_SHIFT: 'commandShift',
    DISABLED: 'disabled',
});

const KNOWN = new Set(Object.values(LayoutSwitchShortcut));

/** Unknown values are conservative: nothing is bound. */
export function parseShortcut(raw) {
    return KNOWN.has(raw) ? raw : LayoutSwitchShortcut.DISABLED;
}

function chord(partner, modifier) {
    return {
        accelerators: [
            `<${partner}>Shift_L`, `<${partner}>Shift_R`,
            `<Shift>${partner}_L`, `<Shift>${partner}_R`,
        ],
        modifiers: [modifier, 'shift'].sort(),
    };
}

/**
 * Accelerators arm the gesture when the last key of the chord goes down;
 * `modifiers` is the exact logical modifier set that must then be released
 * without any other input for the switch to happen.
 */
export function shortcutPlan(shortcut) {
    switch (parseShortcut(shortcut)) {
    case LayoutSwitchShortcut.SINGLE_SHIFT:
        return {accelerators: ['Shift_L', 'Shift_R'], modifiers: ['shift']};
    case LayoutSwitchShortcut.ALT_SHIFT:
        return chord('Alt', 'alt');
    case LayoutSwitchShortcut.CONTROL_SHIFT:
        return chord('Control', 'control');
    case LayoutSwitchShortcut.COMMAND_SHIFT:
        return chord('Super', 'super');
    default:
        return {accelerators: [], modifiers: []};
    }
}

const NATIVE_EQUIVALENTS = {
    [LayoutSwitchShortcut.SINGLE_SHIFT]: ['grp:lshift_toggle', 'grp:rshift_toggle'],
    [LayoutSwitchShortcut.ALT_SHIFT]: [
        'grp:alt_shift_toggle', 'grp:lalt_lshift_toggle',
        'grp:ralt_rshift_toggle', 'grp:alt_shift_toggle_bidir',
    ],
    [LayoutSwitchShortcut.CONTROL_SHIFT]: [
        'grp:ctrl_shift_toggle', 'grp:lctrl_lshift_toggle',
        'grp:rctrl_rshift_toggle', 'grp:ctrl_shift_toggle_bidir',
    ],
};

/**
 * XKB group toggles already switch on the same keys. Running both would switch
 * twice (a no-op with two layouts), so such options are reported as conflicts.
 */
export function nativeConflicts(shortcut, xkbOptions) {
    const equivalents = NATIVE_EQUIVALENTS[parseShortcut(shortcut)] ?? [];
    return (xkbOptions ?? []).filter(option => equivalents.includes(option));
}

export function nextSourceIndex(current, count) {
    if (!Number.isInteger(count) || count < 2)
        return null;
    const index = Number.isInteger(current) && current >= 0 ? current : 0;
    return (index + 1) % count;
}
