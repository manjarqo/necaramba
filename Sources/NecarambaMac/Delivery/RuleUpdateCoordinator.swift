import Foundation
import NecarambaCore

public enum RuleUpdateStatus: Equatable, Sendable {
    case idle, checking, current(UInt64), failed(String)
}
public actor RuleUpdateCoordinator {
    private let store: RuleSlotStore
    private let bundled: RulePackage
    private let consumer: RuleSnapshotConsumer
    private let downloader: RulePackageDownloading
    private let endpoint: URL?
    private let schedule: RuleUpdateSchedule
    private var busy = false
    private var started = false
    private var timer: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<RuleUpdateStatus>.Continuation] = [:]
    private var state: RuleUpdateStatus = .idle
    public init(store: RuleSlotStore, bundled: RulePackage, consumer: RuleSnapshotConsumer, downloader: RulePackageDownloading, endpoint: URL?, schedule: RuleUpdateSchedule = .init()) {
        self.store = store; self.bundled = bundled; self.consumer = consumer; self.downloader = downloader; self.endpoint = endpoint; self.schedule = schedule
    }
    public func statuses() -> AsyncStream<RuleUpdateStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation; continuation.yield(state)
            continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        }
    }
    private func remove(_ id: UUID) { continuations.removeValue(forKey: id) }
    private func publish(_ status: RuleUpdateStatus) { state = status; for c in continuations.values { c.yield(status) } }
    public func start() async {
        guard !started else { return }; started = true
        do { let verified = try store.load(bundled: bundled); consumer.install(verified.snapshot); publish(.current(verified.modelVersion)) }
        catch { publish(.failed("local_rules_unavailable")) }
        if schedule.takeScheduledCheck() { await check() }
        guard started else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                // Timer wakes once per minute; daily schedule never retries immediately after failure.
                do { try await Task.sleep(nanoseconds: 60 * 1_000_000_000) } catch { return }
                await self?.scheduledTick()
            }
        }
    }
    public func stop() { started = false; timer?.cancel(); timer = nil }
    private func scheduledTick() async { if schedule.takeScheduledCheck() { await check() } }
    public func checkNow() async { if schedule.takeManualCheck() { await check() } }
    private func check() async {
        guard !busy, let endpoint else { return }
        busy = true; defer { busy = false }; publish(.checking)
        do {
            let package = try await downloader.fetch(from: endpoint)
            let verified = try store.promote(package)
            consumer.install(verified.snapshot)
            // current is durable delivery version, not acknowledgement of runtime activation.
            publish(.current(verified.modelVersion))
        } catch is CancellationError { publish(.failed("cancelled")) }
        catch let error as RuleVerificationError { publish(.failed("verification_\(error)")) }
        catch { publish(.failed("update_unavailable")) }
    }
    deinit { timer?.cancel() }
}
