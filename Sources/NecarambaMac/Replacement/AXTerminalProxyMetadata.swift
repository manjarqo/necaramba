import ApplicationServices

/// xterm's helper textarea transports input and composition residue; its value is
/// not the terminal buffer. Identity is established by exact host and DOM metadata.
enum AXTerminalProxyMetadata {
  static func isHost(_ bundleID: String) -> Bool {
    ApplicationProfileRegistry.shared.profile(for: bundleID)?.terminalProxyHost == true
  }
  static func matches(bundleID: String, role: String, status: AXError, classes: CFTypeRef?) -> Bool {
    guard isHost(bundleID), ["AXTextField", "AXTextArea"].contains(role),
      status == .success, let classes, CFGetTypeID(classes) == CFArrayGetTypeID(),
      let names = classes as? [String], names.count <= 64,
      names.allSatisfy({ $0.utf8.count <= 256 }) else { return false }
    return names.contains("xterm-helper-textarea")
  }

  static func permits(rangeStatus: AXError, range: CFRange?, directLayout: Bool, authorized: Bool) -> Bool {
    guard authorized, directLayout, rangeStatus == .success, let range,
      range.location >= 0, range.location <= 1024 * 1024, range.length == 0 else { return false }
    return true
  }
}
