// Data adapter: the focused text field, through GNOME Shell's input method.
//
// Wayland applications that support text-input-v3 (GTK, Qt, Firefox, …) report
// the text around the caret to the compositor; the input method can delete
// around the caret and commit text. No clipboard and no synthetic keys are used.
// Offsets are Unicode code points.
import IBus from 'gi://IBus';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const SENSITIVE_PURPOSES = [IBus.InputPurpose.PASSWORD, IBus.InputPurpose.PIN];
const SENSITIVE_HINTS = (IBus.InputHints.PRIVATE ?? 0) | (IBus.InputHints.HIDDEN_TEXT ?? 0);

export class ShellTextInput {
    snapshot() {
        const inputMethod = Main.inputMethod;
        if (!inputMethod?.currentFocus)
            return null;
        const [text, cursor, anchor] = inputMethod.getSurroundingText();
        // `_purpose`/`_hints` are the shell's own IBus translations of the field's content type.
        const sensitive = SENSITIVE_PURPOSES.includes(inputMethod._purpose) ||
            (inputMethod._hints & SENSITIVE_HINTS) !== 0;
        return {focused: true, sensitive, text, cursor, anchor};
    }

    replace({deleteBefore, text}) {
        const inputMethod = Main.inputMethod;
        if (deleteBefore > 0)
            inputMethod.delete_surrounding(-deleteBefore, deleteBefore);
        inputMethod.commit(text);
    }
}
