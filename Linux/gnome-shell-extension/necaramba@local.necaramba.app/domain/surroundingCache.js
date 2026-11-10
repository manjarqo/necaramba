// Domain: last surrounding text reported by the focused field. Pure JavaScript.
//
// GNOME Shell's input method forgets the surrounding text when it is reset (for
// example when the first Shift tap switches the layout). GTK reports it again
// right away; Chromium/Electron does not until the text changes. The last report
// stays usable as long as the same field has focus and no key press or click
// happened since — those may change the text without a new report.

export class SurroundingCache {
    constructor() {
        this._report = null;
        this._focus = null;
    }

    /** @param report {text, cursor, anchor}  @param focus  identity of the focused field */
    remember(report, focus) {
        if (typeof report?.text !== 'string' || !focus)
            return;
        this._report = {...report};
        this._focus = focus;
    }

    invalidate() {
        this._report = null;
        this._focus = null;
    }

    resolve(current, focus) {
        if (typeof current?.text === 'string' || !focus || focus !== this._focus || !this._report)
            return current;
        return {...this._report};
    }
}
