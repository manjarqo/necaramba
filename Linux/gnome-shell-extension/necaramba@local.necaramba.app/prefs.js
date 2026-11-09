// Composition root of the preferences window (runs in the GNOME Extensions app).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {buildPreferencesPage} from './presentation/preferencesPage.js';
import {localizedStrings} from './presentation/strings.js';

export default class NecarambaPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const view = buildPreferencesPage(
            this.getSettings(),
            new Gio.Settings({schema_id: 'org.gnome.desktop.input-sources'}),
            localizedStrings(GLib.get_language_names()));
        window.add(view.page);
        window.connect('close-request', () => {
            view.destroy();
            return false;
        });
    }
}
