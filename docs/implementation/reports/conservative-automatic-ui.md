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
