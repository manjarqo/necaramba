// Domain: which text a double Shift converts. Pure JavaScript.
// Offsets are Unicode code points, as reported by the compositor's text-input.

const MAX_WORD = 128;
const MAX_SELECTION = 1024;
const isInlineSpace = character => character === ' ' || character === '\t';
const isWhitespace = character => /\s/u.test(character);

/**
 * - A non-empty selection is converted as a whole.
 * - Otherwise the last word before the caret: spaces typed after it are kept,
 *   a line break is never crossed.
 *
 * @returns {null | {kind: 'selection', original: string}
 *                | {kind: 'word', original: string, deleteBefore: number, trailing: string}}
 */
export function findConversionRange(text, cursor, anchor) {
    if (typeof text !== 'string')
        return null;
    const characters = Array.from(text);
    const valid = offset => Number.isInteger(offset) && offset >= 0 && offset <= characters.length;
    if (!valid(cursor))
        return null;

    if (valid(anchor) && anchor !== cursor) {
        const start = Math.min(anchor, cursor);
        const end = Math.max(anchor, cursor);
        if (end - start > MAX_SELECTION)
            return null;
        return {kind: 'selection', original: characters.slice(start, end).join('')};
    }

    let end = cursor;
    while (end > 0 && isInlineSpace(characters[end - 1]))
        end--;
    let start = end;
    while (start > 0 && !isWhitespace(characters[start - 1]))
        start--;
    if (start === end || end - start > MAX_WORD)
        return null;
    return {
        kind: 'word',
        original: characters.slice(start, end).join(''),
        deleteBefore: cursor - start,
        trailing: characters.slice(end, cursor).join(''),
    };
}
