import {test, assertEqual} from './harness.js';
import {findConversionRange} from '../../necaramba@local.necaramba.app/domain/conversionRange.js';

test('last word before the caret', () => {
    assertEqual(findConversionRange('ab ghbdtn', 9, 9),
        {kind: 'word', original: 'ghbdtn', deleteBefore: 6, trailing: ''});
});

test('word at the start of the field', () => {
    assertEqual(findConversionRange('ghbdtn', 6, 6),
        {kind: 'word', original: 'ghbdtn', deleteBefore: 6, trailing: ''});
});

test('spaces typed after the word are kept', () => {
    assertEqual(findConversionRange('ab ghbdtn  ', 11, 11),
        {kind: 'word', original: 'ghbdtn', deleteBefore: 8, trailing: '  '});
});

test('caret in the middle of the text uses the word before it', () => {
    assertEqual(findConversionRange('ghbdtn vbh', 6, 6),
        {kind: 'word', original: 'ghbdtn', deleteBefore: 6, trailing: ''});
});

test('a newline ends the word and is never crossed', () => {
    assertEqual(findConversionRange('one\nghbdtn', 10, 10).original, 'ghbdtn');
    assertEqual(findConversionRange('ghbdtn\n', 7, 7), null);
});

test('offsets count code points, not UTF-16 units', () => {
    assertEqual(findConversionRange('😀 ytn', 5, 5),
        {kind: 'word', original: 'ytn', deleteBefore: 3, trailing: ''});
});

test('selection wins over the last word, in either direction', () => {
    assertEqual(findConversionRange('ab ghbdtn vbh', 3, 9), {kind: 'selection', original: 'ghbdtn'});
    assertEqual(findConversionRange('ab ghbdtn vbh', 13, 3), {kind: 'selection', original: 'ghbdtn vbh'});
});

test('nothing to convert, invalid caret or oversized word', () => {
    assertEqual(findConversionRange('', 0, 0), null);
    assertEqual(findConversionRange('   ', 3, 3), null);
    assertEqual(findConversionRange('abc', 7, 7), null);
    assertEqual(findConversionRange(null, 0, 0), null);
    assertEqual(findConversionRange('x'.repeat(129), 129, 129), null);
});
