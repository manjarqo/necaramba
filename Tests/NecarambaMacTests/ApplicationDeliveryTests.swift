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
 func testVerifiedUpdatesAfterSnapshotReachApplicationAndStopUnsubscribes() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let domain="test.delivery."+UUID().uuidString;let defaults=UserDefaults(suiteName:domain)!
  defer { defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:root) }
  let app=try ApplicationServices(directory:root,defaults:defaults,permissions:DeliveryPermissions(),loginBackend:DeliveryLogin(),onPreferences:{_ in})
  let licensing=DeliveryLicensingFake(snapshot:.expired)
  let delivery=ApplicationDeliveryServices(application:app,configuration:.init(bundleID:"test.app"),licensing:licensing)
  await delivery.start(bundle:.main,root:root,install:{ _,_ in })
  XCTAssertEqual(app.licenseState,"expired")
  await delivery.start(bundle:.main,root:root,install:{ _,_ in })
  let initialSubscribers=await licensing.subscriberCount()
  XCTAssertEqual(initialSubscribers,1)
  let pending=expectation(description:"pending approval becomes visible")
  app.onChanged={ if app.licenseState=="pending" { pending.fulfill() } }
  await licensing.emit(.pending)
  await fulfillment(of:[pending],timeout:2)
  let active=expectation(description:"renewal becomes active")
  app.onChanged={ if app.licenseState=="active" { active.fulfill() } }
  await licensing.emit(.active(until:Date(timeIntervalSince1970:2000000000),renews:true))
  await fulfillment(of:[active],timeout:2)
  let revoked=expectation(description:"revocation becomes visible")
  app.onChanged={ if app.licenseState=="revoked" { revoked.fulfill() } }
  await licensing.emit(.revoked)
  await fulfillment(of:[revoked],timeout:2)
  delivery.stop()
  let unsubscribed=await licensing.waitForNoSubscribers()
  XCTAssertTrue(unsubscribed)
  await licensing.emit(.active(until:nil,renews:false))
  XCTAssertEqual(app.licenseState,"revoked")
  await delivery.start(bundle:.main,root:root,install:{ _,_ in })
  let restartedSubscribers=await licensing.subscriberCount()
  XCTAssertEqual(restartedSubscribers,1)
  delivery.stop()
  let restartedUnsubscribed=await licensing.waitForNoSubscribers()
  XCTAssertTrue(restartedUnsubscribed)
 }
 func testStopDuringSnapshotDoesNotKeepStoreKitSubscription() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let domain="test.delivery."+UUID().uuidString;let defaults=UserDefaults(suiteName:domain)!
  defer { defaults.removePersistentDomain(forName:domain);try? FileManager.default.removeItem(at:root) }
  let app=try ApplicationServices(directory:root,defaults:defaults,permissions:DeliveryPermissions(),loginBackend:DeliveryLogin(),onPreferences:{_ in})
  let licensing=DeliveryLicensingFake(snapshot:.expired,holdSnapshot:true)
  let delivery=ApplicationDeliveryServices(application:app,configuration:.init(bundleID:"test.app"),licensing:licensing)
  let startup=Task { await delivery.start(bundle:.main,root:root,install:{ _,_ in }) }
  let requested=await licensing.waitForSnapshotRequest()
  XCTAssertTrue(requested)
  delivery.stop()
  await licensing.releaseSnapshot()
  await startup.value
  let unsubscribed=await licensing.waitForNoSubscribers()
  XCTAssertTrue(unsubscribed)
  XCTAssertEqual(app.licenseState,"unavailable")
 }
}
private actor DeliveryLicensingFake:LicensingAdapter {
 let snapshot:EntitlementState
 let holdSnapshot:Bool
 private var snapshotRequested=false
 private var snapshotWaiter:CheckedContinuation<Void,Never>?
 private var streams:[UUID:AsyncStream<EntitlementState>.Continuation]=[:]
 init(snapshot:EntitlementState,holdSnapshot:Bool=false) { self.snapshot=snapshot;self.holdSnapshot=holdSnapshot }
 func current() async->EntitlementState {
  if holdSnapshot {
   snapshotRequested=true
   await withCheckedContinuation { snapshotWaiter=$0 }
  }
  return snapshot
 }
 func waitForSnapshotRequest() async->Bool {
  for _ in 0..<100 { if snapshotRequested { return true };await Task.yield() }
  return snapshotRequested
 }
 func releaseSnapshot() { snapshotWaiter?.resume();snapshotWaiter=nil }
 func purchase(productID:String) async throws->PurchaseOutcome { .pending }
 func restore() async throws->EntitlementState { snapshot }
 func updates() async->AsyncStream<EntitlementState> {
  let id=UUID()
  return AsyncStream { continuation in
   streams[id]=continuation
   continuation.onTermination={ [weak self] _ in Task { await self?.remove(id) } }
  }
 }
 func emit(_ state:EntitlementState) { for stream in streams.values { stream.yield(state) } }
 func subscriberCount()->Int { streams.count }
 private func remove(_ id:UUID) { streams[id]=nil }
 func waitForNoSubscribers() async->Bool {
  for _ in 0..<100 { if streams.isEmpty { return true }; await Task.yield() }
  return streams.isEmpty
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
