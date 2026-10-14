import Foundation
import ImageIO
import UniformTypeIdentifiers
public enum ManagedAssetError: Error { case nonLocalURL, tooLarge, invalidImage, invalidSound }
public final class HeaderImageStore {
 private let url: URL
 private let queue=DispatchQueue(label:"org.necaramba.header-image")
 public init(directory:URL) throws { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); url=directory.appendingPathComponent("header.png") }
 public func importImage(from source:URL) throws {
  guard source.isFileURL else { throw ManagedAssetError.nonLocalURL }
  let scoped=source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
  let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
  guard size <= 10*1024*1024 else { throw ManagedAssetError.tooLarge }
  try importImage(data:Data(contentsOf:source,options:.mappedIfSafe))
 }
 public func importImage(data:Data) throws {
  try queue.sync {
   guard data.count <= 10*1024*1024 else { throw ManagedAssetError.tooLarge }
   guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let width=p[kCGImagePropertyPixelWidth] as? Int,let height=p[kCGImagePropertyPixelHeight] as? Int else { throw ManagedAssetError.invalidImage }
   guard width>0,height>0,width<=8192,height<=8192,width*height<=16_000_000 else { throw ManagedAssetError.tooLarge }
   guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(width,height)] as CFDictionary) else { throw ManagedAssetError.invalidImage }
   let output=NSMutableData()
   guard let destination=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else { throw ManagedAssetError.invalidImage }
   CGImageDestinationAddImage(destination,image,nil)
   guard CGImageDestinationFinalize(destination) else { throw ManagedAssetError.invalidImage }
   try (output as Data).write(to:url,options:.atomic)
  }
 }
 public func loadImageData() throws -> Data? { try queue.sync { FileManager.default.fileExists(atPath:url.path) ? try Data(contentsOf:url) : nil } }
 public func remove() throws { try queue.sync { if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } } }
}
