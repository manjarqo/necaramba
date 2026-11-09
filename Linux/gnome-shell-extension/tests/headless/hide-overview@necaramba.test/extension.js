// Test helper only: leaves the startup overview so the test client keeps keyboard focus.
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class HideOverview extends Extension {
    enable() {
        this._id = Main.layoutManager.connect('startup-complete', () => Main.overview.hide());
        // Extensions may be enabled after startup already completed.
        if (!Main.layoutManager._startingUp)
            Main.overview.hide();
    }

    disable() {
        Main.layoutManager.disconnect(this._id);
    }
}
