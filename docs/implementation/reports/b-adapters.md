# Native adapter progress B1/B2/B5

Implemented domain ports for permissions/layout/context/clipboard; native permission monitor, verified TIS switching/UCKeyTranslate, focus-epoch state and main-runloop AX observer, generation-owned clipboard transactions, system pasteboard adapter. TestHost has two text views, secure field, focus switch and marked-text fixture.

TDD: PermissionTests RED missing package before A1 integration; LayoutAdapterTests RED missing LayoutAccess/VerifiedLayoutSwitcher/ContextState; ClipboardTransactionTests RED missing clipboard types. GREEN focused7 permission/layout and4 clipboard tests; full native integration suite passing after storage fixes. No permission prompts or general clipboard access in tests. Logs retained in .superpowers/sdd/2026-10-14-necaramba-plan.

TestHost universal xcodebuild succeeded; lipo reports x86_64 arm64. Ad-hoc signed own host only, not Developer ID/notarized release. Physical TCC/input host scenarios unrun. ContextMonitor requires explicit qualified control policy; never asserts every AX text field safe. Runtime/replacement integration and real selection remain pending subsequent B tasks. Clipboard API cannot atomically compare-and-write across arbitrary external apps; bounded best-effort ownership with generation checks is not a guarantee against simultaneous external mutation at OS level.
