import {test, assertEqual} from './harness.js';
import {ConvertLastWord} from '../../necaramba@local.necaramba.app/application/convertLastWord.js';

const US_RU = [{type: 'xkb', id: 'us'}, {type: 'xkb', id: 'ru'}];

function makeWorld({snapshot, sources = US_RU, current = 0, typed = null} = {}) {
    const world = {replaced: [], activated: [], log: [], relayout: []};
    world.textInput = {
        snapshot: () => snapshot,
        replace(edit) { world.replaced.push(edit); world.log.push('replace'); },
    };
    world.inputSources = {
        sources: () => sources,
        currentIndex: () => current,
        activate(index) { world.activated.push(index); world.log.push(`activate ${index}`); current = index; },
    };
    world.typedWord = {
        snapshot: () => typed,
        relayout(layout) { world.relayout.push(layout); },
    };
    world.keyboard = {
        backspace(count) { world.log.push(`backspace ${count}`); },
        type(keys) { world.log.push(`type ${keys.map(k => (k.shift ? '+' : '') + k.keycode).join(',')}`); },
    };
    world.useCase = new ConvertLastWord(world);
    return world;
}

const field = (text, cursor = [...text].length, anchor = cursor) =>
    ({focused: true, sensitive: false, text, cursor, anchor});
const keys = codes => codes.map(code => (typeof code === 'number' ? {keycode: code, shift: false} : code));
const GHBDTN = keys([34, 35, 48, 32, 20, 49]);

// ---- surrounding-text path (GTK, Qt, Firefox) -----------------------------

test('converts the last English-typed word to Russian and selects Russian', () => {
    const world = makeWorld({snapshot: field('ab ghbdtn')});
    assertEqual(world.useCase.execute(), {status: 'converted', from: 'us', to: 'ru', method: 'surrounding'});
    assertEqual(world.replaced, [{deleteBefore: 6, text: 'привет'}]);
    assertEqual(world.activated, [1]);
});

test('direction comes from the text, not from the active layout', () => {
    const world = makeWorld({snapshot: field('руддщ '), current: 1});
    world.useCase.execute();
    assertEqual(world.replaced, [{deleteBefore: 6, text: 'hello '}]);
    assertEqual(world.activated, [0]);
});

test('target layout already active is not re-activated', () => {
    const world = makeWorld({snapshot: field('ghbdtn'), current: 1});
    world.useCase.execute();
    assertEqual(world.activated, []);
});

test('a selection is replaced by committing the converted text', () => {
    const world = makeWorld({snapshot: field('ab ghbdtn vbh', 3, 13)});
    world.useCase.execute();
    assertEqual(world.replaced, [{deleteBefore: 0, text: 'привет мир'}]);
});

test('password fields are skipped, even with typed keys', () => {
    const world = makeWorld({snapshot: {...field('ghbdtn'), sensitive: true},
        typed: {layout: 'us', keys: GHBDTN, trailingSpaces: 0}});
    assertEqual(world.useCase.execute().status, 'unavailable');
    assertEqual(world.log, []);
});

test('needs two input sources with known tables', () => {
    const world = makeWorld({snapshot: field('ghbdtn'), sources: [{type: 'xkb', id: 'us'}, {type: 'xkb', id: 'de'}]});
    assertEqual(world.useCase.execute().status, 'noLayoutPair');
    assertEqual(world.replaced, []);
});

test('text that would not change is left alone', () => {
    const world = makeWorld({snapshot: field('2024')});
    assertEqual(world.useCase.execute().status, 'unchanged');
    assertEqual(world.replaced, []);
    assertEqual(world.activated, []);
});

test('the Russian source may be anywhere in the list', () => {
    const world = makeWorld({
        snapshot: field('ghbdtn'),
        sources: [{type: 'xkb', id: 'us'}, {type: 'ibus', id: 'anthy'}, {type: 'xkb', id: 'ru'}],
    });
    world.useCase.execute();
    assertEqual(world.activated, [2]);
});

test('surrounding-text conversion also moves the typed-word buffer to the target', () => {
    const world = makeWorld({snapshot: field('ghbdtn'), typed: {layout: 'us', keys: GHBDTN, trailingSpaces: 0}});
    world.useCase.execute();
    assertEqual(world.relayout, ['ru']);
});

// ---- retype path (terminals, XWayland/Electron) ---------------------------

test('without surrounding text: erase, select the target layout, retype the same keys', () => {
    const world = makeWorld({
        snapshot: {focused: true, sensitive: false, text: null, cursor: 0, anchor: 0},
        typed: {layout: 'us', keys: GHBDTN, trailingSpaces: 0},
    });
    assertEqual(world.useCase.execute(), {status: 'converted', from: 'us', to: 'ru', method: 'retype'});
    assertEqual(world.log, ['backspace 6', 'activate 1', 'type 34,35,48,32,20,49']);
    assertEqual(world.relayout, ['ru']);
});

test('no text-input focus at all (XWayland) uses the typed keys too', () => {
    const world = makeWorld({snapshot: null, typed: {layout: 'ru', keys: GHBDTN, trailingSpaces: 0}, current: 0});
    world.useCase.execute();
    assertEqual(world.log, ['backspace 6', 'type 34,35,48,32,20,49']);
});

test('retype keeps Shift and re-adds the spaces typed after the word', () => {
    const world = makeWorld({
        snapshot: null,
        typed: {layout: 'us', keys: [{keycode: 34, shift: true}, {keycode: 35, shift: false}], trailingSpaces: 2},
    });
    world.useCase.execute();
    assertEqual(world.log, ['backspace 4', 'activate 1', 'type +34,35,57,57']);
});

test('retype is based on the layout the word was typed in, not the active one', () => {
    // first Shift tap already switched to ru; the word was typed in us
    const world = makeWorld({snapshot: null, typed: {layout: 'us', keys: GHBDTN, trailingSpaces: 0}, current: 1});
    world.useCase.execute();
    assertEqual(world.log, ['backspace 6', 'type 34,35,48,32,20,49']);
});

test('nothing typed and no surrounding text: nothing happens', () => {
    const world = makeWorld({snapshot: null, typed: null});
    assertEqual(world.useCase.execute().status, 'nothing');
    assertEqual(world.log, []);
});

test('typed word in a layout without a table is not retyped', () => {
    const world = makeWorld({snapshot: null, typed: {layout: 'de', keys: GHBDTN, trailingSpaces: 0}});
    assertEqual(world.useCase.execute().status, 'nothing');
    assertEqual(world.log, []);
});
