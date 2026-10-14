import XCTest
import AppKit
import AVFoundation
@testable import NecarambaMac
final class AppearanceStatisticsTests: XCTestCase {
 func testCountersDeduplicatePersistAndReset() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:dir) }
  let store = try StatisticsStore(directory:dir)
  let id = UUID()
  try store.recordCommitted(id:id,kind:.layout,day:"2026-10-14")
  try store.recordCommitted(id:id,kind:.layout,day:"2026-10-14")
  try store.recordCommitted(id:UUID(),kind:.typo,day:"2026-10-14")
  XCTAssertEqual(try store.count(kind:.layout,day:"2026-10-14"),1)
  XCTAssertEqual(store.estimatedSeconds,3)
  XCTAssertEqual(try StatisticsStore(directory:dir).count(kind:.typo,day:"2026-10-14"),1)
  try store.reset(); XCTAssertEqual(store.estimatedSeconds,0)
  XCTAssertEqual(HeaderPalette.colors.count,25)
  for color in HeaderPalette.colors { XCTAssertGreaterThanOrEqual(HeaderPalette.contrast(color,HeaderPalette.foreground(for:color)),4.5) }
 }
 func testHeaderImagePersistsRejectsInvalidAndRemoves() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:dir) }
  let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
  let data = try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
  let store = try HeaderImageStore(directory:dir)
  try store.importImage(data:data)
  let saved = try store.loadImageData()
  XCTAssertEqual(try HeaderImageStore(directory:dir).loadImageData(),saved)
  XCTAssertThrowsError(try store.importImage(data:Data("bad".utf8)))
  XCTAssertThrowsError(try store.importImage(data:Data(count:10*1024*1024+1)))
  XCTAssertEqual(try store.loadImageData(),saved)
  try store.remove(); XCTAssertNil(try store.loadImageData())
 }
 func testSoundRejectsCorruptOversizedAndOverDurationPreservingCustom() throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:dir) }
  let format=try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:8000,channels:1))
  func sound(_ name:String,frames:UInt32) throws -> URL {
   let source=dir.appendingPathComponent(name+".wav")
   let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)); buffer.frameLength=frames
   for i in 0..<Int(frames) { buffer.floatChannelData![0][i]=0 }
   let file=try AVAudioFile(forWriting:source,settings:format.settings); try file.write(from:buffer)
   return source
  }
  let store=SoundStore(directory:dir.appendingPathComponent("managed"))
  let saved=try store.importSound(from:sound("valid",frames:800))
  let bytes=try Data(contentsOf:saved)
  XCTAssertThrowsError(try store.importSound(from:sound("long",frames:88000)))
  let bad=dir.appendingPathComponent("bad"); try Data("corrupt".utf8).write(to:bad)
  XCTAssertThrowsError(try store.importSound(from:bad))
  try Data(count:5*1024*1024+1).write(to:bad)
  XCTAssertThrowsError(try store.importSound(from:bad))
  XCTAssertEqual(try Data(contentsOf:saved),bytes)
  try store.reset(); XCTAssertNil(store.customSoundURL)
 }

}
