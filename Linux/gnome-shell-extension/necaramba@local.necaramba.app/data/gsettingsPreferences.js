// Data adapter: user preferences and the system XKB options, read from GSettings.

export const SHORTCUT_KEY = 'layout-switch-shortcut';
export const CONVERSION_KEY = 'double-shift-conversion';
const XKB_OPTIONS_KEY = 'xkb-options';

export class GSettingsPreferences {
    /**
     * @param extensionSettings  org.gnome.shell.extensions.necaramba
     * @param inputSourceSettings org.gnome.desktop.input-sources (read only)
     */
    constructor(extensionSettings, inputSourceSettings) {
        this._extension = extensionSettings;
        this._inputSources = inputSourceSettings;
    }

    shortcut() {
        return this._extension.get_string(SHORTCUT_KEY);
    }

    conversionEnabled() {
        return this._extension.get_boolean(CONVERSION_KEY);
    }

    xkbOptions() {
        return this._inputSources.get_strv(XKB_OPTIONS_KEY);
    }

    onChanged(callback) {
        const ids = [
            [this._extension, this._extension.connect(`changed::${SHORTCUT_KEY}`, () => callback())],
            [this._extension, this._extension.connect(`changed::${CONVERSION_KEY}`, () => callback())],
            [this._inputSources, this._inputSources.connect(`changed::${XKB_OPTIONS_KEY}`, () => callback())],
        ];
        return () => ids.forEach(([settings, id]) => settings.disconnect(id));
    }
}
