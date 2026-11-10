// Domain: positional keyboard tables and text conversion. Pure JavaScript.
//
// Each string lists the characters of one shift level in physical key order:
// TLDE, AE01..AE12, AD01..AD12, AC01..AC11, BKSL, AB01..AB10 (47 keys),
// matching the XKB `us` and `ru` layouts shipped with Fedora.

const TABLES = {
    us: {
        lower: "`1234567890-=qwertyuiop[]asdfghjkl;'\\zxcvbnm,./",
        upper: '~!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:"|ZXCVBNM<>?',
    },
    ru: {
        lower: 'ё1234567890-=йцукенгшщзхъфывапролджэ\\ячсмитьбю.',
        upper: 'Ё!"№;%:?*()_+ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭ/ЯЧСМИТЬБЮ,',
    },
};

/** evdev key codes of the 47 table positions, in table order. */
export const CONVERTIBLE_KEYCODES = Object.freeze([
    41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    43,
    44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
]);

export function hasLayoutTable(layout) {
    return Object.hasOwn(TABLES, layout);
}

/** Only plain XKB layouts with a table take part in conversion. */
export function layoutForSource(source) {
    if (source?.type !== 'xkb' || !hasLayoutTable(source.id))
        return null;
    return source.id;
}

const mappings = new Map();

function mapping(from, to) {
    const key = `${from}>${to}`;
    if (!mappings.has(key)) {
        const map = new Map();
        for (const level of ['lower', 'upper']) {
            const source = Array.from(TABLES[from][level]);
            const target = Array.from(TABLES[to][level]);
            source.forEach((character, index) => {
                if (!map.has(character))
                    map.set(character, target[index]);
            });
        }
        mappings.set(key, map);
    }
    return mappings.get(key);
}

export function convertText(text, from, to) {
    const map = mapping(from, to);
    return Array.from(text).map(character => map.get(character) ?? character).join('');
}

const SPACE_KEYCODE = 57;

/**
 * The physical keys that type `text` in `layout`, or null when some character
 * has no key in the table (only spaces and the 47 table keys are supported).
 */
export function keysForText(text, layout) {
    const lower = Array.from(TABLES[layout].lower);
    const upper = Array.from(TABLES[layout].upper);
    const keys = [];
    for (const character of Array.from(text)) {
        if (character === ' ') {
            keys.push({keycode: SPACE_KEYCODE, shift: false});
            continue;
        }
        let index = lower.indexOf(character);
        let shift = false;
        if (index < 0) {
            index = upper.indexOf(character);
            shift = true;
        }
        if (index < 0)
            return null;
        keys.push({keycode: CONVERTIBLE_KEYCODES[index], shift});
    }
    return keys;
}

/**
 * Letters decide which layout the text was typed in; text without letters or
 * with a tie keeps the fallback (normally the active layout).
 */
export function detectSourceLayout(text, layouts, fallback) {
    const letters = Array.from(text).filter(character => /\p{L}/u.test(character));
    const scores = layouts.map(layout => {
        const all = TABLES[layout].lower + TABLES[layout].upper;
        return letters.filter(character => all.includes(character)).length;
    });
    const top = Math.max(0, ...scores);
    const leaders = layouts.filter((_, index) => scores[index] === top);
    if (top > 0 && leaders.length === 1)
        return leaders[0];
    return layouts.includes(fallback) ? fallback : layouts[0];
}
