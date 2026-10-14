import Foundation
public enum HeaderPalette {
 public static let defaultIndex = 0
 public static let colors: [UInt32] = [0xDAE8DE,0xD8E6E8,0xDCE3F1,0xE5DEF0,0xEFDAEA,0xF2DEDB,0xF4E2CC,0xEEE9CB,0xE3EACB,0xCFE7DF,0xB6D2C1,0xB5D0D7,0xB8C6E3,0xC8B9DD,0xDEB8D0,0xE3BCB6,0xE7C7A5,0xDDD5A2,0xCBD8A6,0xA9D1C4,0xAAC2B3,0x9AB4C0,0xB5A8BD,0xC3AA9C,0xB4B998]
 private static func luminance(_ color: UInt32) -> Double {
  let components = [Double((color >> 16)&255),Double((color >> 8)&255),Double(color&255)].map { x -> Double in let c=x/255; return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
  return components[0]*0.2126+components[1]*0.7152+components[2]*0.0722
 }
 public static func contrast(_ a: UInt32,_ b: UInt32) -> Double { let x=luminance(a),y=luminance(b); return (max(x,y)+0.05)/(min(x,y)+0.05) }
 public static func foreground(for color: UInt32) -> UInt32 { contrast(color,0) > contrast(color,0xFFFFFF) ? 0 : 0xFFFFFF }
}
