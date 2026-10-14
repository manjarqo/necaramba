import Foundation
import AVFoundation
import Darwin
/// File validation and playback run on a serial utility executor, outside the input executor.
public final class SoundStore {
 private let queue=DispatchQueue(label:"org.necaramba.sound",qos:.utility)
 private let url:URL
 private let defaultSoundURL:URL?
 private let snapshotCaptured: () throws -> Void
 private var enabled=true
 private var player:AVAudioPlayer?
 private var recent:[UUID]=[]
 public convenience init(directory:URL,defaultSoundURL:URL? = nil) { self.init(directory:directory,defaultSoundURL:defaultSoundURL,snapshotCaptured:{}) }
 internal init(directory:URL,defaultSoundURL:URL? = nil,snapshotCaptured:@escaping () throws -> Void) { url=directory.appendingPathComponent("correction.audio"); self.defaultSoundURL=defaultSoundURL; self.snapshotCaptured=snapshotCaptured }
 public func setEnabled(_ value:Bool) { queue.async { self.enabled=value; if !value { self.player?.stop() } } }
 @discardableResult public func importSound(from source:URL) throws -> URL {
  try queue.sync {
   guard source.isFileURL else { throw ManagedAssetError.nonLocalURL }
   let scoped=source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
   let directory=url.deletingLastPathComponent()
   try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
   // Bound the read itself. Size metadata cannot protect against a concurrently growing file.
   let handle=try FileHandle(forReadingFrom:source)
   defer { try? handle.close() }
   var bytes=Data()
   let readLimit=5*1024*1024+1
   while bytes.count<readLimit {
    guard let chunk=try handle.read(upToCount:min(64*1024,readLimit-bytes.count)),!chunk.isEmpty else { break }
    bytes.append(chunk)
   }
   guard !bytes.isEmpty,bytes.count<=5*1024*1024 else { throw ManagedAssetError.tooLarge }
   let temporary=directory.appendingPathComponent(".sound-import-"+UUID().uuidString+".audio")
   try bytes.write(to:temporary,options:.withoutOverwriting)
   defer { try? FileManager.default.removeItem(at:temporary) }
   try snapshotCaptured()
   // Decode the entire bounded file, not just its header, before replacing the managed asset.
   let file:AVAudioFile
   do { file=try AVAudioFile(forReading:temporary) } catch { throw ManagedAssetError.invalidSound }
   let rate=file.processingFormat.sampleRate
   guard rate>0,rate<=192000,file.processingFormat.channelCount<=8,file.length>0,Double(file.length)/rate<=10,Double(file.length)*Double(file.processingFormat.channelCount)*4<=32*1024*1024,let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else { throw ManagedAssetError.invalidSound }
   do { try file.read(into:buffer) } catch { throw ManagedAssetError.invalidSound }
   guard Int64(buffer.frameLength)==file.length else { throw ManagedAssetError.invalidSound }
   // Promote exactly the decoded file on the same filesystem; rename atomically preserves the old asset on failure.
   guard rename(temporary.path,url.path)==0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
   return url
  }
 }
 public func reset() throws { try queue.sync { player?.stop(); player=nil; if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } } }
 public var customSoundURL:URL? { queue.sync { FileManager.default.fileExists(atPath:url.path) ? url : nil } }
 public func playCorrection() { enqueuePlayback(id:nil) }
 public func playCorrection(committedID:UUID) { enqueuePlayback(id:committedID) }
 private func enqueuePlayback(id:UUID?) {
  queue.async {
   guard self.enabled else { return }
   if let id { guard !self.recent.contains(id) else { return }; self.recent.append(id); if self.recent.count>1024 { self.recent.removeFirst() } }
   let source=FileManager.default.fileExists(atPath:self.url.path) ? self.url : self.defaultSoundURL
   guard let source else { return }
   self.player=try? AVAudioPlayer(contentsOf:source); self.player?.play()
  }
 }
}
