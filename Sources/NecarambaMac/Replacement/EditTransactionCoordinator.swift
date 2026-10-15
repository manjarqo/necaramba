import Foundation
import NecarambaCore

/// Main owns the transaction through completion, including cancellation of a posted batch.
/// A cancelled operation keeps its slot until it returns; stale edits are never queued.
@MainActor public final class EditTransactionCoordinator {
  public enum State: Equatable { case idle, preflight, posting, verifying, finished, cancelled }
  public private(set) var state: State = .idle
  private var active = false
  private var operationID: UUID?
  private var task: Task<Void, Never>?
  public init() {}
  public func start(token: ContextToken, operation: @escaping @MainActor () async -> ApplyResult,
                    completion: @escaping @MainActor (ApplyResult) -> Void) {
    guard !active else { completion(.aborted); return }
    active = true
    operationID = UUID()
    state = .preflight
    task = Task { @MainActor in
      let result = await operation()
      let cancelled = Task.isCancelled
      state = cancelled ? .cancelled : .finished
      task = nil
      operationID = nil
      active = false
      completion(cancelled && result == .committed ? .uncertain : result)
    }
  }
  public func perform(token: ContextToken, operation: @escaping @MainActor () async -> ApplyResult) async -> ApplyResult {
    guard !active, !Task.isCancelled else { return .aborted }
    let requestID = UUID()
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        start(token: token, operation: operation, completion: { continuation.resume(returning: $0) })
        operationID = requestID
      }
    }, onCancel: {
      Task { @MainActor [weak self] in
        guard self?.operationID == requestID else { return }
        self?.cancel()
      }
    })
  }
  public func transition(_ state: State) { if active { self.state = state } }
  public func cancel() { task?.cancel() }
}
