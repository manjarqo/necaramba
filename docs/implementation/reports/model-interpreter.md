# Independent pattern-model interpreter

2026-10-15. This implements reusable Swift domain components and a local research runner. An explicitly selected local build can use these components for automatic word decisions. This does not qualify a production model or establish complete Caramba runtime parity.

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

The complete locally extracted model and neutral JSON are under ignored `docs/research/caramba/evidence/model-followup/`. The user selected a local experimental build using this data. The existing public application continues to use its independently sourced rule package; no third-party model is embedded in releases.

The local build explicitly opts in through `NECARAMBA_LOCAL_PATTERN_MODEL`, loads and compiles the model off the main thread, and enables typo/ё controls after successful installation. Model files remain ignored and are not committed. Ordinary builds omit this resource; the public artifact verifier rejects it. The native automatic path retains its physical Space boundary, field identity, focus, generation and exact-text checks. Publication of original model data is not authorized by the existing GPL license of this repository.

When both language candidates have zero scores, the local integration may apply an exact autocorrect rule to the verified current-layout word without switching layout. Explicit rejection and unsupported classification still abstain. This is a deliberate local integration policy, not a claim about the original selector ordering.

## Local application build

From the repository root, with the locally extracted file already present:

```sh
cd App
NECARAMBA_LOCAL_PATTERN_MODEL="$PWD/../docs/research/caramba/evidence/model-followup/model-neutral.json" \
  flutter build macos --release --build-name=1.0.0 --build-number=2
```

This is an opt-in development build, despite Flutter's optimized `--release` mode. Its resource is `Contents/Resources/LocalPatternModel.json`. The public release verification intentionally rejects it. Check the startup log for `Necaramba local pattern model installed` before treating the model as active. The build uses the local signing configuration; it is not a notarized public release.

## Reproduction

See [runner usage](../../../Tools/ModelReplayRunner/README.md). Commands consume local data and never run Caramba, access its license state, contact its servers, or type into a live editor. A successful static replay is evidence for the independent implementation and supplied artifact only; physical behavior comparisons remain separate.

## Verification performed

- Full Swift suite: **244 Mac + 111 Core tests**, zero failures. New components have RED-before-GREEN evidence for matching, preprocessing, byte splices, case projection, category toggles and resource limits.
- Research runner: **6 isolated CLI tests**, zero failures, using only synthetic temporary JSON data.
- Full local reference model: **165913 classifier patterns compiled**; **72595 / 72595 autocorrect splices valid**, zero rejected; complete autocorrect rules compiled, including two rules producing literal TAB. Other ASCII control replacements remain rejected. Literal TAB in this pure text interpreter does not authorize keyboard event dispatch.
- Explicit offline probes produced `teh ` → `the `, `првиет ` → `привет ` and `елка ` → `ёлка `, retaining their trailing spaces. The original executable was not run; these are independent interpreter results using the extracted local data, not differential runtime tests.
- Independent static review found no blocking RU/EN discrepancy in the implemented contracts. Intentional resource and Unicode-version limits remain documented above.

## Local integration verification (2026-10-15)

- Final Swift suite: 255 Mac + 122 Core tests, zero failures; one optional external-model test skipped in the default run and separately executed successfully with the explicit local path (6/6 loader tests).
- Flutter: 65 tests passed; analyzer reported no issues. Local packaging: 4 tests passed.
- Full-model engine probes: `ghbdtn → привет`, `lf → да`, `teh → the`, `првиет → привет`, `елка → ёлка`; typo/ё toggles suppress those respective changes. These are offline probes, not live-editor tests.
- Local model version `26.09.22.01`, neutral JSON SHA-256 `f2c27a82dce1eb85ef03947df61fb1b057bc81707a005e8af56432944b2bd33d`. The embedded resource matched this digest.
- Optimized universal application built; strict deep code-signature verification passed. Settings showed automatic correction active and both additional-correction toggles available after restart.
- Physical auto-correction in Spark still needs a user keyboard check; synthetic probes and successful model loading do not prove that editor's event delivery.

## Follow-up: punctuation in wrong-layout Russian words

The reported `nj;t` and `gthtrk.xbkjcm` are not missing vocabulary. Offline model replay classifies `тоже` and `переключилось` as known, and their English-key spellings as scored −5 and −12 respectively. The local integration's initial source-token protection rejected the semicolon and period before invoking this classifier. This is separate from layout update timing or model coverage.

The separate manual version case `1ю3ю166 → 1.3.166` loses capture because `InputRuntime`'s manual `tracked` buffer accepts letters/layout punctuation but clears on digits. This must be fixed in manual tracking, without enabling automatic corrections for numeric tokens or broadening the automatic `WordBuffer`.

The fix admits English-key punctuation only with caller-confirmed physical translations, a known Russian alternative and a negative English classifier score. Numeric tokens, paths, protocol/email markers, multiple dots and common domain suffixes remain blocked. This is not a universal domain detector: other single-dot tokens still depend on the classifier and user exclusions. `TokenGuard` and AX replacement checks are unchanged. A full-model offline probe confirmed both reported replacements after the fix.

Manual tracking now includes ASCII digits. Regression tests cover `1ю3ю166 ↔ 1.3.166`, repeated reversals, trailing spaces and physical translation when tap Unicode is stale. The automatic word buffer's numeric-token exclusion remains tested.

Follow-up verification: 259 Mac tests (one optional local-model skip) and 125 Core tests, zero failures on the unchanged-source retry. The first full run stalled in XCTest invocation near the existing archive tests; a process sample was retained and that test process alone was stopped. Targeted tests had passed before the retry. Local optimized build and deep strict code-signature verification passed; the application was restarted. Physical typing of these new cases still requires user confirmation.
