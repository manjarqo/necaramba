# Independent open lexical model — 2026-10-15

User approved building independently sourced public data. Delivered candidate model `Resources/OpenModel/open-v1.json`, provenance, complete upstream notices, deterministic Python generator, bounded pure Swift decoder and a real-engine evaluation CLI. No extracted proprietary model, proprietary rule outputs, personal typing logs, or holdout predictions were generator inputs. Existing app packaging, active local model and signed-rule limits remain unchanged.

The source revision and hashes are pinned in `Resources/OpenModel/provenance.json`. The artifact contains 77,892 English and 1,420,050 Russian lowercase forms, 36,456,028 bytes, SHA256 `ad3639106cfc43a1c0ff5522f3ae93f32d2bf8bfdfc28df29c020a28c936a1b9`. Membership is not frequency; there is no statistical training or new typo/ё model.

## Evidence

- Python generator: seven tests pass; two generation runs identical.
- Core: 130 tests pass, including five new model validation tests. RED missing-type evidence was recorded before implementation.
- CLI: two smoke tests pass; missing-binary RED recorded before implementation.
- Real-engine calibration: 6,002 examples; baseline and open model both TP 1,966, FP 0, FN 436, overall recall 81.848%, layout recall 81.833%. No observed benchmark improvement. Frozen manifests, labels and existing baseline were not regenerated.
- Independent development regressions: 15/18. `nj;t` and `gthtrk.xbkjcm` abstain due to existing punctuation protection. `ру` changes to `he`, a development false positive. Numeric automatic abstention is tested; manual double-Shift is not tested by this CLI.
- Debug evaluation process took 11.46 seconds and peaked at 495,976,448 bytes RSS on this machine. This includes JSON decoding, snapshots and multiple evaluation engines, not a measurement of steady-state application memory.
- Standalone data archive `build/OpenModel/necaramba-open-model-1.tar.gz`: 5,321,144 bytes, SHA256 `216968c60dffd95f7f8a9bca32e851b1a76141249206f0621825dc2f58b980f8`. Explicit allowlist includes only model data, notices, pinned dictionary/affix inputs, generator/tests and repository GPL license. Extracted into a temporary directory, rebuilt offline to identical model hash, all seven tests pass.
- `git diff --check` clean. No commit, push, GitHub release or active app replacement performed.

## Interpretation

The data package can be distributed with its included notices as an experimental open lexical candidate. It is not a complete production replacement for the local model. Full expansion exceeds the existing signed-payload 500,000-entry limit; that limit has not been relaxed. A future application integration must measure a compact representation, address short-token and punctuation ambiguity with dedicated tests, and qualify real editor behavior. Do not infer production reliability from dictionary size or zero false positives in one synthetic split.
