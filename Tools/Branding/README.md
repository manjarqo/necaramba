# Branding

The app icon and the menu bar template are drawn in code by
`Sources/NecarambaMac/Branding/BrandMark.swift`. Regenerate the Dock icon set after
changing it:

```sh
xcrun swiftc -O Sources/NecarambaMac/Branding/BrandMark.swift Tools/Branding/RenderAppIcon.swift -o /tmp/render-app-icon
/tmp/render-app-icon App/macos/Runner/Assets.xcassets/AppIcon.appiconset
```
