import Foundation
public enum HeaderPalette {
 public static let defaultIndex = 0
 public static let colors: [UInt32] = [0x1D3557,0x264653,0x2A9D8F,0x457B9D,0x577590,0x277DA1,0x4D908E,0x43AA8B,0x90BE6D,0x6A994E,0x386641,0x8D99AE,0x6D6875,0xB5838D,0xE5989B,0xAF5170,0x8E4162,0x7B2CBF,0x5A189A,0x3C096C,0x9C6644,0xB08968,0xBC6C25,0xD4A373,0x555B6E]
 private static func luminance(_ color: UInt32) -> Double {
  let components = [Double((color >> 16)&255),Double((color >> 8)&255),Double(color&255)].map { x -> Double in let c=x/255; return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
  return components[0]*0.2126+components[1]*0.7152+components[2]*0.0722
 }
 public static func contrast(_ a: UInt32,_ b: UInt32) -> Double { let x=luminance(a),y=luminance(b); return (max(x,y)+0.05)/(min(x,y)+0.05) }
 public static func foreground(for color: UInt32) -> UInt32 { contrast(color,0) > contrast(color,0xFFFFFF) ? 0 : 0xFFFFFF }
}
