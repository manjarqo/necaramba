import AppKit

/// The Necaramba mark: one keycap carrying a Latin "Q" and a Cyrillic "Й".
/// Drawn in code so every Dock size and the menu bar template stay crisp.
public enum BrandMark {
  static let plate = NSColor(srgbRed: 0x3B / 255, green: 0x3F / 255, blue: 0xD9 / 255, alpha: 1)
  static let keySide = NSColor(srgbRed: 0x2A / 255, green: 0x2D / 255, blue: 0xA6 / 255, alpha: 1)
  static let keyFace = NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xFB / 255, alpha: 1)
  static let latin = NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)

  /// A macOS app icon: the plate fills the 824/1024 icon grid with a soft shadow.
  public static func appIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let size = CGFloat(pixels)
    draw(in: rep) {
      let inset = size * 100 / 1024
      let side = size - inset * 2
      let plateRect = NSRect(x: inset, y: inset, width: side, height: side)
      NSGraphicsContext.saveGraphicsState()
      if pixels >= 64 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        // Shadow offsets ignore the flipped context: negative falls downward.
        shadow.shadowOffset = NSSize(width: 0, height: -size * 10 / 1024)
        shadow.shadowBlurRadius = size * 22 / 1024
        shadow.set()
      }
      plate.setFill()
      NSBezierPath(roundedRect: plateRect, xRadius: side * 0.225, yRadius: side * 0.225).fill()
      NSGraphicsContext.restoreGraphicsState()
      drawKeycap(in: plateRect, unit: side / 100)
    }
    return rep
  }

  /// The plate-relative keycap, in a flipped (top-left origin) context.
  private static func drawKeycap(in plateRect: NSRect, unit u: CGFloat) {
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
      NSRect(x: plateRect.minX + x * u, y: plateRect.minY + y * u, width: w * u, height: h * u)
    }
    keySide.setFill()
    NSBezierPath(roundedRect: rect(21, 22, 58, 60), xRadius: 12 * u, yRadius: 12 * u).fill()
    keyFace.setFill()
    NSBezierPath(roundedRect: rect(21, 17, 58, 58), xRadius: 12 * u, yRadius: 12 * u).fill()
    let font = NSFont.systemFont(ofSize: 19 * u, weight: .bold)
    legend("Q", font: font, color: latin, x: plateRect.minX + 31 * u,
           baseline: plateRect.minY + 40 * u, alignRight: false)
    legend("Й", font: font, color: plate, x: plateRect.minX + 69 * u,
           baseline: plateRect.minY + 66 * u, alignRight: true)
  }

  private static func legend(_ text: String, font: NSFont, color: NSColor,
                             x: CGFloat, baseline: CGFloat, alignRight: Bool) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let width = string.size().width
    string.draw(at: NSPoint(x: alignRight ? x - width : x, y: baseline - font.ascender))
  }

  /// Monochrome template for the status item; macOS tints it for the menu bar.
  public static func statusImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
      NSColor.black.setStroke()
      let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.75, width: 15, height: 14.5),
                                 xRadius: 3.5, yRadius: 3.5)
      outline.lineWidth = 1.4
      outline.stroke()
      let font = NSFont.systemFont(ofSize: 5.6, weight: .bold)
      legend("Q", font: font, color: .black, x: 3.8, baseline: 8.1, alignRight: false)
      legend("Й", font: font, color: .black, x: 14.3, baseline: 14.2, alignRight: true)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Necaramba"
    return image
  }

  private static func draw(in rep: NSBitmapImageRep, _ body: () -> Void) {
    guard let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return }
    let cg = bitmap.cgContext
    cg.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    body()
    NSGraphicsContext.restoreGraphicsState()
  }
}
