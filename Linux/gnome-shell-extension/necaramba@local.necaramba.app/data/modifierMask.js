// Data: Clutter modifier masks -> logical modifier names.
import Clutter from 'gi://Clutter';

const LOGICAL_BITS = [
    ['shift', Clutter.ModifierType.SHIFT_MASK],
    ['control', Clutter.ModifierType.CONTROL_MASK],
    ['alt', Clutter.ModifierType.MOD1_MASK | Clutter.ModifierType.META_MASK],
    ['super', Clutter.ModifierType.MOD4_MASK | Clutter.ModifierType.SUPER_MASK |
        Clutter.ModifierType.HYPER_MASK],
    ['level3', Clutter.ModifierType.MOD5_MASK],
    ['button', Clutter.ModifierType.BUTTON1_MASK | Clutter.ModifierType.BUTTON2_MASK |
        Clutter.ModifierType.BUTTON3_MASK | Clutter.ModifierType.BUTTON4_MASK |
        Clutter.ModifierType.BUTTON5_MASK],
];

/** Lock states (Caps Lock, Num Lock) are deliberately not logical modifiers. */
export function modifiersFromMask(mask) {
    return LOGICAL_BITS.filter(([, bits]) => (mask & bits) !== 0).map(([name]) => name);
}
