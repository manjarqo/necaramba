// Focused GTK4 text field; prints its text to (unbuffered) stderr after every change.
imports.gi.versions.Gtk = '4.0';
const {Gtk, GLib} = imports.gi;
Gtk.init();
const window = new Gtk.Window({title: 'necaramba-headless-client', default_width: 480, default_height: 120});
const entry = new Gtk.Entry();
entry.connect('changed', () => printerr(`TEXT ${JSON.stringify(entry.get_text())}`));
window.set_child(entry);
window.present();
GLib.MainLoop.new(null, false).run();
