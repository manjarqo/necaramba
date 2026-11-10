import {test, assertEqual} from './harness.js';
import {SurroundingCache} from '../../necaramba@local.necaramba.app/domain/surroundingCache.js';

const FIELD = {id: 'field'};
const OTHER = {id: 'other'};
const report = (text, cursor = [...text].length, anchor = cursor) => ({text, cursor, anchor});

test('current surrounding text wins when the field reports it', () => {
    const cache = new SurroundingCache();
    cache.remember(report('old'), FIELD);
    assertEqual(cache.resolve(report('new'), FIELD), report('new'));
});

test('after an input-method reset the last report of the same field is used', () => {
    const cache = new SurroundingCache();
    cache.remember(report('ab ghbdtn', 3, 9), FIELD);
    assertEqual(cache.resolve(report(null, 0, 0), FIELD), report('ab ghbdtn', 3, 9));
});

test('a key press or click makes the remembered text stale until the field reports again', () => {
    const cache = new SurroundingCache();
    cache.remember(report('ghbdtn'), FIELD);
    cache.invalidate();
    assertEqual(cache.resolve(report(null, 0, 0), FIELD), report(null, 0, 0));
    cache.remember(report('ghbdtnx'), FIELD);
    assertEqual(cache.resolve(report(null, 0, 0), FIELD).text, 'ghbdtnx');
});

test('a different focused field never uses another field\'s text', () => {
    const cache = new SurroundingCache();
    cache.remember(report('ghbdtn'), FIELD);
    assertEqual(cache.resolve(report(null, 0, 0), OTHER).text, null);
});

test('null reports are not remembered', () => {
    const cache = new SurroundingCache();
    cache.remember(report('ghbdtn'), FIELD);
    cache.remember(report(null, 0, 0), FIELD);
    assertEqual(cache.resolve(report(null, 0, 0), FIELD).text, 'ghbdtn');
});

test('no focus: nothing is resolved from the cache', () => {
    const cache = new SurroundingCache();
    cache.remember(report('ghbdtn'), FIELD);
    assertEqual(cache.resolve(report(null, 0, 0), null).text, null);
});
