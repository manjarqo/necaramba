# Independent lexical baseline — modified dictionary selection

`independent-v1.json` is an unsigned raw `RuleSnapshot` candidate for packaging and validation, not a trusted production signed payload. It contains 179,000 lowercase English/Russian base words derived from independently licensed LibreOffice dictionary inputs pinned in `Corpora/Sources/provenance.json`. It is a **modified selection**; it does not imply upstream endorsement. Redistribution must include **all files in Licenses/** alongside the payload/documentation.

No Caramba code, CLM1, extracted resources, or personal data were used. Frequency bands are uniformly 1 and are not empirical frequencies. Own exact rules and keyboard maps are independent. `US` and `RU` are corpus layout identifiers: the runtime must resolve real platform layouts and supply verified physical mappings. Russian-PC, ISO/JIS, and installed layout-specific punctuation are not inferred from these aliases.

The frozen holdout currently fails the release layout-recall threshold. Do not enable shipped automatic correction or call this a production-quality language model based on this asset. Production signing keys are not part of this directory.
