// Data adapter: GNOME Shell input sources (the Wayland-safe way to switch layouts).
import {getInputSourceManager} from 'resource:///org/gnome/shell/ui/status/keyboard.js';

export class ShellInputSources {
    constructor(manager = getInputSourceManager()) {
        this._manager = manager;
    }

    /** Ordered as in Settings: [{type: 'xkb' | 'ibus', id}] */
    sources() {
        return Object.values(this._manager.inputSources ?? {})
            .sort((a, b) => a.index - b.index)
            .map(source => ({type: source.type, id: source.id}));
    }

    currentIndex() {
        return this._manager.currentSource?.index ?? 0;
    }

    /** Activates without the switcher popup, like a direct click in the menu. */
    activate(index) {
        this._manager.inputSources?.[index]?.activate(true);
    }
}
