// Application: convert the last word (or the selection) to the other layout.
import {findConversionRange} from '../domain/conversionRange.js';
import {convertText, detectSourceLayout, keysForText, layoutForSource} from '../domain/layoutTables.js';

const SPACE = 57;

/**
 * Three methods:
 * - surrounding: the field reports its text (GTK, Qt, Firefox). The word is
 *   read, converted by key position and replaced through the input method.
 * - retype: no surrounding text (terminals, XWayland/Electron). The word is
 *   erased with BackSpace, the target layout selected and the same physical
 *   keys typed again, as on macOS.
 * - selection: no surrounding text and nothing typed since the caret moved, but
 *   a fresh selection (PRIMARY). The target layout is selected and the keys
 *   that type the selected text are pressed; typing replaces the selection.
 *
 * Ports:
 * - textInput: { snapshot(): null | {focused, sensitive, terminal, text, cursor, anchor},
 *                replace({deleteBefore, text}) }
 * - inputSources: { sources(): [{type, id}], currentIndex(): number, activate(index) }
 * - typedWord: { snapshot(): null | {layout, keys: [{keycode, shift}], trailingSpaces},
 *                relayout(layout),
 *                replace(layout, keys), reset() }
 * - keyboard: { backspace(count), type(keys) }
 * - selection: { isFresh(): boolean, read(): Promise<string|null>, consume() }
 *   Fresh means it changed after the last user key press or click.
 */
export class ConvertLastWord {
    constructor({textInput, inputSources, typedWord, keyboard, selection}) {
        this._textInput = textInput;
        this._inputSources = inputSources;
        this._typedWord = typedWord;
        this._keyboard = keyboard;
        this._selection = selection;
    }

    async execute() {
        const snapshot = this._textInput.snapshot();
        if (snapshot?.sensitive)
            return {status: 'unavailable'};

        const sources = this._inputSources.sources();
        const indexOf = new Map();
        sources.forEach((source, index) => {
            const layout = layoutForSource(source);
            if (layout && !indexOf.has(layout))
                indexOf.set(layout, index);
        });
        const layouts = [...indexOf.keys()];
        if (layouts.length < 2)
            return {status: 'noLayoutPair'};

        if (typeof snapshot?.text === 'string')
            return this._convertSurrounding(snapshot, sources, layouts, indexOf);
        const typed = this._typedWord.snapshot();
        if (typed && layouts.includes(typed.layout))
            return this._retype(typed, layouts, indexOf);
        // In a terminal typing goes to the cursor, it does not replace a selection.
        if (!snapshot?.terminal && this._selection.isFresh())
            return this._retypeSelection(sources, layouts, indexOf);
        return {status: 'nothing'};
    }

    _convertSurrounding(snapshot, sources, layouts, indexOf) {
        const range = findConversionRange(snapshot.text, snapshot.cursor, snapshot.anchor);
        if (!range)
            return {status: 'nothing'};

        const currentIndex = this._inputSources.currentIndex();
        const current = layoutForSource(sources[currentIndex]);
        const from = detectSourceLayout(range.original, layouts, current);
        const to = layouts.find(layout => layout !== from);
        const converted = convertText(range.original, from, to);
        if (converted === range.original)
            return {status: 'unchanged'};

        if (range.kind === 'selection')
            this._textInput.replace({deleteBefore: 0, text: converted});
        else
            this._textInput.replace({deleteBefore: range.deleteBefore, text: converted + range.trailing});
        this._typedWord.relayout(to);
        this._select(indexOf.get(to));
        return {status: 'converted', from, to, method: 'surrounding'};
    }

    _retype(typed, layouts, indexOf) {
        const from = typed.layout;
        const to = layouts.find(layout => layout !== from);

        const spaces = Array.from({length: typed.trailingSpaces}, () => ({keycode: SPACE, shift: false}));
        this._keyboard.backspace(typed.keys.length + typed.trailingSpaces);
        this._select(indexOf.get(to));
        this._keyboard.type([...typed.keys, ...spaces]);
        this._typedWord.relayout(to);
        return {status: 'converted', from, to, method: 'retype'};
    }

    async _retypeSelection(sources, layouts, indexOf) {
        const text = await this._selection.read();
        this._selection.consume();
        if (!text)
            return {status: 'nothing'};

        const current = layoutForSource(sources[this._inputSources.currentIndex()]);
        const from = detectSourceLayout(text, layouts, current);
        const to = layouts.find(layout => layout !== from);
        const keys = keysForText(text, from);
        if (!keys || convertText(text, from, to) === text)
            return {status: 'unchanged'};

        this._select(indexOf.get(to));
        this._keyboard.type(keys);
        if (keys.some(key => key.keycode === SPACE))
            this._typedWord.reset();
        else
            this._typedWord.replace(to, keys);
        return {status: 'converted', from, to, method: 'selection'};
    }

    _select(index) {
        if (index !== this._inputSources.currentIndex())
            this._inputSources.activate(index);
    }
}
