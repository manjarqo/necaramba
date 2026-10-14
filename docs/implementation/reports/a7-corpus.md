# A7 independent corpus and quality gate

Status: runner/validation and independently licensed lexical baseline implemented. **Release quality gate fails.** No shipping enablement is justified.

The raw unsigned snapshot is `Resources/Rules/independent-v1.json`, SHA256 `c5b8ffaae684f053cb57203bc364115fec413224f659d0bbac8b9b2d1b04a133`, 12,376,802 bytes, 179,000 English/Russian base words, four own typo rules, three own ё rules, uniform frequency band 1, and corpus `US`/`RU` keyboard aliases. It is independent of Caramba and is not a production signed package. Distribution must include `Resources/Rules/Licenses/`. Actual native layout IDs and verified physical maps must be wired by composition/runtime; aliases do not claim Russian-PC/ISO/JIS support.

Provenance: LibreOffice/dictionaries pinned revision `67032ee957631908098a72edf48dc81cac27e369`. Source-specific SCOWL and Alexander I. Lebedev BSD-style notices and full lexical input files are retained. Manifest pins corpus, snapshot, source files and license bytes with SHA256. Generated selection is clearly marked modified. Own synthetic transformations are CC0. These are licensed, dictionary-derived single-word oracles, **not a natural typing gold standard**, editor acceptance corpus, or empirical language-frequency sample. Affixes are not expanded. No personal text, installed-app resources, CLM1, or recovered implementation is included.

Current corpus revision is `independent-v2-oracle-fix`, 18,010 cases: train 6,002; calibration 6,002; holdout 6,006; holdout no-change 3,602. Coarse first-four-character families (language-specific, ё folded for grouping) stay in one split. Unicode-normalized identical input/expected values also cannot cross splits. The full external dictionary is fixed prior lexical knowledge, not trained from these evaluation labels. Prefix grouping does not prove complete linguistic/morphological independence. The synthetic cases cover lower/title/upper case, both languages, wrong layout, mixed/code/URL/email/path/number guards, and keyboard punctuation. App categories are token simulations only.

| Measurement | Calibration | Holdout |
|---|---:|---:|
| total | 6,002 | 6,006 |
| TP | 1,966 | 1,943 |
| FP | 0 | 0 |
| FN | 436 | 461 |
| exact-correction precision | 100% | 100% |
| no-change false-change rate | 0% | 0% |
| layout recall | 81.8333% | 80.8670% |
| exit | 1 | 1 |

Holdout Wilson 95% intervals: precision [99.8027%, 100%]; false-change [0%, 0.10654%]; layout recall [79.2441%, 82.3912%]. Point thresholds are precision ≥99.5%, false-change ≤0.1%, layout recall ≥95%. Zero observed false changes does not establish a true population rate below the threshold. Reports publish raw denominators, per-category confusion counts, intervals, and every exact mismatch. Undefined denominators are null and fail gates. A wrong nonempty replacement counts FP and FN, so changing to any wrong word cannot inflate recall.

All 459 holdout layout misses have punctuation in the source keyboard spelling: 229 lowercase Russian, 229 title-case Russian, one explicit `ght;lt` → `прежде` example. Current TokenGuard protects these before candidate generation. The other two misses are unsupported exact-typo families (`превет` → `привет`, `helllo` → `hello`). No linguistic engine changes, threshold tuning, or new correction rules were made from holdout outcomes. Follow-up work should use calibration and retain this baseline.

Coverage limit: holdout has only two exact-rule typo samples and one ё sample. Calibration has one typo and one ё sample. `doubleCaps` is explicitly reported with zero samples. This is insufficient to certify these features even when exact seed examples pass. Broad typo/ё/doubleCaps quality requires a separate reviewed corpus expansion with independently sourced labels; it is not represented as complete here. No n-gram/frequency scoring is calibrated.

Oracle review found 84 holdout title-case rows in v1 whose first source character was punctuation; uppercasing a comma did not encode Shift, producing a contradictory input/output pair. A new RED consistency test demonstrated the validator gap. V2 fixes only the source encoding (`<` for capital Б, `:` for capital Ж, etc.), preserving targets, families, rules, and thresholds. V1 holdout/manifest/generator and original measurements are archived under `Corpora/Archive/v1` and `Reports/*-v1-invalid-labels.json`; their metrics are explicitly invalid as a quality claim. V2 remeasurement remains the same failed result. An earlier split overlap was corrected by validation before first predictions. Neither change selected examples for favorable outcomes.

Verification: eight CorpusRunnerTests pass after observed RED failures for missing contracts, family leakage bypass, unknown nested manifest fields, absent category coverage, and contradictory labels. Manifest integration tests verify all committed bytes and reject tampering/unknown licenses. Locally the CLI was compiled against the built Core static library because Package.swift is root-owned; equivalent root target declaration is `.executableTarget(name: "CorpusRunner", dependencies: ["NecarambaCore"], path: "Tools/CorpusRunner")`. CLI holdout and calibration both produced reports and exited 1 as required for failed recall. The report uses immutable synthetic token replay with empty physical-event arrays, not the real input callback.

Physical-input differential run, actual Caramba comparison, all editor/OS/device combinations, Intel runtime, release signing, packaging and notarization are **unrun**. No system settings, TCC, login items, installed Caramba, or personal documents were modified. Final verification: `swift test` passed 87 XCTest cases (40 Mac + 47 Core, including eight corpus cases), zero failures. Release builds for arm64 and x86_64 both exited 0. The installed Xcode toolchain emitted an x86_64 deprecation warning for its macOS 27 deployment target; this is compile evidence only, not verification of macOS 12 runtime compatibility. A tampered rules-hash manifest exited 2 before producing output. Product-source `git diff --cached --check` passed. Original SCOWL license text retains one upstream trailing space to preserve its pinned bytes; it is the only staged whitespace warning.
