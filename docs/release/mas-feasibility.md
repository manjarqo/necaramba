# Distribution feasibility — 2026-10-14

Developer ID is the primary planned channel; this checkout produces a local prototype, not a notarized distribution.

Apple requires App Sandbox for Mac App Store distribution ([Configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)). Apple lists accessibility APIs in assistive apps among sandbox-incompatible functionality ([Protecting user data](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)). The present edit adapter uses AX; therefore MAS feasibility is BLOCKED, not inferred from other applications' distribution channels. No broad entitlement exception was copied.

Developer ID distribution requires hardened runtime and appropriate signing before notarization ([Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Signing credentials, notarization and clean quarantined install were not exercised. The templates do not prove either channel works.
