# Necaramba Open Model 2

An independently sourced RU/EN lexical model and independently authored correction policy for Necaramba. No proprietary model, extracted patterns or private typing logs are construction inputs. This is a **modified selection** of the SCOWL-derived US English and Alexander I. Lebedev Russian Hunspell dictionaries distributed by LibreOffice; no upstream endorsement is implied.

## Contents

- 77,892 English and 1,419,808 Russian lowercase word forms.
- 233 explicit typo rules and 67 optional preferred ё spellings; see `CORRECTIONS.md`.
- `en.words` and `ru.words`: sorted UTF-8 tables used by the compact runtime index (about 39.45 MB including offsets).
- `open-v1.json`: intermediate lexical source, retained for reproducible generation; its historical filename is not the runtime package version.
- `corrections.json` and `manifest.json`: open-2 runtime policy and integrity metadata.
- Complete source notices, pinned upstream URLs/SHA-256, deterministic generators and evaluation reports.

These are vocabulary memberships and explicit corrections, **not measured frequencies**, a neural model, or a guarantee that every word is covered. Proper names, one-letter entries, words with apostrophes/hyphens and compounds are outside this lexical selection. Unknown words and conflicting interpretations should be left unchanged. Source-unknown typo correction and explicit ё spelling preferences have distinct policies; ambiguous words such as все/всё and осел/осёл are protected.

## Reproduce offline

From the repository root, Python 3 standard library only:

```sh
python3 Tools/OpenModel/build.py
python3 Tools/OpenModel/corrections.py
python3 Tools/OpenModel/pack.py
python3 Tools/OpenModel/manifest.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/OpenModel -p 'test_*.py'
```

`build.py --fetch` restores pinned inputs, checking SHA-256 before writing them. A normal build is offline and verifies the same hashes. Upstream revision: `67032ee957631908098a72edf48dc81cac27e369` of [LibreOffice/dictionaries](https://github.com/LibreOffice/dictionaries/tree/67032ee957631908098a72edf48dc81cac27e369). Original `.dic` and notices are in `Corpora/Sources/`; `.aff` inputs are in this directory's `Sources/`.

Expansion supports the pinned files' prefix/suffix rules and permitted cross-products, not arbitrary Hunspell directives or compound generation. Only original lowercase standalone alphabetic entries and resulting forms of 2–48 characters are admitted. No inferred frequencies are added. The ё-derived-form filter documented in `CORRECTIONS.md` removes unsupported forms produced by legacy upstream conditions. This is a conservative modification, not an exhaustive morphological correctness proof.

## Evaluation

```sh
swift run -c release OpenModelV2Runner --directory Resources/OpenModel --output /tmp/open-calibration.json
swift run -c release OpenModelV2Runner --directory Resources/OpenModel --split holdout --output /tmp/open-holdout.json
```

The runner uses the actual domain engine with synthetic physical-input fixtures and the unchanged frozen corpus. It does not automate editors or establish end-to-end keyboard reliability. Optional `--reference /absolute/local/model.json` compares a caller-supplied reference interpreter and saves only aggregate reference statistics, never its per-token answers or rules. Reference data are not redistributed or used to generate the open model. Historical `evaluation.json` belongs to the first lexical-only prototype and identifies its own older model hash; current results belong to the v2 report.

Current saved reports (`evaluation-v2-calibration.json`, `evaluation-v2-holdout.json`) record:

| Split | Cases | Open layout recall | Open false changes / unchanged cases | Reference interpreter layout recall |
| --- | ---: | ---: | ---: | ---: |
| calibration | 6002 | 2385/2400 (99.375000%) | 0/3600 | 81.166667% |
| holdout | 6006 | 2378/2399 (99.124635%) | 0/3602 | 80.908712% |

Open precision is 100% on these fixtures; 15 calibration and 21 holdout corrections were missed. All 29 separately authored development regressions and the 300-rule consistency audit pass. These finite synthetic counts do not guarantee zero mistakes in real input. The reference column evaluates a local **interpreter**, not the original Caramba application, and does not establish application-level superiority. Source corpus words overlap the external dictionary prior, so this is not an unseen-vocabulary generalization benchmark. Both reports retain `releaseReady: false`: application/physical-input and several category coverage requirements are unmet. No live browser/editor or hardware-input verification is implied. The archive supports offline model regeneration; rerunning the Swift evaluations requires the full project and corpus, which are not duplicated into the model-only archive.

## Application build

```sh
cd App
NECARAMBA_OPEN_MODEL=YES flutter build macos --release --build-name=1.0.0 --build-number=2
```

Leave `NECARAMBA_LOCAL_PATTERN_MODEL` unset to test the open model. An explicitly supplied local model has precedence. This opt-in build bundles only the compact word tables, corrections, manifest and notices; it does not create another 1.5-million-entry RuleSnapshot or weaken the existing signed update limits. Loading and verification run off the input thread. An ordinary build without this opt-in retains the previous public baseline until release qualification. This switch does not sign/notarize or publish a public release.

## Redistribution

Include **all files in `Licenses/`** with the model, including applications and source archives. SCOWL component notices and Lebedev terms remain applicable to their data. Independently authored rules and generator code are GPLv3. Do not relabel all upstream data as GPL-only. Modified versions must be identified and upstream names must not imply endorsement.

## Русский

Открытая модель Necaramba 2: 77 892 английских и 1 419 808 русских словоформ, 233 правила опечаток и 67 предпочтительных написаний с «ё». Данные Caramba не использованы для её создания. Для распространения сохраняйте все лицензии из `Licenses/`, происхождение и описание изменений.

Словари хранятся компактно; модель загружается вне потока обработки клавиш. Известные слова сохраняются, неоднозначные варианты не угадываются. Опечатки исправляются по собственному явному списку, восстановление «ё» включается настройкой. Это не частотная модель и не обещание полного покрытия языка.

Команды воспроизводимой генерации, сравнения и сборки приложения приведены выше. Для открытой сборки включите `NECARAMBA_OPEN_MODEL=YES` и не задавайте `NECARAMBA_LOCAL_PATTERN_MODEL`. Синтетические результаты следует отличать от проверки живого ввода в браузерах и редакторах. Публикация GitHub-релиза автоматически не выполняется.
