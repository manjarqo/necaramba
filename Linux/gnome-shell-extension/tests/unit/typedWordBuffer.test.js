import {test, assertEqual} from './harness.js';
import {TypedWordBuffer} from '../../necaramba@local.necaramba.app/domain/typedWordBuffer.js';

// evdev codes: g34 h35 b48 d32 t20 n49, space 57, BackSpace 14, Enter 28, Left 105, 7 = 8
const press = (buffer, keycode, {shift = false, layout = 'us', modifiers} = {}) =>
    buffer.press({keycode, modifiers: modifiers ?? (shift ? ['shift'] : []), layout});
const typeWord = (buffer, codes, options) => codes.forEach(code => press(buffer, code, options));
const GHBDTN = [34, 35, 48, 32, 20, 49];

test('records the physical keys of the word being typed', () => {
    const buffer = new TypedWordBuffer();
    press(buffer, 34, {shift: true});
    typeWord(buffer, [35, 48]);
    assertEqual(buffer.snapshot(), {
        layout: 'us',
        keys: [{keycode: 34, shift: true}, {keycode: 35, shift: false}, {keycode: 48, shift: false}],
        trailingSpaces: 0,
    });
});

test('spaces after the word are counted; the next letter starts a new word', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, GHBDTN);
    typeWord(buffer, [57, 57]);
    assertEqual(buffer.snapshot().trailingSpaces, 2);
    assertEqual(buffer.snapshot().keys.length, 6);
    press(buffer, 47);
    assertEqual(buffer.snapshot(), {layout: 'us', keys: [{keycode: 47, shift: false}], trailingSpaces: 0});
});

test('BackSpace removes spaces first, then keys', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, [34, 35, 57]);
    press(buffer, 14);
    assertEqual(buffer.snapshot().trailingSpaces, 0);
    press(buffer, 14);
    assertEqual(buffer.snapshot().keys, [{keycode: 34, shift: false}]);
    press(buffer, 14);
    assertEqual(buffer.snapshot(), null);
});

test('modifier keys alone are ignored (Shift taps keep the word)', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, GHBDTN);
    [42, 54, 29, 56, 125, 97, 100, 126].forEach(code => press(buffer, code));
    assertEqual(buffer.snapshot().keys.length, 6);
});

test('Enter, Tab, arrows, Delete and shortcuts end the word', () => {
    for (const end of [{keycode: 28}, {keycode: 15}, {keycode: 105}, {keycode: 111}, {keycode: 102},
        {keycode: 46, modifiers: ['control']}, {keycode: 30, modifiers: ['alt']}]) {
        const buffer = new TypedWordBuffer();
        typeWord(buffer, GHBDTN);
        press(buffer, end.keycode, {modifiers: end.modifiers});
        assertEqual(buffer.snapshot(), null);
    }
});

test('a space with nothing before it, clicks and focus changes reset', () => {
    const buffer = new TypedWordBuffer();
    press(buffer, 57);
    assertEqual(buffer.snapshot(), null);
    typeWord(buffer, GHBDTN);
    buffer.reset();
    assertEqual(buffer.snapshot(), null);
});

test('a layout change in the middle of a word restarts the word', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, [34, 35]);
    press(buffer, 48, {layout: 'ru'});
    assertEqual(buffer.snapshot(), {layout: 'ru', keys: [{keycode: 48, shift: false}], trailingSpaces: 0});
});

test('keys outside the convertible block (numpad, F-keys) reset', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, GHBDTN);
    press(buffer, 79);
    assertEqual(buffer.snapshot(), null);
});

test('digits and punctuation keys are part of the word', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, [26, 39, 51, 41, 8]);
    assertEqual(buffer.snapshot().keys.length, 5);
});

test('overlong words are dropped', () => {
    const buffer = new TypedWordBuffer({maxKeys: 4});
    typeWord(buffer, [34, 35, 48, 32, 20]);
    assertEqual(buffer.snapshot(), null);
});

test('after a conversion the same keys belong to the target layout', () => {
    const buffer = new TypedWordBuffer();
    typeWord(buffer, GHBDTN);
    buffer.relayout('ru');
    assertEqual(buffer.snapshot().layout, 'ru');
    press(buffer, 47, {layout: 'ru'});
    assertEqual(buffer.snapshot().keys.length, 7);
});
