// Presentation: the layout-switching preferences page.
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {LayoutSwitchShortcut, nativeConflicts, parseShortcut} from '../domain/layoutShortcut.js';

export const SHORTCUT_KEY = 'layout-switch-shortcut';
export const CONVERSION_KEY = 'double-shift-conversion';

export const SHORTCUT_ORDER = [
    LayoutSwitchShortcut.SINGLE_SHIFT,
    LayoutSwitchShortcut.ALT_SHIFT,
    LayoutSwitchShortcut.CONTROL_SHIFT,
    LayoutSwitchShortcut.COMMAND_SHIFT,
    LayoutSwitchShortcut.DISABLED,
];

/**
 * @param settings       org.gnome.shell.extensions.necaramba
 * @param inputSources   org.gnome.desktop.input-sources (read only)
 * @param strings        localized strings
 * @returns {{page: Adw.PreferencesPage, shortcutRow: Adw.ComboRow, conflictRow: Adw.ActionRow,
 *            conversionRow: Adw.SwitchRow, destroy: Function}}
 */
export function buildPreferencesPage(settings, inputSources, strings) {
    const page = new Adw.PreferencesPage({title: strings.page, icon_name: 'input-keyboard-symbolic'});
    const group = new Adw.PreferencesGroup({title: strings.group, description: strings.groupDescription});
    const shortcutRow = new Adw.ComboRow({
        title: strings.shortcut,
        model: Gtk.StringList.new(SHORTCUT_ORDER.map(value => strings[value])),
    });
    const conflictRow = new Adw.ActionRow({title: strings.conflictTitle, subtitle_lines: 0});
    conflictRow.add_prefix(new Gtk.Image({icon_name: 'dialog-warning-symbolic'}));
    group.add(shortcutRow);
    group.add(conflictRow);

    const conversionGroup = new Adw.PreferencesGroup();
    const conversionRow = new Adw.SwitchRow({
        title: strings.conversionTitle,
        subtitle: strings.conversionBody,
        subtitle_lines: 0,
    });
    settings.bind(CONVERSION_KEY, conversionRow, 'active', Gio.SettingsBindFlags.DEFAULT);
    conversionGroup.add(conversionRow);

    const info = new Adw.PreferencesGroup();
    info.add(new Adw.ActionRow({title: strings.sourcesTitle, subtitle: strings.sourcesBody, subtitle_lines: 0}));
    page.add(conversionGroup);
    page.add(group);
    page.add(info);

    const sync = () => {
        const shortcut = parseShortcut(settings.get_string(SHORTCUT_KEY));
        shortcutRow.selected = SHORTCUT_ORDER.indexOf(shortcut);
        const conflicts = nativeConflicts(shortcut, inputSources.get_strv('xkb-options'));
        conflictRow.visible = conflicts.length > 0;
        conflictRow.subtitle = strings.conflictBody.replace('%s', conflicts.join(', '));
    };
    shortcutRow.connect('notify::selected', () => {
        const value = SHORTCUT_ORDER[shortcutRow.selected];
        if (value && value !== settings.get_string(SHORTCUT_KEY))
            settings.set_string(SHORTCUT_KEY, value);
    });
    const ids = [
        [settings, settings.connect(`changed::${SHORTCUT_KEY}`, sync)],
        [inputSources, inputSources.connect('changed::xkb-options', sync)],
    ];
    sync();
    return {
        page,
        shortcutRow,
        conflictRow,
        conversionRow,
        destroy: () => {
            ids.forEach(([source, id]) => source.disconnect(id));
            Gio.Settings.unbind(conversionRow, 'active');
        },
    };
}
