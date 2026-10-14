# Conservative automatic layout correction and settings redesign

Date: 2026-10-14. User confirmed repeated manual toggles work and requested working automatic layout correction plus a modern premium interface.

## Scope

The local application enables a separate conservative automatic mode when the user's automatic-correction preference is on. This is an explicit change to the former prototype behavior that blocked all automatic correction behind broad release qualification. It does not mark the historical corpus, editor profiles or distribution release gate as passed. Existing historical reports remain intact.

Only an ordinary physically typed space ends a candidate. Corrections require a known unambiguous target word, an unknown source word of at least three characters, actual captured keyboard mappings, current permissions, a supported nonsecure field, unchanged context and the boundary's captured input generation. Correct words, ambiguous words, exclusions, denied applications and protected code/URL-like tokens are preserved. Enter/Tab and early in-word changes are outside this mode. A new event cancels deferred work rather than deleting text typed afterward.

The installed signed dictionary remains unchanged. A small independently authored conversational supplement supplies short function words and common forms missing from the base-word selection. This supplement is a local vocabulary extension, not frequency calibration or broad linguistic qualification. Typos and ё restoration are not enabled by this layout-only mode; settings must show their current availability honestly.

Readable AX controls require exact original suffix and exact post-edit proof. Empty input proxies such as Orca use physical lineage and a fresh bounded field/context/generation check; a complete send is reported as `dispatched`, never a verified commit. Partial/uncertain mutations are not retried. Secure Input, password fields, active composition and unprovable focus remain excluded.

## Interface direction

System light/dark appearance, compact neutral toolbar, restrained blue accent, system typography, compact sidebar, grouped settings rows and consistent focus states. Color/image personalization remains available. The actual automatic state distinguishes active, user-disabled, initializing, unavailable and permission/secure-input conditions. No keyboard text crosses the native/Flutter boundary.

## Evidence

Investigation reproduced default `corpusQualified=false`, empty editor profiles, missing actual ABC/Russian alias resolution, raw-event Unicode mismatch and strict AX requirements as independent blockers. The historical v3 corpus rerun still reports 8,459 cases, TP 3,147, FP 0, FN 493 and layout recall 80.8688%; it is not a measurement of the new conservative physical pipeline or a passed release gate.

Integrated validation: 179 Mac + 65 Core = 244 Swift tests passed; Flutter analyze reports no issues and all 54 Flutter tests passed. RED/GREEN tests cover status initialization/unavailability, live event-tap state, retained-model readiness after update failure, vocabulary protection, both correction directions, stale event Unicode, cancellation on new input, exclusions, app policy, protected token prefixes, physical-space proof, readable/proxy mutation and manual reversal. Review caught and fixed unsafe prefix resets, mixed table/engine publication, and treating letters appended after manual replacement as a new word.

A temporary read-only host test captured installed ABC/Russian tables and loaded the full local dictionary plus supplement. It verified `ghbdtn` → `привет`, `rfr` → `как`, `ltkf` → `дела`, `xtv` → `чем`, `руддщ` → `hello` and preservation of correct/protected tokens. On 7,200 calibration examples evaluated with synthetic key events built from those installed tables, 1,991/2,400 layout corrections matched and there were zero changes on 4,800 no-change examples. This is not a physical-key/editor qualification or a passed broad release gate. The environment-specific temporary test was removed after recording evidence.

After unknown input, paste or navigation, automatic tracking waits for a physical space before trusting a new word. This is particularly relevant to opaque terminal input proxies, where the existing document text cannot be proved. Initial and completed-space scenarios are tested separately. A manual conversion without a trailing space does not create an automatic word boundary.

Light/dark Flutter previews were visually reviewed. Universal x86_64/arm64 Release (60.9 MB) built successfully and passed deep/strict codesign verification with the unchanged certificate requirement. The app launched without permission onboarding, changed from initializing to active after dictionary installation, and its narrow and wide live-window layouts were visually inspected. Physical automatic correction in Orca remains pending user verification.

## First word without a leading space

Regression tests reproduced dropped first words after Return and focus invalidation. Return now establishes a physical boundary for the next token without correcting the submitted word. An untrusted token can reach the automatic adapter with an explicit word-start-proof requirement, preserved when remapping captured key events. Readable AX fields must prove field start or preceding whitespace; the full observed value is pinned through destructive preflight. Opaque fields cannot satisfy this proof and still require a known physical boundary. Paste/navigation and appended manual-conversion suffix protection remain intact.

Validation: 225 Mac + 65 Core = 290 Swift tests passed. Added first-word, opaque-prefix, embedded URL/email, Unicode whitespace, and changed-prefix-before-dispatch coverage. Actual physical input in Orca remains a user verification step; no claim is made that opaque focus-only resets can establish an empty field.


## Orca opaque first-word follow-up

Physical user verification showed the first-word fix still failed in Orca while Chrome succeeded. Runtime logs showed a layout correction decision followed by `auto.result code=0` after successful AX reads of the empty proxy; the next word reached `ax.auto.emptyProxy` and `auto.result code=3`. Thus first-word start-proof rejection, rather than vocabulary or permission failure, was confirmed.

Runtime now distinguishes unknown prefix history after an empty capture reset from a known interrupted token, paste, edited suffix or foreign input. A fresh uninterrupted physical token may explicitly use the opaque fallback. Readable fields still require start/whitespace proof. A paste or interrupted token remains blocked across subsequent invalidations within the same field until a physical boundary. A new PID/bundle/focus epoch starts a fresh capture; layout changes alone do not. Opaque output remains `dispatched`, never verified, counted or retried. This is a deliberate compatibility tradeoff: unseen pre-existing text before a freshly captured token cannot be checked in an opaque terminal proxy.

RED: new empty-capture-reset and adapter dispatch tests failed with aborted/unchanged text. GREEN: 228 Mac + 65 Core = 293 tests passed, including preservation of pasted URL prefixes across mouse reset and readable embedded-suffix rejection even with opaque permission. Real physical Orca verification remains pending after the updated build.

Review found the previous field’s Cmd+Tab block surviving an actual focus change. A regression test reproduced it; tracking the capture context now prevents that carryover. Final validation: 229 Mac + 65 Core = 294 Swift tests passed.

A second review caught known-prefix context not being recorded by intercepted plain paste and retained manual results. Both paths were reproduced RED and corrected; replay/discard and unsafe-event paths also retain their known context. Final suite after these changes: 230 Mac + 65 Core = 295 tests, zero failures.
