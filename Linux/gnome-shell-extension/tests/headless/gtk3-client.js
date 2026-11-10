// GTK 3 text field without surrounding text: through XWayland, or on Wayland with
// the simple input method — like Chromium/Electron without Wayland IME. Prints its text to stderr.
imports.gi.versions.Gtk = '3.0';
const {Gtk} = imports.gi;

Gtk.init(null);
const window = new Gtk.Window({title: 'necaramba-headless-gtk3-client', default_width: 480, default_height: 120});
const entry = new Gtk.Entry();
entry.connect('changed', () => printerr(`TEXT ${JSON.stringify(entry.get_text())}`));
window.connect('destroy', () => Gtk.main_quit());
window.add(entry);
window.show_all();
Gtk.main();
