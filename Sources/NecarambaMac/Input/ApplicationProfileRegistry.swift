import Foundation
import NecarambaCore

/// Process-wide verified application profiles, read from tap, AX and main threads.
/// Starts with the built-in profiles; an installed verified package replaces them atomically.
public final class ApplicationProfileRegistry: @unchecked Sendable {
  public static let shared = ApplicationProfileRegistry()
  private let lock = NSLock()
  private var value = ApplicationProfiles.builtIn
  public var current: ApplicationProfiles {
    lock.lock(); defer { lock.unlock() }
    return value
  }
  public func install(_ profiles: ApplicationProfiles) {
    lock.lock(); value = profiles; lock.unlock()
  }
  public func profile(for bundleID: String) -> ApplicationProfile? { current.profile(for: bundleID) }
}
