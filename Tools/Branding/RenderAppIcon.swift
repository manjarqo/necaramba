// Renders the Dock icon set from BrandMark. Compile together with
// Sources/NecarambaMac/Branding/BrandMark.swift; argument: output directory.
import AppKit

@main struct RenderAppIcon {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      FileHandle.standardError.write(Data("Usage: render-app-icon <AppIcon.appiconset>\n".utf8)); exit(1)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    for pixels in [16, 32, 64, 128, 256, 512, 1024] {
      guard let png = BrandMark.appIcon(pixels: pixels).representation(using: .png, properties: [:]) else { exit(1) }
      try png.write(to: output.appendingPathComponent("app_icon_\(pixels).png"), options: .atomic)
    }
  }
}
