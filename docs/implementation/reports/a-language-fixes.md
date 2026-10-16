# A3/A4 language safety follow-up

Date: 2026-10-14. Scope: `WordBuffer`, `TokenGuard`, `RuleIndex`, `LinguisticEngine`, and focused Core tests. The recorded-style physical fixtures in the tests are synthetic; no host editor, other installed keyboard switcher, user TCC, or personal data was accessed.

## Changes

- `typoEnabled == false` now suppresses both exact typo replacement and double-capital correction, matching the shared typo control. The existing `autoEnabled` gate remains first.
- The word buffer retains a bounded set of single-grapheme source punctuation keys that can be Russian letters in a different layout. It still invalidates on other unknown input and preserves its existing `!`/`?` punctuation-run guard.
- Only one narrow punctuation shape can become a layout candidate: a leading comma followed by at least two ASCII letters. The recorded physical events must reconstruct the visible text exactly, an explicit physical mapping must cover every key, and the mapped result must be a known, unprotected letters-only word. Explicit never-switch tokens and user word exclusions still win. Selection and token-only paths cannot bypass these conditions.
- Embedded and trailing punctuation, including semicolons, brackets, and dots, abstains even if physical mapping yields a known word. Those source forms can also be code, paths, hostnames, or ordinary punctuation; key provenance alone cannot distinguish intent. Multiple punctuation marks, mixed scripts, unsupported mapping, and uncertain provenance also abstain. The leading-comma allowance is a constrained heuristic, not proof that every such source is prose; release use still requires physical/editor differential validation.

## RED/GREEN evidence

- RED: `testDisablingTypoAlsoDisablesDoubleCaps` replaced `HEllo` with `Hello` with typo disabled.
- RED: `testRecordedStylePhysicalPunctuationLayoutWords` could not buffer `vj;yj` and therefore could not produce a correction.
- RED: `testPhysicalPunctuationRequiresSingleSafeSourceMarkAndExactEventText` showed a never-switch token `vj;yj` being replaced after the new physical path was introduced; the explicit protected-token check fixed it.
- RED (review round 1): `testRecordedStylePhysicalPunctuationAbstainsWhenSourceCouldBeCode` showed `vj;yj` → `можно` and `ktc[jp` → `лесхоз` even though the raw source could be code-like syntax.
- GREEN: `swift test --filter 'LinguisticEngineTests|WordBufferTests'` passed 23 tests after narrowing the source shape; `swift test` passed 62 Core tests and the other package targets. `git diff --check` passed. These are Swift package results, not device/editor differential results.

The synthetic physical case proves `,tvjkm ` → `бемоль ` with a supplied key map. The `vj;yj` and `ktc[jp` pairs came from independent ReviewV3 calibration mismatch families and now abstain despite mapping to known Russian words. Safety cases keep dot syntax, punctuation runs, missing event provenance, and explicit never-switch tokens unchanged. Existing stream tests continue to keep URL, email, path, and punctuation-prefix syntax unchanged.

## Calibration and remaining gates

`swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split calibration --output /tmp/necaramba-language-calibration-round1.json` produced the existing token-only result: 8,400 cases, TP 3,164, FP 0, FN 436, layout recall 0.8183. The runner reports a failed gate (layout recall, zero typo/ё families, and unrun physical differential). Token-only rows have no physical events, so this run neither measures nor activates the new physical punctuation path. Rules, corpus, and their SHA-256 values were left unchanged.

Early correction within a word remains deferred under spec §5: the current reviewed calibration contains no prefix-confidence evidence or transactional editor tests from which to prove an unambiguous early decision. No confidence threshold was invented. Broad typo/ё quality and release readiness likewise remain blocked on independent corpus coverage and physical/editor differential evidence.
