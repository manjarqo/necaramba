// Data adapter: synthesizes physical key presses through a compositor virtual keyboard.
// Events are processed in order with layout changes, so a source activated between
// `backspace()` and `type()` applies to the retyped keys.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';

const BACKSPACE = 14;
const LEFT_SHIFT = 42;

export class VirtualKeyboard {
    /** @param observer  ShellKeyObserver, told which events are synthetic */
    constructor(observer) {
        this._observer = observer;
        const seat = global.stage.context.get_backend().get_default_seat();
        this._device = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
    }

    backspace(count) {
        this.type(Array.from({length: count}, () => ({keycode: BACKSPACE, shift: false})));
    }

    /** @param keys [{keycode (evdev), shift}] */
    type(keys) {
        const events = [];
        for (const {keycode, shift} of keys) {
            if (shift)
                events.push({keycode: LEFT_SHIFT, down: true});
            events.push({keycode, down: true}, {keycode, down: false});
            if (shift)
                events.push({keycode: LEFT_SHIFT, down: false});
        }
        this._observer.expectSynthetic(events);
        for (const {keycode, down} of events) {
            this._device.notify_key(GLib.get_monotonic_time(), keycode,
                down ? Clutter.KeyState.PRESSED : Clutter.KeyState.RELEASED);
        }
    }
}
