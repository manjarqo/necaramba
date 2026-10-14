import Foundation
import AVFoundation
/// File validation and playback run on a serial utility executor, outside the input executor.
public final class SoundStore {
 private let queue=DispatchQueue(label:"org.necaramba.sound",qos:.utility)
 private let url:URL
 private let defaultSoundURL:URL?
 private var enabled=true
 private var player:AVAudioPlayer?
 private var recent:[UUID]=[]
 public init(directory:URL,defaultSoundURL:URL? = nil) { url=directory.appendingPathComponent("correction.audio"); self.defaultSoundURL=defaultSoundURL }
 public func setEnabled(_ value:Bool) { queue.async { self.enabled=value; if !value { self.player?.stop() } } }
 @discardableResult public func importSound(from source:URL) throws -> URL {
  try queue.sync {
   guard source.isFileURL else { throw ManagedAssetError.nonLocalURL }
   let scoped=source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
   let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
   guard size>0,size<=5*1024*1024 else { throw ManagedAssetError.tooLarge }
   // Decode the entire bounded file, not just its header, before replacing the managed asset.
   let file:AVAudioFile
   do { file=try AVAudioFile(forReading:source) } catch { throw ManagedAssetError.invalidSound }
   let rate=file.processingFormat.sampleRate
   guard rate>0,rate<=192000,file.processingFormat.channelCount<=8,file.length>0,Double(file.length)/rate<=10,Double(file.length)*Double(file.processingFormat.channelCount)*4<=32*1024*1024,let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else { throw ManagedAssetError.invalidSound }
   do { try file.read(into:buffer) } catch { throw ManagedAssetError.invalidSound }
   guard Int64(buffer.frameLength)==file.length else { throw ManagedAssetError.invalidSound }
   try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
   try Data(contentsOf:source).write(to:url,options:.atomic)
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
