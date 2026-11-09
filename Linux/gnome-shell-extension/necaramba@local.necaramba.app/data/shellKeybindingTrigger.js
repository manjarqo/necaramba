// Data adapter: arms the gesture through a mutter keybinding and observes the
// following input events through the core idle monitor.
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {modifiersFromMask} from './modifierMask.js';

/**
 * `runtimeSettings` holds one `as` key per binding name: `<name>-accelerators`
 * (`tap-accelerators`, `chord-accelerators`). It is expected to use a memory
 * backend: accelerators are derived state.
 */
export class ShellKeybindingTrigger {
    constructor(runtimeSettings) {
        this._settings = runtimeSettings;
        this._monitor = global.backend.get_core_idle_monitor();
        this._bound = new Set();
        this._watchIds = new Set();
    }

    bind(name, accelerators, onArm) {
        const key = `${name}-accelerators`;
        this._settings.set_strv(key, accelerators);
        const action = Main.wm.addKeybinding(key, this._settings,
            Meta.KeyBindingFlags.IGNORE_AUTOREPEAT, Shell.ActionMode.ALL,
            () => onArm(this._currentModifiers()));
        if (action === Meta.KeyBindingAction.NONE)
            throw new Error(`mutter rejected accelerators ${accelerators.join(', ')}`);
        this._bound.add(key);
    }

    unbindAll() {
        for (const id of this._watchIds)
            this._monitor.remove_watch(id);
        this._watchIds.clear();
        for (const key of this._bound)
            Main.wm.removeKeybinding(key);
        this._bound.clear();
    }

    watchNextInput(callback) {
        const id = this._monitor.add_user_active_watch(() => {
            this._watchIds.delete(id);
            callback(this._currentModifiers());
        });
        this._watchIds.add(id);
    }

    _currentModifiers() {
        const [, , mask] = global.get_pointer();
        return modifiersFromMask(mask);
    }
}
