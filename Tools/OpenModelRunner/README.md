# Open model evaluation

Run from the repository root:

```sh
swift build --product OpenModelRunner
python3 Tools/OpenModelRunner/test_runner.py
.build/debug/OpenModelRunner --model Resources/OpenModel/open-v1.json --output /tmp/open-model-evaluation.json
```

The CLI validates the frozen `Corpora/manifest.json`, its source hashes, licenses,
rule snapshot, and corpus split separation. It runs the **real `LinguisticEngine`**
twice against the calibration split: with the frozen baseline, and with only its
lexicon replaced by the supplied `OpenLexicalModel`. The model's SHA-256 and
version are recorded. It does not score or tune against holdout (manifest integrity
validation does read every split).

A separate, independently authored regression section covers correct and wrong
layouts of `ground`, `connector`, `тоже`, `переключилось`, and `периодически`, plus
versions, URLs, email, code, acronyms, and short ambiguous tokens. These use
simulated physical events and deterministic fixture key codes derived from the
baseline mapping, **not actual keyboard hardware capture**. Punctuation safety
abstentions are reported as mismatches when the desired correction cannot be made;
the evaluator does not weaken production safety guards.

Numeric regression expectations are **automatic abstention**. Manual double-Shift
version conversion belongs to runtime/editor integration tests and is not evaluated
here. Calibration is token-only, so it cannot measure physical punctuation paths,
Accessibility, browser compatibility, or replacement reliability.

`releaseReady` is always `false`, and physical/editor evidence is `UNRUN`. Exit zero
means a valid report was written, not that quality thresholds passed. Inspect both
calibration reports, failures, and regression actual/expected values. Exit two means
invalid arguments, invalid model, failed manifest integrity, or an I/O error.

The smoke tests intentionally use a tiny original fixture model: their purpose is
CLI behavior and honest reporting, not measuring production dictionary quality.
No extracted proprietary model is read by this tool.
