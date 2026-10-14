import Foundation
import StoreKit
import NecarambaCore

/// Commercial composition must supply its own IDs, bundle and expected StoreKit environment.
public actor StoreKitLicensingAdapter: LicensingAdapter {
    private let productIDs: Set<String>
    private let bundleID: String
    private let environment: String
    private let now: () -> Date
    private var prior: EntitlementState = .unavailable
    private var observer: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<EntitlementRevision>.Continuation] = [:]
    private var sequence: UInt64 = 0
    private let cacheStorage: EntitlementMaterialStore?
    private var cache: VerifiedEntitlementCache?
    public init(productIDs: Set<String>, bundleID: String, environment: String = "Production", now: @escaping () -> Date = Date.init, cacheStorage: EntitlementMaterialStore? = nil) {
        self.productIDs = productIDs; self.bundleID = bundleID; self.environment = environment; self.now = now; self.cacheStorage = cacheStorage
    }
    public func current() async -> EntitlementState {
        guard !productIDs.isEmpty, !bundleID.isEmpty else { return .unavailable }
        var best: EntitlementState = .expired
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, accepts(transaction) else { continue }
            let state = stateFor(transaction)
            if case .active = state { prior = state; await saveCache(result); return state }
            if case .revoked = state { best = state }
        }
        if best == .expired, let cache = entitlementCache() {
            let cached = await cache.load(now: now()); prior = cached; return cached
        }
        prior = best; return best
    }
    public func snapshot() async -> EntitlementRevision {
        for _ in 0..<3 {
            let before=sequence
            let state=await current()
            guard before==sequence else { continue }
            sequence &+= 1
            return .init(state:state,sequence:sequence)
        }
        // Continuous concurrent StoreKit changes cannot make a stale snapshot grant access.
        sequence &+= 1
        return .init(state:.unavailable,sequence:sequence)
    }
    public func purchase(productID: String) async throws -> PurchaseOutcome {
        guard productIDs.contains(productID), !bundleID.isEmpty else { throw LicensingError.unknownProduct }
        guard let product = try await Product.products(for: [productID]).first else { throw LicensingError.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, accepts(transaction) else { throw LicensingError.unverified }
            let state = stateFor(transaction); prior = state; await saveCache(result); await transaction.finish(); return .entitled(state)
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw LicensingError.unavailable
        }
    }
    public func restore() async throws -> EntitlementState {
        guard !productIDs.isEmpty, !bundleID.isEmpty else { throw LicensingError.unavailable }
        try await AppStore.sync(); return await current()
    }
    public func updates() async -> AsyncStream<EntitlementRevision> {
        guard !productIDs.isEmpty, !bundleID.isEmpty else { return AsyncStream { $0.finish() } }
        let id = UUID()
        let stream = AsyncStream<EntitlementRevision> { continuation in
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        }
        startObserving()
        return stream
    }
    private func startObserving() {
        guard observer == nil else { return }
        observer = Task { [weak self] in
            for await result in Transaction.updates {
                if Task.isCancelled { break }
                await self?.consume(result)
            }
            await self?.observerFinished()
        }
    }
    private func removeListener(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { observer?.cancel() }
    }
    private func observerFinished() {
        observer = nil
        if !listeners.isEmpty { startObserving() }
    }
    private func consume(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, accepts(transaction) else { return }
        let state = stateFor(transaction)
        prior = state
        sequence &+= 1
        let update=EntitlementRevision(state:state,sequence:sequence)
        for listener in listeners.values { listener.yield(update) }
        await saveCache(result); await transaction.finish()
    }
    private func entitlementCache() -> VerifiedEntitlementCache? {
        if let cache { return cache }
        guard let cacheStorage else { return nil }
        let created = VerifiedEntitlementCache(storage: cacheStorage, verify: { [weak self] material in await self?.verifyCachedMaterial(material) })
        cache = created; return created
    }
    private func saveCache(_ result: VerificationResult<Transaction>) async {
        guard case .verified = result, let cache = entitlementCache() else { return }
        try? await cache.save(material: result.jwsRepresentation, checkedAt: now())
    }
    private func accepts(_ transaction: Transaction) -> Bool {
        guard productIDs.contains(transaction.productID), transaction.appBundleID == bundleID, !transaction.isUpgraded else { return false }
        if #available(macOS 13.0, *) { return transaction.environment.rawValue == environment }
        return transaction.environmentStringRepresentation == environment
    }
    private func stateFor(_ transaction: Transaction) -> EntitlementState {
        if transaction.revocationDate != nil { return .revoked }
        guard let expiry = transaction.expirationDate else {
            // This commercial phase is for subscriptions; non-expiring products require a separately approved policy.
            return .unavailable
        }
        return now() < expiry ? .active(until: expiry, renews: false) : .expired
    }
    /// Cache verification asks StoreKit for its cryptographically verified local transaction, then compares exact signed material.
    public func verifyCachedMaterial(_ material: String) async -> CachedEntitlementVerification? {
        guard material.utf8.count <= 65536 else { return nil }
        for productID in productIDs {
            guard let result = await Transaction.latest(for: productID), result.jwsRepresentation == material,
                  case .verified(let transaction) = result, accepts(transaction), let expiry = transaction.expirationDate else { continue }
            return .init(productID: productID, expires: expiry, revoked: transaction.revocationDate != nil)
        }
        return nil
    }
    deinit { observer?.cancel() }
}
