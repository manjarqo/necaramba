# VSCodium accessibility — 2026-10-15

Installed bundle identifier: `com.vscodium`, verified from its Info.plist. The visible editor and debug-console editor reported: “The editor is not accessible at this time. To enable screen reader optimized mode, use Shift+Option+F1”. The user-level setting explicitly contains `editor.accessibilitySupport: off`.

Necaramba's Electron activation allowlist omitted VSCodium. Added the exact identifier to the existing AXManualAccessibility activation path, preserving delayed refresh and lifecycle cancellation. Electron documents this mechanism at https://www.electronjs.org/docs/latest/tutorial/accessibility . No blanket editable-role qualification or permission/security bypass was added.

The regression test failed with 3 assertions before the production change. All activation tests then passed. Full Swift suite: 459 executed, one optional private-model skip, zero failures. Public-model universal release build succeeded and strict deep signature verification passed. The local app was restarted; no publication performed. Existing uncommitted Safari mitigation retained.

The explicit user setting is a separate obstacle. The user explicitly declined changing it to auto; off is preserved. Research continues on independent physical-input delivery; see the prior compatibility research. Physical manual/automatic conversion in VSCodium is not yet verified. New app activation alone must not be called a complete fix while editor accessibility remains disabled.

After restart and VSCodium activation, a newly created empty Untitled document still reported editor inaccessible while off was preserved. The empty test tab was closed, without modifying a user document. Activation therefore does not by itself fix the reported issue.
