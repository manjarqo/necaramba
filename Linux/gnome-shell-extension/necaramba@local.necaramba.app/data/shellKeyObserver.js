// Data adapter: observes key presses delivered to any window (Wayland or XWayland).
//
// The core idle monitor notifies on every input event while the compositor is
// processing it, so Clutter.get_current_event() is that event. Only key codes and
// modifiers are used; they never leave the shell process.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';

import {modifiersFromMask} from './modifierMask.js';

const SYNTHETIC_TIMEOUT_MICROS = 1_000_000;

export class ShellKeyObserver {
    /**
     * @param onKey   ({keycode, modifiers}) for each physical key press (evdev code)
     * @param onReset () when the caret may have moved: click, touch, focus change
     */
    constructor({onKey, onReset}) {
        this._onKey = onKey;
        this._onReset = onReset;
        this._monitor = global.backend.get_core_idle_monitor();
        this._watchId = 0;
        this._last = null;
        this._expected = [];
        this._expectedAt = 0;
    }

    start() {
        this._focusId = global.display.connect('notify::focus-window', () => this._onReset());
        this._watch();
    }

    stop() {
        if (this._watchId)
            this._monitor.remove_watch(this._watchId);
        this._watchId = 0;
        if (this._focusId)
            global.display.disconnect(this._focusId);
        this._focusId = 0;
        this._expected = [];
    }

    /** Key events Necaramba is about to synthesize; they are not user input. */
    expectSynthetic(events) {
        if (GLib.get_monotonic_time() - this._expectedAt > SYNTHETIC_TIMEOUT_MICROS)
            this._expected = [];
        this._expected.push(...events);
        this._expectedAt = GLib.get_monotonic_time();
    }

    _watch() {
        this._watchId = this._monitor.add_user_active_watch(() => {
            this._watchId = 0;
            this._watch();
            this._handle(Clutter.get_current_event());
        });
    }

    _handle(event) {
        if (!event)
            return;
        const type = event.type();
        if (type === Clutter.EventType.BUTTON_PRESS || type === Clutter.EventType.TOUCH_BEGIN) {
            this._onReset();
            return;
        }
        const down = type === Clutter.EventType.KEY_PRESS;
        if (!down && type !== Clutter.EventType.KEY_RELEASE)
            return;

        // The same event can be reported more than once.
        const keycode = event.get_key_code() - 8;
        const identity = `${type}:${keycode}:${event.get_time_us?.() ?? event.get_time()}`;
        if (identity === this._last)
            return;
        this._last = identity;

        if (this._consumeSynthetic(keycode, down) || !down)
            return;
        this._onKey({keycode, modifiers: modifiersFromMask(event.get_state())});
    }

    _consumeSynthetic(keycode, down) {
        if (this._expected.length === 0)
            return false;
        if (GLib.get_monotonic_time() - this._expectedAt > SYNTHETIC_TIMEOUT_MICROS) {
            this._expected = [];
            return false;
        }
        const head = this._expected[0];
        if (head.keycode !== keycode || head.down !== down)
            return false;
        this._expected.shift();
        return true;
    }
}
