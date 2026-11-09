// Domain: physical keys of the word being typed. Pure JavaScript.
//
// Used where the application does not report the text around the caret
// (terminals, XWayland/Electron). The word is converted by erasing it and
// retyping the same physical keys in the other layout, as on macOS.
import {CONVERTIBLE_KEYCODES} from './layoutTables.js';

const CONVERTIBLE = new Set(CONVERTIBLE_KEYCODES);
// Shift, Ctrl, Alt, Super (left/right), AltGr, Caps Lock.
const MODIFIER_KEYS = new Set([42, 54, 29, 97, 56, 100, 125, 126, 58]);
const SPACE = 57;
const BACKSPACE = 14;
const SHORTCUT_MODIFIERS = ['control', 'alt', 'super', 'level3'];

export class TypedWordBuffer {
    constructor({maxKeys = 128} = {}) {
        this._maxKeys = maxKeys;
        this.reset();
    }

    reset() {
        this._keys = [];
        this._trailing = 0;
        this._layout = null;
    }

    /** @param {{keycode: number, modifiers: string[], layout: string|null}} key  a key press */
    press({keycode, modifiers, layout}) {
        if (MODIFIER_KEYS.has(keycode))
            return;
        if (modifiers.some(modifier => SHORTCUT_MODIFIERS.includes(modifier))) {
            this.reset();
            return;
        }
        if (keycode === BACKSPACE) {
            if (this._trailing > 0)
                this._trailing--;
            else
                this._keys.pop();
            if (this._keys.length === 0)
                this.reset();
            return;
        }
        if (keycode === SPACE) {
            if (this._keys.length === 0)
                this.reset();
            else
                this._trailing++;
            return;
        }
        if (!CONVERTIBLE.has(keycode) || !layout) {
            this.reset();
            return;
        }
        if (this._trailing > 0 || this._layout !== layout) {
            this.reset();
            this._layout = layout;
        }
        this._keys.push({keycode, shift: modifiers.includes('shift')});
        if (this._keys.length > this._maxKeys)
            this.reset();
    }

    /** The word now belongs to `layout` (it was converted by retyping or replacing). */
    relayout(layout) {
        if (this._keys.length > 0)
            this._layout = layout;
    }

    snapshot() {
        if (this._keys.length === 0)
            return null;
        return {
            layout: this._layout,
            keys: this._keys.map(key => ({...key})),
            trailingSpaces: this._trailing,
        };
    }
}
