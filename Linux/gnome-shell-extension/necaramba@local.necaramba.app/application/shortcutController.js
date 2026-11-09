// Application: turns keyboard gestures into actions. Depends on domain and ports only.
import {
    LayoutSwitchShortcut,
    parseShortcut,
    shortcutPlan,
    nativeConflicts,
} from '../domain/layoutShortcut.js';
import {ModifierReleaseGesture} from '../domain/modifierReleaseGesture.js';

/** Second Shift press must follow the first release within this window (as on macOS). */
const DOUBLE_TAP_WINDOW_MICROS = 300_000;
/**
 * The compositor may echo a release with another notification a few
 * milliseconds later; later notifications are real input.
 */
const RELEASE_ECHO_MICROS = 20_000;
const TAP_ACCELERATORS = ['Shift_L', 'Shift_R'];

/**
 * Gestures:
 * - Shift tap (press and release alone): switches the layout when the shortcut is
 *   `singleShift`. It switches immediately, so typing right after a tap is never late.
 * - Double Shift (second press within 300 ms of the first release): converts the
 *   last word instead of the second switch. Conversion selects the target layout
 *   itself, so the first tap's switch never leaves the wrong layout active.
 * - Alt/Ctrl/Super + Shift chords: switch the layout.
 *
 * Ports:
 * - preferences: { shortcut(), conversionEnabled(), xkbOptions(), onChanged(cb) => unsubscribe }
 * - trigger: { bind(name, accelerators, onArm(modifiers)), unbindAll(), watchNextInput(cb(modifiers)) }
 * - clock: { nowMicros() }
 * - logger: { log(message) }
 * - actions: { switchLayout(), convertWord() }
 */
export class ShortcutController {
    constructor({preferences, trigger, clock, logger, actions}) {
        this._preferences = preferences;
        this._trigger = trigger;
        this._clock = clock;
        this._logger = logger;
        this._actions = actions;
        this._tap = new ModifierReleaseGesture();
        this._chord = new ModifierReleaseGesture();
        this._unsubscribe = null;
        this._resetState();
        this._status = {shortcut: LayoutSwitchShortcut.DISABLED, layoutActive: false, conversion: false, conflicts: []};
    }

    get status() {
        return {...this._status, conflicts: [...this._status.conflicts]};
    }

    start() {
        this._unsubscribe = this._preferences.onChanged(() => this._apply());
        this._apply();
    }

    stop() {
        this._unsubscribe?.();
        this._unsubscribe = null;
        this._release();
        this._status = {...this._status, layoutActive: false, conversion: false};
    }

    _resetState() {
        this._tap.reset();
        this._chord.reset();
        this._watching = false;
        this._firstReleaseAt = null;
        this._secondPress = false;
    }

    _release() {
        this._trigger.unbindAll();
        this._resetState();
    }

    _apply() {
        this._release();
        const shortcut = parseShortcut(this._preferences.shortcut());
        const conversion = Boolean(this._preferences.conversionEnabled());
        const plan = shortcutPlan(shortcut);
        const conflicts = nativeConflicts(shortcut, this._preferences.xkbOptions());
        const layoutActive = plan.accelerators.length > 0 && conflicts.length === 0;
        this._status = {shortcut, layoutActive, conversion, conflicts};
        if (conflicts.length > 0)
            this._logger.log(`layout shortcut ${shortcut} left to native XKB option(s): ${conflicts.join(', ')}`);

        this._tapSwitches = layoutActive && shortcut === LayoutSwitchShortcut.SINGLE_SHIFT;
        this._tapConverts = conversion;
        if (this._tapSwitches || this._tapConverts)
            this._trigger.bind('tap', TAP_ACCELERATORS, modifiers => this._onTapArm(modifiers));
        if (layoutActive && shortcut !== LayoutSwitchShortcut.SINGLE_SHIFT)
            this._trigger.bind('chord', plan.accelerators, modifiers => this._onChordArm(plan.modifiers, modifiers));
    }

    _onTapArm(modifiers) {
        if (!sameModifiers(modifiers, ['shift']))
            return;
        const now = this._clock.nowMicros();
        this._secondPress = this._firstReleaseAt !== null &&
            now >= this._firstReleaseAt && now - this._firstReleaseAt < DOUBLE_TAP_WINDOW_MICROS;
        this._tap.arm(['shift'], now);
        this._watch();
    }

    _onChordArm(required, modifiers) {
        if (!sameModifiers(modifiers, required))
            return;
        this._chord.arm(required, this._clock.nowMicros());
        this._watch();
    }

    _watch() {
        if (this._watching)
            return;
        this._watching = true;
        this._trigger.watchNextInput(modifiers => {
            this._watching = false;
            this._onInput(modifiers);
        });
    }

    _onInput(modifiers) {
        const now = this._clock.nowMicros();
        // Between the taps, only the next Shift press may happen. A notification
        // with Shift held is that press (the watch may report it before the
        // keybinding does); anything else — a letter, a click — ends the window.
        if (this._firstReleaseAt !== null && !this._tap.armed &&
            now - this._firstReleaseAt >= RELEASE_ECHO_MICROS &&
            !sameModifiers(modifiers, ['shift']))
            this._firstReleaseAt = null;

        switch (this._tap.observe(modifiers, now)) {
        case 'fire':
            this._onTapFire(now);
            break;
        case 'cancel':
            this._firstReleaseAt = null;
            this._secondPress = false;
            break;
        default:
            break;
        }
        if (this._chord.observe(modifiers, now) === 'fire')
            this._actions.switchLayout();

        if (this._tap.armed || this._chord.armed || this._firstReleaseAt !== null)
            this._watch();
    }

    _onTapFire(now) {
        if (this._secondPress && this._tapConverts) {
            this._secondPress = false;
            this._firstReleaseAt = null;
            this._actions.convertWord();
            return;
        }
        this._secondPress = false;
        if (this._tapSwitches)
            this._actions.switchLayout();
        this._firstReleaseAt = this._tapConverts ? now : null;
    }
}

function sameModifiers(live, required) {
    const a = [...new Set(live)].sort();
    const b = [...required].sort();
    return a.length === b.length && a.every((modifier, index) => modifier === b[index]);
}
