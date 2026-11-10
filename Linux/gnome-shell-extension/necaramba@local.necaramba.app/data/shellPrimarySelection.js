// Data adapter: the PRIMARY selection (the selected text), for apps that do not
// report surrounding text — Electron/Chromium, XWayland.
//
// PRIMARY often keeps old text after the selection is gone, so it only counts
// as "fresh" when its owner changed after the last user key press or click.
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';

/** Owner changes right after a conversion are the app reacting to our typing. */
const OWN_ECHO_MICROS = 500_000;

export class ShellPrimarySelection {
    constructor() {
        this._fresh = false;
        this._ignoreUntil = 0;
        this._selection = null;
        this._ownerId = 0;
    }

    start() {
        this._selection = global.display.get_selection();
        this._ownerId = this._selection.connect('owner-changed', (_selection, type, source) => {
            if (type !== Meta.SelectionType.SELECTION_PRIMARY)
                return;
            if (GLib.get_monotonic_time() < this._ignoreUntil)
                return;
            this._fresh = source !== null;
        });
    }

    stop() {
        if (this._ownerId)
            this._selection.disconnect(this._ownerId);
        this._ownerId = 0;
        this._selection = null;
        this._fresh = false;
    }

    /** A key press (not a bare modifier) or a click: an older selection is stale. */
    noteUserInput() {
        this._fresh = false;
    }

    isFresh() {
        return this._fresh;
    }

    read() {
        return new Promise(resolve => {
            St.Clipboard.get_default().get_text(St.ClipboardType.PRIMARY, (_clipboard, text) => resolve(text ?? null));
        });
    }

    consume() {
        this._fresh = false;
        this._ignoreUntil = GLib.get_monotonic_time() + OWN_ECHO_MICROS;
    }
}
