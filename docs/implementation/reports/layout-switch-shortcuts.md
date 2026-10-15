# Configurable layout switching

The Settings shortcut row now selects Shift, Alt (Option)+Shift, Ctrl+Shift or Disabled. The compact menu uses a selected checkmark and key symbols, follows the existing light/dark theme, and stacks at narrow widths or large text sizes. Double Shift remains the manual conversion command independently of this choice.

The Core gesture recognizer emits a layout switch once after all participating keys are released. Both press/release orders and left/right variants are supported. Ordinary typing, extra modifiers, foreign events, focus changes and unobserved initially held modifiers cancel the gesture. Option manual correction and split Shift retain their own behavior without an additional action on a completed layout chord.

Preferences store a domain enum. Legacy stored singleShiftEnabled=true/false migrates to singleShift/disabled; encoding retains a consistent legacy boolean. Native bridge snapshots project the choice to three mutually exclusive flags. Atomic patches reject conflicting true values; legacy single-flag commands remain supported. Other preference changes, including toggling auto mode, preserve the choice. Flutter renders only the confirmed native snapshot.

Validation: 73 Core + 232 Mac = 305 Swift tests passed; 61 Flutter tests passed; flutter analyze found no issues. RED/GREEN covered migration, chord combinations/cancellation, bridge persistence, runtime wiring, atomic UI patches and narrow Russian large-text layout. Independent code review found no blocking defect. Universal Release build (61.2 MB) passed deep/strict signature verification.

Live GUI review confirmed the dark settings row/menu, successful Alt+Shift selection and persistence after quitting/relaunching. Original Shift selection was restored after this check. Physical hardware chord behavior is covered by event-driven tests but still awaits user verification; no hardware-input claim is made from GUI automation.

## Command + Shift

Added the fifth selector option Command + Shift (⌘ ⇧), with left/right Command key codes 55/54. The same final-release and cancellation rules apply; Cmd+Shift+V and other chords involving another key do not switch layouts. Older Flutter snapshots missing commandShiftEnabled migrate to false, while native Codable keeps the enum and legacy projection consistent.

Expanded the existing gesture matrix, wrong-choice/cancellation cases, native persistence and runtime publication tests to cover Command. RED reproduced rejection of the new bridge flag and missing chord actions. GREEN: all 305 Swift tests passed; all 62 Flutter tests passed; flutter analyze clean. Physical hardware verification remains separate.
