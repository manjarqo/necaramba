import Foundation
import OSLog

/// Redacted stages only. Call sites must never pass keyboard text, AX values,
/// titles, clipboard content or document paths. No event stream is recorded.
enum InputDiagnostics {
  private static let logger = Logger(subsystem: "local.necaramba.app", category: "ManualInput")
  static func event(_ reason: String, detail: Int = 0) {
    logger.notice("stage=\(reason, privacy: .public) code=\(detail, privacy: .public)")
  }
}
