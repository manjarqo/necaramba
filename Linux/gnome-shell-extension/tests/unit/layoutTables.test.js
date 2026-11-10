import {test, assertEqual} from './harness.js';
import {
    hasLayoutTable,
    layoutForSource,
    convertText,
    keysForText,
    detectSourceLayout,
} from '../../necaramba@local.necaramba.app/domain/layoutTables.js';

test('English and Russian XKB layouts have tables; variants and IBus engines do not', () => {
    assertEqual(hasLayoutTable('us'), true);
    assertEqual(hasLayoutTable('ru'), true);
    assertEqual(layoutForSource({type: 'xkb', id: 'ru'}), 'ru');
    assertEqual(layoutForSource({type: 'xkb', id: 'us+intl'}), null);
    assertEqual(layoutForSource({type: 'ibus', id: 'anthy'}), null);
});

test('us -> ru converts by physical key position', () => {
    assertEqual(convertText('ghbdtn', 'us', 'ru'), 'привет');
    assertEqual(convertText('Ghbdtn', 'us', 'ru'), 'Привет');
    assertEqual(convertText('GHBDTN', 'us', 'ru'), 'ПРИВЕТ');
});

test('ru -> us is the inverse', () => {
    assertEqual(convertText('привет', 'ru', 'us'), 'ghbdtn');
    assertEqual(convertText('руддщ', 'ru', 'us'), 'hello');
});

test('punctuation keys that carry Russian letters are converted', () => {
    assertEqual(convertText("[jhjij,'", 'us', 'ru'), 'хорошобэ');
    assertEqual(convertText('`;.', 'us', 'ru'), 'ёжю');
    assertEqual(convertText('~:<>', 'us', 'ru'), 'ЁЖБЮ');
    assertEqual(convertText('/?', 'us', 'ru'), '.,');
    assertEqual(convertText('ёжю.,', 'ru', 'us'), '`;./?');
});

test('shifted digit row follows the target layout', () => {
    assertEqual(convertText('@#$^&', 'us', 'ru'), '"№;:?');
    assertEqual(convertText('"№;:?', 'ru', 'us'), '@#$^&');
});

test('digits, spaces and unknown characters are kept', () => {
    assertEqual(convertText('2024 год!', 'ru', 'us'), '2024 ujl!');
    assertEqual(convertText('ü€', 'us', 'ru'), 'ü€');
});

test('source layout is detected from letters, punctuation-only uses the fallback', () => {
    assertEqual(detectSourceLayout('ghbdtn', ['us', 'ru'], 'ru'), 'us');
    assertEqual(detectSourceLayout('привет', ['us', 'ru'], 'us'), 'ru');
    assertEqual(detectSourceLayout('привеn', ['us', 'ru'], 'us'), 'ru');
    assertEqual(detectSourceLayout('приdtn', ['us', 'ru'], 'ru'), 'ru');
    assertEqual(detectSourceLayout('приdtn', ['us', 'ru'], 'us'), 'us');
    assertEqual(detectSourceLayout(';,.', ['us', 'ru'], 'us'), 'us');
    assertEqual(detectSourceLayout(';,.', ['us', 'ru'], 'ru'), 'ru');
    assertEqual(detectSourceLayout(';,.', ['us', 'ru'], 'de'), 'us');
});

test('keys for text: the physical keys that type it in a layout', () => {
    assertEqual(keysForText('пР', 'ru'), [{keycode: 34, shift: false}, {keycode: 35, shift: true}]);
    assertEqual(keysForText('a b', 'us'), [{keycode: 30, shift: false}, {keycode: 57, shift: false}, {keycode: 48, shift: false}]);
    assertEqual(keysForText('"№', 'ru'), [{keycode: 3, shift: true}, {keycode: 4, shift: true}]);
    assertEqual(keysForText('a€', 'us'), null);
    assertEqual(keysForText('a\nb', 'us'), null);
});
