import XCTest
import NecarambaCore
@testable import NecarambaMac
private final class LoginFake: LoginBackend {
 var current:LoginStatus = .requiresApproval
 func status()->LoginStatus { current }
 func setEnabled(_ value:Bool) throws { }
}
private final class LifecycleRuntime:InputRuntimeControl {
 var reasons:[InvalidationReason]=[]
 func updatePreferences(_ snapshot:PreferencesSnapshot) { }
 func invalidateContext(reason:InvalidationReason) { reasons.append(reason) }
}
private final class LifecycleSourceFake:LifecycleNotificationSource {
 var callback:((InvalidationReason)->Void)?
 var starts=0
 func start(_ callback:@escaping (InvalidationReason)->Void) { starts+=1; self.callback=callback }
 func stop() { callback=nil }
}
final class LifecycleControllerTests:XCTestCase {
 func testApprovalAndObserverOwnership() async throws {
  try await MainActor.run {
   let login=LoginController(backend:LoginFake())
   try login.setEnabled(true); XCTAssertEqual(login.status,.requiresApproval)
   let runtime=LifecycleRuntime(),source=LifecycleSourceFake()
   let controller=LifecycleController(runtime:runtime,source:source)
   controller.start(); controller.start(); source.callback?(.sleep)
   XCTAssertEqual(source.starts,1); XCTAssertEqual(runtime.reasons,[.sleep])
   controller.stop(); source.callback?(.sleep); XCTAssertEqual(runtime.reasons.count,1)
   controller.start(); source.callback?(.unknownInput); XCTAssertEqual(runtime.reasons,[.sleep,.unknownInput])
   controller.stop()
  }
 }
}
