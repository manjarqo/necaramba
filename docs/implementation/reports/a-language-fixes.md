# A3/A4 language safety follow-up

Date: 2026-10-14. Scope: `WordBuffer`, `TokenGuard`, `RuleIndex`, `LinguisticEngine`, and focused Core tests. The recorded-style physical fixtures in the tests are synthetic; no host editor, installed Caramba, user TCC, or personal data was accessed.

## Changes

- `typoEnabled == false` now suppresses both exact typo replacement and double-capital correction, matching the shared typo control. The existing `autoEnabled` gate remains first.
- The word buffer retains a bounded set of single-grapheme source punctuation keys that can be Russian letters in a different layout. It still invalidates on other unknown input and preserves its existing `!`/`?` punctuation-run guard.
- Punctuation-bearing text can become a layout candidate only when exactly one supported source mark appears among ASCII letters, the recorded physical events reconstruct the visible text exactly, an explicit physical mapping covers every key, and the mapped result is a known, unprotected letters-only word. Explicit never-switch tokens and user word exclusions still win. Selection and token-only paths cannot bypass these conditions.
- Dots are deliberately excluded from this conversion path because a single embedded dot can be a hostname or code member access. Multiple punctuation marks, mixed scripts, unsupported mapping, and uncertain provenance abstain. This leaves some calibration misses unresolved by design.

## RED/GREEN evidence

- RED: `testDisablingTypoAlsoDisablesDoubleCaps` replaced `HEllo` with `Hello` with typo disabled.
- RED: `testRecordedStylePhysicalPunctuationLayoutWords` could not buffer `vj;yj` and therefore could not produce a correction.
- RED: `testPhysicalPunctuationRequiresSingleSafeSourceMarkAndExactEventText` showed a never-switch token `vj;yj` being replaced after the new physical path was introduced; the explicit protected-token check fixed it.
- GREEN: `swift test --filter LinguisticEngineTests` passed 14 tests; `swift test` passed 62 Core tests and the other package test targets. `git diff --check` passed. These are Swift package results, not device/editor differential results.

The synthetic physical cases prove `vj;yj ` → `можно `, `ktc[jp ` → `лесхоз `, and `,tvjkm ` → `бемоль ` with supplied key maps. Safety cases keep dot syntax, punctuation runs, missing event provenance, and explicit never-switch tokens unchanged. Existing stream tests continue to keep URL, email, path, and punctuation-prefix syntax unchanged.

## Calibration and remaining gates

`swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split calibration --output /tmp/necaramba-language-calibration.json` produced the existing token-only result: 8,400 cases, TP 3,164, FP 0, FN 436, layout recall 0.8183. The runner reports a failed gate (layout recall, zero typo/ё families, and unrun physical differential). Token-only rows have no physical events, so this run neither measures nor activates the new physical punctuation path. Rules, corpus, and their SHA-256 values were left unchanged.

Early correction within a word remains deferred under spec §5: the current reviewed calibration contains no prefix-confidence evidence or transactional editor tests from which to prove an unambiguous early decision. No confidence threshold was invented. Broad typo/ё quality and release readiness likewise remain blocked on independent corpus coverage and physical/editor differential evidence.
