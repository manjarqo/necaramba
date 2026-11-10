// Data adapter: the focused text field, through GNOME Shell's input method.
//
// Wayland applications that support text-input-v3 (GTK, Qt, Firefox, Chromium
// with Wayland IME, …) report the text around the caret to the compositor; the
// input method can delete around the caret and commit text. No clipboard and no
// synthetic keys are used. Offsets are Unicode code points.
import IBus from 'gi://IBus';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {SurroundingCache} from '../domain/surroundingCache.js';

const SENSITIVE_PURPOSES = [IBus.InputPurpose.PASSWORD, IBus.InputPurpose.PIN];
const SENSITIVE_HINTS = (IBus.InputHints.PRIVATE ?? 0) | (IBus.InputHints.HIDDEN_TEXT ?? 0);
const TERMINAL_PURPOSE = IBus.InputPurpose.TERMINAL ?? -1;

export class ShellTextInput {
    constructor() {
        this._cache = new SurroundingCache();
        this._signalId = 0;
    }

    start() {
        const inputMethod = Main.inputMethod;
        this._signalId = inputMethod.connect('surrounding-text-set', () => {
            const [text, cursor, anchor] = inputMethod.getSurroundingText();
            this._cache.remember({text, cursor, anchor}, inputMethod.currentFocus);
        });
    }

    stop() {
        if (this._signalId)
            Main.inputMethod.disconnect(this._signalId);
        this._signalId = 0;
        this._cache.invalidate();
    }

    /** A key press or click may change the text without a new report. */
    noteUserInput() {
        this._cache.invalidate();
    }

    snapshot() {
        const inputMethod = Main.inputMethod;
        const focus = inputMethod?.currentFocus;
        if (!focus)
            return null;
        const [text, cursor, anchor] = inputMethod.getSurroundingText();
        const report = this._cache.resolve({text, cursor, anchor}, focus);
        // `_purpose`/`_hints` are the shell's own IBus translations of the field's content type.
        const sensitive = SENSITIVE_PURPOSES.includes(inputMethod._purpose) ||
            (inputMethod._hints & SENSITIVE_HINTS) !== 0;
        return {focused: true, sensitive, terminal: inputMethod._purpose === TERMINAL_PURPOSE, ...report};
    }

    replace({deleteBefore, text}) {
        const inputMethod = Main.inputMethod;
        if (deleteBefore > 0)
            inputMethod.delete_surrounding(-deleteBefore, deleteBefore);
        inputMethod.commit(text);
        // The field reports the new text itself; never reuse the old one.
        this._cache.invalidate();
    }
}
