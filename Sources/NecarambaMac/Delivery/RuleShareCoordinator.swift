import NecarambaCore
@MainActor public final class RuleShareCoordinator {
    private let transport: RuleShareTransport
    private var pending: RuleSharePayload?
    public init(transport: RuleShareTransport) { self.transport = transport }
    @discardableResult public func preview(_ payload: RuleSharePayload) throws -> RuleSharePayload {
        pending = nil
        let snapshot = try payload.validated(); pending = snapshot; return snapshot
    }
    public func cancel() { pending = nil }
    public func confirm() async throws {
        guard let payload = pending else { return }; pending = nil
        try await transport.send(payload)
    }
}
