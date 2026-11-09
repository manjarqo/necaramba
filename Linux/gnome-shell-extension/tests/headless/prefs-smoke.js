// Smoke test of the preferences page inside the nested session.
// Usage: gjs -m prefs-smoke.js <installed schemas dir>
import 'gi://Gtk?version=4.0';
import Adw from 'gi://Adw?version=1';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

import {buildPreferencesPage} from '../../necaramba@local.necaramba.app/presentation/preferencesPage.js';
import {localizedStrings} from '../../necaramba@local.necaramba.app/presentation/strings.js';

const [schemaDir] = ARGV;
const source = Gio.SettingsSchemaSource.new_from_directory(schemaDir, Gio.SettingsSchemaSource.get_default(), false);
const settings = new Gio.Settings({settings_schema: source.lookup('org.gnome.shell.extensions.necaramba', true)});
const inputSources = new Gio.Settings({schema_id: 'org.gnome.desktop.input-sources'});

let failures = 0;
const check = (name, condition) => {
    print(`${condition ? 'PASS' : 'FAIL'} prefs: ${name}`);
    if (!condition)
        failures++;
};
const settle = () => {
    const context = GLib.MainContext.default();
    for (let i = 0; i < 50; i++)
        context.iteration(false);
};

Adw.init();
settings.set_string('layout-switch-shortcut', 'singleShift');
inputSources.set_strv('xkb-options', []);
const strings = localizedStrings(['en_US.UTF-8', 'en']);
const view = buildPreferencesPage(settings, inputSources, strings);
const window = new Adw.PreferencesWindow();
window.add(view.page);
window.present();
settle();

check('shows the stored shortcut', view.shortcutRow.selected === 0);
check('lists five choices', view.shortcutRow.model.get_n_items() === 5);
check('no conflict warning without XKB toggles', view.conflictRow.visible === false);

view.shortcutRow.selected = 1;
settle();
check('choosing Alt + Shift stores altShift', settings.get_string('layout-switch-shortcut') === 'altShift');

inputSources.set_strv('xkb-options', ['grp:alt_shift_toggle']);
settle();
check('native Alt+Shift toggle shows the conflict warning',
    view.conflictRow.visible && view.conflictRow.subtitle.includes('grp:alt_shift_toggle'));

settings.set_string('layout-switch-shortcut', 'controlShift');
settle();
check('external change updates the row and hides the warning',
    view.shortcutRow.selected === 2 && view.conflictRow.visible === false);

check('conversion switch reflects the setting', view.conversionRow.active === true);
view.conversionRow.active = false;
settle();
check('turning the switch off stores false', settings.get_boolean('double-shift-conversion') === false);
settings.set_boolean('double-shift-conversion', true);

check('Russian locale gets Russian strings',
    localizedStrings(['ru_RU.UTF-8', 'ru', 'C']).disabled === 'Выключено');

view.destroy();
window.destroy();
inputSources.set_strv('xkb-options', []);
settings.set_string('layout-switch-shortcut', 'singleShift');
System.exit(failures === 0 ? 0 : 1);
