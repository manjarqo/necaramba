import CoreGraphics
import Foundation
import NecarambaCore

public struct ShortcutLease: Equatable, Sendable {
  public let id: UUID
  public let context: ContextToken
  public let generation: UInt64
  public let startedNanos: UInt64
  public init(context: ContextToken, generation: UInt64, startedNanos: UInt64) {
    id = UUID()
    self.context = context
    self.generation = generation
    self.startedNanos = startedNanos
  }
}
/// Tap-confined shortcut identity. Cancellation is final for a ticket, even if a later shortcut begins.
public final class ShortcutSession {
  public private(set) var active: ShortcutLease?
  public init() {}
  public func begin(_ lease: ShortcutLease) -> Bool {
    guard active == nil else { return false }
    active = lease
    return true
  }
  public func cancel() { active = nil }
  public func admits(
    _ lease: ShortcutLease, generation: UInt64, context: ContextToken?, now: UInt64
  ) -> Bool {
    active == lease && lease.generation == generation && lease.context == context
      && now >= lease.startedNanos && now - lease.startedNanos < 100_000_000
  }
  /// Only the original trigger press and its first matching release belong to this shortcut.
  public static func consumeTrigger(_ events: [CGEvent]) -> (
    events: [CGEvent], awaitingRelease: Bool
  ) {
    var pressed = false
    var released = false
    var remaining: [CGEvent] = []
    for event in events {
      let isV = event.getIntegerValueField(.keyboardEventKeycode) == 9
      if !pressed, isV, event.type == .keyDown {
        pressed = true
        continue
      }
      if pressed, !released, isV {
        if event.type == .keyUp {
          released = true
          continue
        }
        if event.type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
          continue
        }
      }
      remaining.append(event)
    }
    return (remaining, pressed && !released)
  }
}
