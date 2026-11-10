// Composition root for the GNOME Shell runtime.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {ConvertLastWord} from './application/convertLastWord.js';
import {ShortcutController} from './application/shortcutController.js';
import {switchToNextLayout} from './application/switchToNextLayout.js';
import {GSettingsPreferences} from './data/gsettingsPreferences.js';
import {ShellInputSources} from './data/shellInputSources.js';
import {ShellKeybindingTrigger} from './data/shellKeybindingTrigger.js';
import {ShellKeyObserver} from './data/shellKeyObserver.js';
import {ShellPrimarySelection} from './data/shellPrimarySelection.js';
import {ShellTextInput} from './data/shellTextInput.js';
import {VirtualKeyboard} from './data/virtualKeyboard.js';
import {layoutForSource} from './domain/layoutTables.js';
import {TypedWordBuffer, isModifierKey} from './domain/typedWordBuffer.js';

const RUNTIME_SCHEMA = 'org.gnome.shell.extensions.necaramba.runtime';

export default class NecarambaExtension extends Extension {
    enable() {
        const inputSources = new ShellInputSources();
        const typedWord = new TypedWordBuffer();
        this._selection = new ShellPrimarySelection();
        this._textInput = new ShellTextInput();
        this._observer = new ShellKeyObserver({
            onKey: key => {
                if (!isModifierKey(key.keycode)) {
                    this._selection.noteUserInput();
                    this._textInput.noteUserInput();
                }
                typedWord.press({
                    ...key,
                    layout: layoutForSource(inputSources.sources()[inputSources.currentIndex()]),
                });
            },
            onReset: () => {
                this._selection.noteUserInput();
                this._textInput.noteUserInput();
                typedWord.reset();
            },
        });
        const convertLastWord = new ConvertLastWord({
            textInput: this._textInput,
            inputSources,
            typedWord,
            keyboard: new VirtualKeyboard(this._observer),
            selection: this._selection,
        });
        this._controller = new ShortcutController({
            preferences: new GSettingsPreferences(
                this.getSettings(),
                new Gio.Settings({schema_id: 'org.gnome.desktop.input-sources'})),
            trigger: new ShellKeybindingTrigger(this._runtimeSettings()),
            clock: {nowMicros: () => GLib.get_monotonic_time()},
            logger: {log: message => console.log(`${this.uuid}: ${message}`)},
            actions: {
                switchLayout: () => switchToNextLayout(inputSources),
                convertWord: () => convertLastWord.execute()
                    .then(result => console.log(`${this.uuid}: double Shift: ${result.status}${result.method ? ` (${result.method})` : ''}`))
                    .catch(error => logError(error, this.uuid)),
            },
        });
        this._selection.start();
        this._textInput.start();
        this._observer.start();
        this._controller.start();
    }

    disable() {
        this._controller?.stop();
        this._controller = null;
        this._observer?.stop();
        this._observer = null;
        this._selection?.stop();
        this._selection = null;
        this._textInput?.stop();
        this._textInput = null;
    }

    /** Derived keybinding state lives in memory and never reaches dconf. */
    _runtimeSettings() {
        const source = Gio.SettingsSchemaSource.new_from_directory(
            this.dir.get_child('schemas').get_path(),
            Gio.SettingsSchemaSource.get_default(), false);
        return new Gio.Settings({
            settings_schema: source.lookup(RUNTIME_SCHEMA, true),
            backend: Gio.memory_settings_backend_new(),
        });
    }
}
