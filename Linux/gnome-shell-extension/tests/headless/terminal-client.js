// VTE terminal (the widget behind Ptyxis and GNOME Terminal). It does not report
// surrounding text, so double Shift must take the retype path. Prints the line
// under the cursor to stderr whenever it changes.
imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Vte = '3.91';
const {Gtk, GLib, Vte} = imports.gi;

Gtk.init();
const window = new Gtk.Window({title: 'necaramba-headless-terminal', default_width: 640, default_height: 240});
const terminal = new Vte.Terminal();
window.set_child(terminal);
window.present();
// A shell-like line reader: the tty echoes and edits the line (BackSpace works), Enter starts a new one.
terminal.spawn_async(Vte.PtyFlags.DEFAULT, null, ['/bin/sh', '-c', 'while read -r line; do :; done'],
    null, GLib.SpawnFlags.DEFAULT, null, -1, null, () => {});
terminal.grab_focus();

let last = null;
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
    const [, row] = terminal.get_cursor_position();
    const lines = (terminal.get_text_format(Vte.Format.TEXT) ?? '').split('\n');
    const line = (lines[row] ?? '').trimEnd();
    if (line !== last) {
        last = line;
        printerr(`TEXT ${JSON.stringify(line)}`);
    }
    return GLib.SOURCE_CONTINUE;
});
GLib.MainLoop.new(null, false).run();
