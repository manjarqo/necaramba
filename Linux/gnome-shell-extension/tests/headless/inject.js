// Injects evdev keycodes through org.gnome.Mutter.RemoteDesktop of the nested shell.
// One long-lived session keeps a single virtual keyboard for the whole test, so the
// focused client does not lose its keyboard between scenarios.
// Protocol: each stdin line is "code:1 code:0 sleep:ms ..." (1 press, 0 release);
// "DONE" is printed after the line has been injected.
const {Gio, GLib, GioUnix} = imports.gi;

const bus = Gio.DBus.session;
const NAME = 'org.gnome.Mutter.RemoteDesktop';
const SESSION = `${NAME}.Session`;
const call = (path, iface, method, params, type = null) => bus.call_sync(NAME, path, iface, method, params,
    type ? new GLib.VariantType(type) : null, Gio.DBusCallFlags.NONE, -1, null);

const [session] = call('/org/gnome/Mutter/RemoteDesktop', NAME, 'CreateSession', null, '(o)').deepUnpack();
call(session, SESSION, 'Start', null);

const input = new Gio.DataInputStream({
    base_stream: new GioUnix.InputStream({fd: 0, close_fd: false}),
});
for (;;) {
    const [line] = input.read_line_utf8(null);
    if (line === null)
        break;
    for (const step of line.split(/\s+/).filter(Boolean)) {
        const [code, value] = step.split(':');
        if (code === 'sleep') {
            GLib.usleep(Number(value) * 1000);
            continue;
        }
        call(session, SESSION, 'NotifyKeyboardKeycode', new GLib.Variant('(ub)', [Number(code), value === '1']));
        GLib.usleep(40000);
    }
    GLib.usleep(250000);
    print('DONE');
}
try {
    call(session, SESSION, 'Stop', null);
} catch {
    // The nested shell may already be gone at the end of the test.
}
