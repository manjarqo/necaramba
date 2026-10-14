import Foundation
import ServiceManagement
/// Instantiate only in the application composition root; tests use LoginBackend fakes.
public final class SystemLoginBackend:LoginBackend {
 private let helperBundleID:String
 private let defaults:UserDefaults
 public init(mainBundleID:String,defaults:UserDefaults) throws {
  guard mainBundleID.split(separator:".").count>=2,mainBundleID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0=="." || $0=="-") }) else { throw LoginError.invalidBundleIdentifier }
  helperBundleID=mainBundleID+".LoginHelper"; self.defaults=defaults
 }
 public func status()->LoginStatus {
  if #available(macOS 13.0,*) {
   switch SMAppService.mainApp.status { case .enabled:return .enabled; case .notRegistered:return .disabled; case .requiresApproval:return .requiresApproval; case .notFound:return .unavailable; @unknown default:return .unavailable }
  }
  // Legacy API has no authoritative query; preference is intentionally not represented as enabled.
  return .unavailable
 }
 public func setEnabled(_ value:Bool) throws {
  if #available(macOS 13.0,*) {
   if defaults.bool(forKey:"login.legacyRegistered") {
    guard SMLoginItemSetEnabled(helperBundleID as CFString,false) else { throw LoginError.changeRejected }
    defaults.set(false,forKey:"login.legacyRegistered")
   }
   if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
  } else {
   guard SMLoginItemSetEnabled(helperBundleID as CFString,value) else { throw LoginError.changeRejected }
   defaults.set(value,forKey:"login.legacyRegistered")
  }
 }
}
