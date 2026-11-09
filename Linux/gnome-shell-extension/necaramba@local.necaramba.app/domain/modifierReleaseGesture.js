// Domain: "press modifiers, release them without typing" gesture.
// Pure JavaScript, no GNOME imports. Timestamps are monotonic microseconds.

/**
 * The compositor reports one notification per input event, but may repeat it
 * for the event that is being processed while a watch is (re)installed.
 * Notifications closer than this window to the previous one are treated as
 * the same event.
 */
const SAME_EVENT_WINDOW_MICROS = 1500;

/**
 * Mirrors the macOS rule: the layout shortcut fires once after the keys are
 * released, provided nothing else was typed or pressed while holding them.
 *
 * `arm()` is called when the last key of the shortcut goes down. Every later
 * input event is passed to `observe()` with the logical modifiers that are
 * still held after that event.
 */
export class ModifierReleaseGesture {
    constructor({sameEventWindowMicros = SAME_EVENT_WINDOW_MICROS} = {}) {
        this._window = sameEventWindowMicros;
        this.reset();
    }

    get armed() {
        return this._held !== null;
    }

    reset() {
        this._held = null;
        this._last = 0;
    }

    arm(modifiers, nowMicros) {
        const held = new Set(modifiers);
        if (held.size === 0) {
            this.reset();
            return;
        }
        this._held = held;
        this._last = nowMicros;
    }

    /** @returns {'idle'|'ignored'|'pending'|'fire'|'cancel'} */
    observe(modifiers, nowMicros) {
        if (!this.armed)
            return 'idle';
        if (nowMicros < this._last) {
            this.reset();
            return 'cancel';
        }
        if (nowMicros - this._last < this._window)
            return 'ignored';
        this._last = nowMicros;

        const now = new Set(modifiers);
        const foreign = [...now].some(modifier => !this._held.has(modifier));
        // Nothing was released: the event was a key, button or pointer action.
        if (foreign || now.size === this._held.size) {
            this.reset();
            return 'cancel';
        }
        if (now.size === 0) {
            this.reset();
            return 'fire';
        }
        this._held = now;
        return 'pending';
    }
}
