# Independent open-model comparison

From the repository root:

```sh
swift build --product OpenModelV2Runner
python3 Tools/OpenModelV2Runner/test_runner.py
.build/debug/OpenModelV2Runner --directory Resources/OpenModel --output /tmp/open-v2-calibration.json
```

The directory is loaded by the production `OpenModelLoader`: manifest hashes,
resource bounds, packed RU/EN lexicons and exact correction rules are validated.
The frozen `Corpora/manifest.json` is fully validated including hashes, licenses and
split separation. Only the requested split is evaluated: `--split calibration`
(default) or `--split holdout`. Use holdout once the implementation is frozen;
do not tune against it.

Evaluation uses the real `OpenCorrectionEngine`, all correction preferences enabled,
and exact visible-character events with physical provenance **simulated in memory**.
Candidate strings use the baseline character mapping plus explicit US shifted
punctuation pairs with case preservation. This
is not native keyboard-table capture, user input, Accessibility or browser testing.
No events are posted. The independent fixed regressions include user-reported words,
punctuation, short words, exact typos, title/double capitals, valid е/ё spellings,
URLs, versions and ambiguity. Numeric cases assert automatic abstention; manual
version conversion requires separate runtime/editor tests.

Optional local comparison:

```sh
.build/debug/OpenModelV2Runner --directory Resources/OpenModel --output /tmp/comparison.json --reference /absolute/path/to/local-model.json
```

The reference model is only loaded through the existing local loader and queried on
the same frozen rows. Its predictions are used to compute aggregate counts/metrics;
**reference-derived words, mismatch lists, per-token outputs, data and local paths
are never serialized**. No reference data is added to the open lexicon or rules.
Do not use reference predictions as training labels. CLI smoke tests use an original
synthetic reference and need no proprietary model.

Reports include open-model mismatches for diagnosis, split and manifest identifiers,
real measured initialization/evaluation durations, and throughput. Timings depend on
build mode and local conditions, and include fixture construction and metric work.
They are not input-tap latency measurements. `releaseReady` always remains false and
hardware/editor qualification is `UNRUN`. Exit zero only means the report was written;
inspect quality metrics and regressions. Invalid inputs/I/O fail with exit two.

The rule consistency audit runs every declared open typo/ё rule through the real
engine and reports policy interference. It is not independent or held-out quality
evidence.
