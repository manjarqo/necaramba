import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testRawTIFFOnlyDropFailsClosed() {
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    board.clearContents()
    board.setData(Data([7]), forType: .tiff)
    XCTAssertNil(MainFlutterWindow.readHeaderDropData(from: board))
  }
  func testFileURLDropReadsBoundedImage() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
    let payload = Data(repeating: 7, count: 1024)
    try payload.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    board.clearContents()
    board.writeObjects([url as NSURL])
    XCTAssertEqual(MainFlutterWindow.readHeaderDropData(from: board), payload)
  }
  func testOversizedFileURLDropFailsClosed() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
    try Data(repeating: 7, count: 10 * 1024 * 1024 + 1).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    board.clearContents()
    board.writeObjects([url as NSURL])
    XCTAssertNil(MainFlutterWindow.readHeaderDropData(from: board))
  }

}
