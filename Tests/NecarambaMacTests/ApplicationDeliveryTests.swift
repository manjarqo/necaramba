import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ApplicationDeliveryTests:XCTestCase {
 func testPreviewIDBindsExactPayloadAndConsumesConsentOnce() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let domain="test.delivery."+UUID().uuidString;let defaults=UserDefaults(suiteName:domain)!
  defer { defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:root) }
  let app=try ApplicationServices(directory:root,defaults:defaults,permissions:DeliveryPermissions(),loginBackend:DeliveryLogin(),onPreferences:{_ in})
  let transport=DeliveryShareSpy()
  let delivery=ApplicationDeliveryServices(application:app,configuration:.init(shareEndpoint:URL(string:"https://feedback.example.invalid/rules")!,bundleID:"test.app"),shareTransport:transport)
  let first=try await delivery.execute("previewShare",arguments:["word":"пример","language":"russian","modelVersion":"0","feedback":NSNull()])
  let second=try await delivery.execute("previewShare",arguments:["word":"тест","language":"russian","modelVersion":"0","feedback":"explicit"])
  do { _=try await delivery.execute("confirmShare",arguments:["previewID":first["previewID"]!]);XCTFail() } catch let e as NativeCommandFailure { XCTAssertEqual(e.code,"conflict") }
  _=try await delivery.execute("confirmShare",arguments:["previewID":second["previewID"]!])
  do { _=try await delivery.execute("confirmShare",arguments:["previewID":second["previewID"]!]);XCTFail() } catch let e as NativeCommandFailure { XCTAssertEqual(e.code,"conflict") }
  let sent=await transport.values
  XCTAssertEqual(sent.map(\.word),["тест"])
  XCTAssertEqual(sent.first?.feedback,"explicit")
 }
 func testMissingConfigurationCannotSendOrPurchase() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let domain="test.delivery."+UUID().uuidString;let defaults=UserDefaults(suiteName:domain)!
  defer { defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:root) }
  let app=try ApplicationServices(directory:root,defaults:defaults,permissions:DeliveryPermissions(),loginBackend:DeliveryLogin(),onPreferences:{_ in})
  let delivery=ApplicationDeliveryServices(application:app,configuration:.init(bundleID:"test.app"))
  for method in ["previewShare","purchase","restore","checkRules","manageSubscription"] {
   do { _=try await delivery.execute(method,arguments:[:]);XCTFail(method) } catch { }
  }
 }
}
private actor DeliveryShareSpy:RuleShareTransport {
 var values:[RuleSharePayload]=[]
 func send(_ payload:RuleSharePayload) async throws { values.append(payload) }
}
private final class DeliveryPermissions:PermissionReading {
 func current()->PermissionState { .init(listen:false,post:false,ax:false,secureInput:false) }
 func request(_ kind:PermissionKind) { }
}
private struct DeliveryLogin:LoginBackend {
 func status()->LoginStatus { .disabled }
 func setEnabled(_ value:Bool) throws { }
}
