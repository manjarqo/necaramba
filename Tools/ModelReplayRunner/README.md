# Offline model replay

An independently written Swift research runner for an explicitly supplied local neutral model export. It does not bundle third-party dictionaries, executable code, keys or a model downloader. It is a separate SwiftPM command-line target, not part of the macOS app's input loop or packaged resources.

```sh
swift run ModelReplayRunner --model /absolute/path/model-neutral.json --pair ru-en --text ghbdtn --text привет
swift run ModelReplayRunner --model /absolute/path/model-neutral.json --pair ru-en --token --text 'ghbdtn '
swift run ModelReplayRunner --model /absolute/path/model-neutral.json --pair ru-en --validate-autocorrect --autocorrect --text example
```

Default framing treats supplied text as a complete word without trimming; `--incomplete` omits the final boundary anchor. `--token` uses the documented whitespace, boundary and fallback processing. Pair orientation is resolved against the supplied language table. Output is JSON; invalid arguments, unresolved model references and decoding errors exit 2 without partial JSON output. Inputs are bounded to 64 MiB, 100 queried texts and the Core's compilation/evaluation budgets.

`--validate-autocorrect` validates each declared byte splice on its pattern material. `--autocorrect` executes the separate rule interpreter on the explicit query texts. Neither option writes to an application or changes the model. Scores and static corrections are not claims about execution of the original application: layout selection, app profiles, event timing, exceptions, IME and Secure Input policies are separate.

The implementation uses Swift Unicode casing and fail-closed bounds/overflow handling; it does not reproduce an original executable's integer wraparound or guarantee identical Unicode tables. All committed test fixtures are independently authored. Model-derived data stay outside the public repository. See [research findings](../../docs/research/caramba/model-followup-2026-10-15.md) and [behavior contracts](../../docs/research/caramba/behavior-followup-2026-10-15.md).

Validation:

```sh
swift build --product ModelReplayRunner
python3 Tools/ModelReplayRunner/test_runner.py
swift test --filter Pattern
```
