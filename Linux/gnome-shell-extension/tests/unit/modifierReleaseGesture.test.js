import {test, assertEqual} from './harness.js';
import {ModifierReleaseGesture} from '../../necaramba@local.necaramba.app/domain/modifierReleaseGesture.js';

const ms = value => value * 1000;

test('bare Shift tap fires once Shift is released', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['shift'], ms(0));
    assertEqual(gesture.observe([], ms(80)), 'fire');
    assertEqual(gesture.armed, false);
});

test('typing while Shift is held cancels the switch (Shift+a)', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['shift'], ms(0));
    assertEqual(gesture.observe(['shift'], ms(30)), 'cancel');
    assertEqual(gesture.observe([], ms(60)), 'idle');
});

test('chord fires only after every chord modifier is released', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['alt', 'shift'], ms(0));
    assertEqual(gesture.observe(['alt'], ms(100)), 'pending');
    assertEqual(gesture.observe([], ms(200)), 'fire');
});

test('a key typed inside the chord cancels it (Ctrl+Shift+T)', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['control', 'shift'], ms(0));
    assertEqual(gesture.observe(['control', 'shift'], ms(40)), 'cancel');
});

test('a key typed after a partial release cancels it', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['alt', 'shift'], ms(0));
    assertEqual(gesture.observe(['alt'], ms(50)), 'pending');
    assertEqual(gesture.observe(['alt'], ms(90)), 'cancel');
});

test('an extra modifier or mouse button cancels it', () => {
    const extra = new ModifierReleaseGesture();
    extra.arm(['alt', 'shift'], ms(0));
    assertEqual(extra.observe(['alt', 'shift', 'control'], ms(30)), 'cancel');
    const button = new ModifierReleaseGesture();
    button.arm(['shift'], ms(0));
    assertEqual(button.observe(['shift', 'button'], ms(30)), 'cancel');
});

test('repeated notifications for the arming event are ignored', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['shift'], ms(10));
    assertEqual(gesture.observe(['shift'], ms(10.2)), 'ignored');
    assertEqual(gesture.observe([], ms(90)), 'fire');
});

test('repeated notifications for one release are ignored', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['alt', 'shift'], ms(0));
    assertEqual(gesture.observe(['alt'], ms(50)), 'pending');
    assertEqual(gesture.observe(['alt'], ms(50.4)), 'ignored');
    assertEqual(gesture.observe([], ms(120)), 'fire');
});

test('re-arming restarts the gesture', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm(['alt', 'shift'], ms(0));
    assertEqual(gesture.observe(['alt'], ms(50)), 'pending');
    gesture.arm(['alt', 'shift'], ms(100));
    assertEqual(gesture.observe(['alt'], ms(150)), 'pending');
    assertEqual(gesture.observe([], ms(200)), 'fire');
});

test('arming without modifiers is refused and a clock jump resets', () => {
    const gesture = new ModifierReleaseGesture();
    gesture.arm([], ms(0));
    assertEqual(gesture.armed, false);
    gesture.arm(['shift'], ms(100));
    assertEqual(gesture.observe([], ms(50)), 'cancel');
});
