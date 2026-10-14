# Native input runtime implementation

Implemented platform-independent edit/selection ports in Core/Ports/Editing.swift, qualified AX value/range replacement with revalidation and readback, suffix proof, one-entry undo, manual selected-text layout transform, direct AX plain-text insertion preserving all clipboard representations, default-deny capability evidence, dedicated event-tap run loop, random self-event marker, bounded timeout reenable, monotonic gesture timer, and immutable rule snapshot installation under the runtime lock.

Composition API: NativeInputController(profiles:layouts:permissions:preferences:snapshot:corpusQualified:). Defaults deny editor support and production corpus qualification. start/stop, updatePreferences, install, updateWordPolicies, updateAppPolicies, invalidateContext, manualCorrection, plainPaste(clipboard:), undoLast. onResult reports only ApplyResult; onToggleAuto requests persistence by the composition root. RuntimeCommand carries native data only and never belongs in a channel payload.

RED evidence: ReplacementTests, RuntimeReplayTests, SelectionTests, NativeInputControllerTests compiled against missing production types and failed. GREEN: all four targeted suites pass; swift test passes Core and Mac suites. RuntimeReplayTests covers 100000 physical/repeat/self-tag events with exact one-pass dispositions using production InputRuntime. No permissions requested, clipboard read, user typing injected, or personal stores modified by these tests.

## Explicit remaining gates

This is a conservative functional slice, not B3–B6 acceptance. The tap is listen-only: all physical events pass and there is no applying queue or suppression. At most one deferred command is scheduled; any later non-up event cancels it before delivery. Continuous typing therefore aborts pending boundary correction instead of holding keys. Early-within-word correction is not implemented. A7 production corpus is unqualified, so the facade disables auto by default. No editor/control is declared compatible.

CmdShiftV interception is BLOCKED. A qualified explicit plainPaste call works through AX with clipboard unchanged. The keyboard chord currently passes through and does not invoke our plainPaste. Safely suppressing it requires a prepared immutable AX selection/paste generation published outside callback, executor acceptance before suppression, paired release ownership, bounded tagged original-chord replay only before first mutation, and uncertain-stop after possible mutation. Existing ContextAccess alone does not prove those conditions. No claim is made that this meets B5 hotkey acceptance.

Clipboard Copy fallback is unsupported; AX selected range is the only implemented selection strategy. KeySender uses qualified AX value/range instead of guessed Backspace/Unicode events. AX full value rewrite requires host qualification because editors can alter semantics and undo grouping.

Host matrix, real TCC/Secure Input, external editor, partial physical injection failure, actual keyboard/layout, p99/idle CPU/RSS, macOS12, Intel/Apple Silicon release checks: UNRUN. ReplayRunner target must be added by root Package.swift owner; its file checks exact ordered pass-through and rejects <100000 events. Its scenarios JSON is a declaration, not host evidence.

RuleSnapshotConsumer temporary declaration is Core/Ports/Editing.swift (single-line public protocol); root should remove it when integrating delivery owner's canonical Core/Delivery definition. install is synchronous: immutable swap and pending buffer invalidation happen before return.
