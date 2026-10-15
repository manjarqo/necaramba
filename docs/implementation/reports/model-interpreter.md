# Independent pattern-model interpreter

2026-10-15. This implements reusable Swift domain components and a local research runner. It does **not** replace Necaramba's running `LinguisticEngine`, qualify a production model, or establish complete Caramba runtime parity.

## Implemented contracts

- `PatternClassifier`: compiled UTF-8 trie, all overlapping terminal-prefix occurrences, separate insensitive/original case passes, language-pair filtering, signed weights and zero-weight known/rejected assertions. `classify` exposes explicit framing; `classifyToken` adds the documented Unicode trim, boundary and empty-feature fallback rules.
- `PatternRewriteRule`: bounded retained UTF-8 byte prefix + insertion + byte suffix, with exact UTF-8 validation. Counts are not Unicode scalar counts or UTF-16 ranges.
- `PatternAutocorrector`: compiled rules, fixed original match list, source/lowercase matching, specific autocorrect fallback, byte rewrite, exact or Unicode scalar case-aware global nonoverlapping substitution, dynamic ё categorization and independent typo/ё switches.
- `ModelReplayRunner`: explicitly loads a local neutral JSON model, resolves references, evaluates sample strings and optionally validates every declared autocorrect splice. No original resources, keys or model are included in the executable or repository.

The implementations use independently authored Swift code and synthetic tests. Retained REA pseudocode/disassembly established behavior; it was not copied into these components. The data extraction and rule counts are documented in [model findings](../../research/caramba/model-followup-2026-10-15.md); exact conditions and remaining gaps in [behavior findings](../../research/caramba/behavior-followup-2026-10-15.md).

## Deliberate limits

Swift Unicode tables may differ from the original Rust tables. Invalid inputs, excessive work and integer overflow return unsupported rather than using machine wraparound. The core operates on strings and grants no authority to dispatch keyboard events. The native event/AX focus, generation, exact-text, IME, secure-field and delimiter checks remain separate and unchanged.

A classification result is not a layout selection policy. App-specific rules, collision suppression, event delivery, undo, early correction and full main-state-machine wiring are not reproduced by these primitives. Decoded Appex records are not proven to be one app profile each. No claim of complete 1:1 behavior or corpus qualification is made.

## Data and integration

The complete locally extracted model and neutral JSON are under ignored `docs/research/caramba/evidence/model-followup/`. They are research inputs only. The existing public application continues to use its independently sourced rule package; no third-party model is embedded in releases.

The user has been asked to choose between a public version using independently licensed data and a local experimental integration using the extracted reference data. That choice is pending. The generic interpreter is useful for either approach; publication of original model data is not authorized by the existing GPL license of this repository.

## Reproduction

See [runner usage](../../../Tools/ModelReplayRunner/README.md). Commands consume local data and never run Caramba, access its license state, contact its servers, or type into a live editor. A successful static replay is evidence for the independent implementation and supplied artifact only; physical behavior comparisons remain separate.

## Verification performed

- Full Swift suite: **244 Mac + 111 Core tests**, zero failures. New components have RED-before-GREEN evidence for matching, preprocessing, byte splices, case projection, category toggles and resource limits.
- Research runner: **6 isolated CLI tests**, zero failures, using only synthetic temporary JSON data.
- Full local reference model: **165913 classifier patterns compiled**; **72595 / 72595 autocorrect splices valid**, zero rejected; complete autocorrect rules compiled, including two rules producing literal TAB. Other ASCII control replacements remain rejected. Literal TAB in this pure text interpreter does not authorize keyboard event dispatch.
- Explicit offline probes produced `teh ` → `the `, `првиет ` → `привет ` and `елка ` → `ёлка `, retaining their trailing spaces. The original executable was not run; these are independent interpreter results using the extracted local data, not differential runtime tests.
- Independent static review found no blocking RU/EN discrepancy in the implemented contracts. Intentional resource and Unicode-version limits remain documented above.
