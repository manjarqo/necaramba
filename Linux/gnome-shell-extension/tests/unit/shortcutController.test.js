import {test, assertEqual} from './harness.js';
import {ShortcutController} from '../../necaramba@local.necaramba.app/application/shortcutController.js';

function makeWorld({shortcut = 'singleShift', conversion = true, xkbOptions = []} = {}) {
    const world = {now: 0, bindings: {}, watchers: [], listeners: [], logs: []};
    world.preferences = {
        shortcut: () => shortcut,
        conversionEnabled: () => conversion,
        xkbOptions: () => xkbOptions,
        onChanged(callback) {
            world.listeners.push(callback);
            return () => { world.listeners = world.listeners.filter(c => c !== callback); };
        },
        set(next) {
            shortcut = next.shortcut ?? shortcut;
            conversion = next.conversion ?? conversion;
            xkbOptions = next.xkbOptions ?? xkbOptions;
            world.listeners.forEach(c => c());
        },
    };
    world.trigger = {
        bind(name, accelerators, onArm) { world.bindings[name] = {accelerators, onArm}; },
        unbindAll() { world.bindings = {}; world.watchers = []; },
        watchNextInput(callback) { world.watchers.push(callback); },
    };
    world.clock = {nowMicros: () => world.now};
    world.logger = {log: message => world.logs.push(message)};
    world.done = [];
    world.actions = {
        switchLayout: () => world.done.push('switch'),
        convertWord: () => world.done.push('convert'),
    };
    world.controller = new ShortcutController(world);
    world.at = millis => { world.now = millis * 1000; };
    // A compositor event: the keybinding (if any) runs first, then the idle watch.
    world.event = (millis, modifiers, armName = null) => {
        world.at(millis);
        if (armName)
            world.bindings[armName].onArm(modifiers);
        const pending = world.watchers;
        world.watchers = [];
        pending.forEach(callback => callback(modifiers));
    };
    world.shiftTap = (pressAt, releaseAt) => {
        world.event(pressAt, ['shift'], 'tap');
        world.event(releaseAt, []);
    };
    return world;
}

test('single Shift + conversion: Shift taps bound once, no chord', () => {
    const world = makeWorld();
    world.controller.start();
    assertEqual(Object.keys(world.bindings), ['tap']);
    assertEqual(world.bindings.tap.accelerators, ['Shift_L', 'Shift_R']);
});

test('chord shortcut with conversion binds both taps and the chord', () => {
    const world = makeWorld({shortcut: 'altShift'});
    world.controller.start();
    assertEqual(Object.keys(world.bindings).sort(), ['chord', 'tap']);
    assertEqual(world.bindings.chord.accelerators[0], '<Alt>Shift_L');
});

test('chord shortcut without conversion binds only the chord; Off binds nothing', () => {
    const chord = makeWorld({shortcut: 'controlShift', conversion: false});
    chord.controller.start();
    assertEqual(Object.keys(chord.bindings), ['chord']);
    const off = makeWorld({shortcut: 'disabled', conversion: false});
    off.controller.start();
    assertEqual(Object.keys(off.bindings), []);
});

test('a single Shift tap switches immediately', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    assertEqual(world.done, ['switch']);
});

test('double Shift switches once, then converts on the second release', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.shiftTap(200, 260);
    assertEqual(world.done, ['switch', 'convert']);
});

test('a second tap after the 300 ms window is just another switch', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.shiftTap(500, 560);
    assertEqual(world.done, ['switch', 'switch']);
});

test('a triple tap converts once and then switches', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 60);
    world.shiftTap(150, 210);
    world.shiftTap(300, 360);
    assertEqual(world.done, ['switch', 'convert', 'switch']);
});

test('typing between the taps cancels the double', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.event(120, []);          // a letter key
    world.shiftTap(200, 260);
    assertEqual(world.done, ['switch', 'switch']);
});

test('a trailing notification a few ms after the release does not end the window', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.event(86, []);           // compositor echo of the release
    world.shiftTap(200, 260);
    assertEqual(world.done, ['switch', 'convert']);
});

test('second press reported by the input watch before the keybinding still counts', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.event(200, ['shift']);   // watch first …
    world.bindings.tap.onArm(['shift']);   // … then the keybinding, same event
    world.event(260, []);
    assertEqual(world.done, ['switch', 'convert']);
});

test('Shift+letter as the second press cancels everything', () => {
    const world = makeWorld();
    world.controller.start();
    world.shiftTap(0, 80);
    world.event(150, ['shift'], 'tap');
    world.event(180, ['shift']);   // letter typed with Shift held
    world.event(220, []);
    assertEqual(world.done, ['switch']);
});

test('with a chord shortcut, taps only convert', () => {
    const world = makeWorld({shortcut: 'altShift'});
    world.controller.start();
    world.shiftTap(0, 80);
    assertEqual(world.done, []);
    world.shiftTap(150, 210);
    assertEqual(world.done, ['convert']);
    world.event(1000, ['alt', 'shift'], 'chord');
    world.event(1100, ['alt']);
    world.event(1150, []);
    assertEqual(world.done, ['convert', 'switch']);
});

test('conversion off: single Shift still switches, double just switches twice', () => {
    const world = makeWorld({conversion: false});
    world.controller.start();
    world.shiftTap(0, 80);
    world.shiftTap(150, 210);
    assertEqual(world.done, ['switch', 'switch']);
});

test('native XKB toggle for the chord leaves the chord unbound but keeps conversion', () => {
    const world = makeWorld({shortcut: 'altShift', xkbOptions: ['grp:alt_shift_toggle']});
    world.controller.start();
    assertEqual(Object.keys(world.bindings), ['tap']);
    assertEqual(world.controller.status, {
        shortcut: 'altShift', layoutActive: false, conversion: true, conflicts: ['grp:alt_shift_toggle'],
    });
    assertEqual(world.logs.length, 1);
});

test('chord arm with extra live modifiers is ignored', () => {
    const world = makeWorld({shortcut: 'altShift', conversion: false});
    world.controller.start();
    world.event(0, ['alt', 'shift', 'control'], 'chord');
    world.event(50, []);
    assertEqual(world.done, []);
});

test('preference change rebinds and drops pending gestures', () => {
    const world = makeWorld();
    world.controller.start();
    world.event(0, ['shift'], 'tap');
    world.preferences.set({shortcut: 'commandShift'});
    assertEqual(Object.keys(world.bindings).sort(), ['chord', 'tap']);
    world.event(50, []);
    assertEqual(world.done, []);
});

test('stop unbinds and unsubscribes', () => {
    const world = makeWorld();
    world.controller.start();
    world.controller.stop();
    assertEqual(world.bindings, {});
    assertEqual(world.listeners.length, 0);
});
