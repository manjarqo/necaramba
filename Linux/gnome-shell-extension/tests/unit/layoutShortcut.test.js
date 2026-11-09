import {test, assertEqual} from './harness.js';
import {
    LayoutSwitchShortcut,
    parseShortcut,
    shortcutPlan,
    nativeConflicts,
    nextSourceIndex,
} from '../../necaramba@local.necaramba.app/domain/layoutShortcut.js';

test('shortcut raw values match NecarambaCore LayoutSwitchShortcut', () => {
    assertEqual(Object.values(LayoutSwitchShortcut),
        ['singleShift', 'altShift', 'controlShift', 'commandShift', 'disabled']);
});

test('unknown stored shortcut is treated as disabled', () => {
    assertEqual(parseShortcut('altShift'), 'altShift');
    assertEqual(parseShortcut('capsLock'), 'disabled');
    assertEqual(parseShortcut(undefined), 'disabled');
});

test('single Shift binds both bare Shift keys', () => {
    assertEqual(shortcutPlan('singleShift'),
        {accelerators: ['Shift_L', 'Shift_R'], modifiers: ['shift']});
});

test('chords bind either key order and both sides', () => {
    assertEqual(shortcutPlan('altShift'), {
        accelerators: ['<Alt>Shift_L', '<Alt>Shift_R', '<Shift>Alt_L', '<Shift>Alt_R'],
        modifiers: ['alt', 'shift'],
    });
    assertEqual(shortcutPlan('controlShift').modifiers, ['control', 'shift']);
    assertEqual(shortcutPlan('controlShift').accelerators[2], '<Shift>Control_L');
    assertEqual(shortcutPlan('commandShift'), {
        accelerators: ['<Super>Shift_L', '<Super>Shift_R', '<Shift>Super_L', '<Shift>Super_R'],
        modifiers: ['shift', 'super'],
    });
});

test('disabled shortcut binds nothing', () => {
    assertEqual(shortcutPlan('disabled'), {accelerators: [], modifiers: []});
});

test('native XKB group toggles for the same chord are reported as conflicts', () => {
    assertEqual(nativeConflicts('altShift', ['compose:ralt', 'grp:alt_shift_toggle']),
        ['grp:alt_shift_toggle']);
    assertEqual(nativeConflicts('controlShift', ['grp:lctrl_lshift_toggle']),
        ['grp:lctrl_lshift_toggle']);
    assertEqual(nativeConflicts('singleShift', ['grp:lshift_toggle']), ['grp:lshift_toggle']);
    assertEqual(nativeConflicts('singleShift', ['grp:alt_shift_toggle']), []);
    assertEqual(nativeConflicts('commandShift', ['grp:alt_shift_toggle']), []);
    assertEqual(nativeConflicts('disabled', ['grp:alt_shift_toggle']), []);
});

test('next input source wraps around and ignores single-source setups', () => {
    assertEqual(nextSourceIndex(0, 2), 1);
    assertEqual(nextSourceIndex(1, 2), 0);
    assertEqual(nextSourceIndex(2, 3), 0);
    assertEqual(nextSourceIndex(0, 1), null);
    assertEqual(nextSourceIndex(0, 0), null);
    assertEqual(nextSourceIndex(undefined, 2), 1);
});
