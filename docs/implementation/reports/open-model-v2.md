# Open Model 2 — implementation and qualification

Date: 2026-10-15. Local implementation; no public release or universal parity claim.

## Outcome

Three parallel work streams delivered independent vocabulary/rules, compact native integration, and engine/evaluation. The open model contains 77,892 English and 1,419,808 Russian forms, 233 explicit typo corrections and 67 optional preferred ё spellings. Proprietary data were not construction inputs. A separately supplied local reference was used only after model construction for aggregate evaluation.

Pinned LibreOffice dictionary sources, original notices, selection changes and hashes are recorded in `Resources/OpenModel/provenance.json`. Conservative filtering removed 242 unsupported ё-derived forms from legacy affix expansion. Proper names, single-letter entries, compounds and hyphenated/apostrophe forms are outside this selection. Counts describe forms, not distinct lemmas or measured frequencies.

## Architecture and behavior

`OpenWordLookup`, `OpenCorrectionRules` and `OpenCorrectionEngine` belong to the domain layer. `PackedOpenLexicon` uses UTF-8 tables and UInt32 offsets with binary search, avoiding a second 1.5-million-object rule snapshot. `OpenModelLoader` verifies the manifest, payload sizes, hashes and version, rejects symlinks and enforces the combined 64 MiB budget before reading payloads. Native loading runs off the input thread; installation publishes on the main thread and invalidates stale input context.

Known words are preserved. Unknown or competing interpretations abstain unless explicit independent correction rules provide sufficient evidence. Layout-plus-typo correction, case handling, optional ё normalization, protected tokens and intermediate/final exclusions are covered. Punctuation-bearing layout candidates require matching physical-input evidence; URLs, numeric tokens and code-like sequences remain protected. Existing focus, security and replacement safeguards remain in place.

Explicit local model > opt-in open model > existing public fallback is the installation precedence. Build with `NECARAMBA_OPEN_MODEL=YES` and unset `NECARAMBA_LOCAL_PATTERN_MODEL`. Ordinary builds retain the existing baseline pending editor qualification.

## Frozen evaluation

The actual engines were run against an unchanged frozen corpus using simulated physical provenance. The comparison is with our local interpreter of the supplied reference, **not the original Caramba application**. Reference per-token answers and rules are not exported. No tuning was performed against the final holdout.

| Measure | Open model | Local reference interpreter |
|---|---:|---:|
| Calibration: layout recall, 6,002 total cases | 99.375% | 81.167% |
| Calibration: incorrect positive decisions | 0 | 57 |
| Holdout: layout recall, 6,006 total cases | 99.125% | 80.909% |
| Holdout: incorrect positive decisions | 0 | 58 |

Holdout open counts: 2,383 true positives, 21 missed corrections, 3,602 true negatives, zero false positives. All 29 independent regression scenarios and all 300 own-rule consistency checks passed. The latter check proves rule execution, not independent generalization. Machine-readable reports are `Resources/OpenModel/evaluation-v2-{calibration,holdout}.json`; the older `evaluation.json` documents the earlier lexical-only prototype.

Release-mode holdout runner initialization took approximately 105 ms and open evaluation 143 ms on this machine. These are runner measurements, not keyboard-to-editor latency. Compact storage including offsets is approximately 39.45 MB. The separate application performance audit remains a proposal, not an implemented optimization claim.

## Verification

- Full Swift suite: 142 core tests and 277 macOS tests, no failures; one optional private-model test skipped.
- Open-model Python suite: 20 tests passed. Packaging tests and two v2 CLI smoke tests passed.
- Universal Flutter release build completed; `lipo` reports arm64 and x86_64. Strict deep codesign verification passed.
- Bundle manifest/payload hashes verified, all three license files present, no `LocalPatternModel.json` bundled.
- Local app launched and shows active status. Additional typo/ё controls are enabled, which requires successful model installation; the bundle contains only the open model. Preferences were not changed during inspection.
- `git diff --check` passed.

Local open application: `App/build/macos/Build/Products/Release/Necaramba.app`. Previous private application preserved at ignored `build/LocalPrivate/Necaramba.app`.

## Remaining qualification

The reports deliberately retain `releaseReady: false`. Synthetic corpus checks do not certify physical keyboard capture, repeated replacement, selection, Spotlight, Safari, Chrome, Zen, Spark or Orca. Those require live editor qualification. The model also has no frequency/context scorer and its explicit typo inventory is not a claim of exhaustive typo coverage. Evidence supports substantially better layout recall on the frozen sample; complete behavioral equivalence to a proprietary application has not been established.

The public model archive includes only independent data, generators, provenance and licenses. No private model, extracted proprietary rules or private typing logs belong in that archive or a public release.
