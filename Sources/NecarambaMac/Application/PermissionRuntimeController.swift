import NecarambaCore

/// Rebuilds permission-sensitive native resources after a grant or revocation.
/// Reading permissions never prompts; secure input is handled by the context monitor.
@MainActor public final class PermissionRuntimeController {
    private let permissions: PermissionReading
    private let start: () -> Bool
    private let stop: () -> Void
    private let isRunning: () -> Bool
    private var previous: PermissionState?
    private var running = false

    public init(permissions: PermissionReading, start: @escaping () -> Bool, stop: @escaping () -> Void, isRunning: @escaping () -> Bool) {
        self.permissions = permissions
        self.start = start
        self.stop = stop
        self.isRunning = isRunning
    }

    @discardableResult public func refresh() -> Bool {
        let current = permissions.current()
        if let previous,
           (previous.listen != current.listen || previous.post != current.post || previous.ax != current.ax || !isRunning()) {
            stop()
            running = false
        }
        previous = current
        if !running { running = start() }
        return running
    }
}
