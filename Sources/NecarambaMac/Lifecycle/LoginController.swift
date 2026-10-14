import Foundation
public enum LoginStatus:Equatable, Sendable { case enabled, disabled, requiresApproval, unavailable }
public enum LoginError:Error { case changeRejected, invalidBundleIdentifier }
public protocol LoginBackend {
 func status()->LoginStatus
 func setEnabled(_ value:Bool) throws
}
@MainActor public final class LoginController {
 private let backend:LoginBackend
 public private(set) var status:LoginStatus
 public init(backend:LoginBackend) { self.backend=backend; status=backend.status() }
 public func refresh() { status=backend.status() }
 public func setEnabled(_ value:Bool) throws { defer { refresh() }; try backend.setEnabled(value) }
}
