import AppKit
import XCTest
@testable import NecarambaMac

final class BrandMarkTests: XCTestCase {
  private func color(_ rep: NSBitmapImageRep, _ x: Double, _ y: Double) -> (Int, Int, Int, Int) {
    let c = rep.colorAt(x: Int(x * Double(rep.pixelsWide)), y: Int(y * Double(rep.pixelsHigh)))!
      .usingColorSpace(.sRGB)!
    return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
  }

  func testAppIconDrawsTheDualLegendKeycapOnTheIndigoPlate() {
    for pixels in [16, 32, 64, 128, 256, 512, 1024] {
      let rep = BrandMark.appIcon(pixels: pixels)
      XCTAssertEqual(rep.pixelsWide, pixels)
      XCTAssertEqual(rep.pixelsHigh, pixels)
    }
    let rep = BrandMark.appIcon(pixels: 1024)
    XCTAssertEqual(color(rep, 0.02, 0.02).3, 0, "Outside the plate stays transparent")
    let plate = color(rep, 0.5, 0.88)
    XCTAssertEqual(plate.0, 0x3B, accuracy: 3); XCTAssertEqual(plate.2, 0xD9, accuracy: 3)
    let face = color(rep, 0.5, 0.5)
    XCTAssertGreaterThan(face.0, 240, "Keycap face is near white")
  }

  func testStatusImageIsATemplateSizedForTheMenuBar() {
    let image = BrandMark.statusImage()
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    XCTAssertEqual(image.accessibilityDescription, "Necaramba")
  }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) vs \(b)", file: file, line: line)
}
