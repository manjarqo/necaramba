import Foundation
import Security
import NecarambaCore

public protocol EntitlementMaterialStore { func read() throws -> Data?; func write(_ data: Data) throws }
public struct CachedEntitlementVerification: Sendable {
    public let productID: String
    public let expires: Date
    public let revoked: Bool
    public init(productID: String, expires: Date, revoked: Bool) { self.productID = productID; self.expires = expires; self.revoked = revoked }
}
public actor VerifiedEntitlementCache {
    private struct Record: Codable {
        let material: String
        let checkedAt: Date
        let latestObserved: Date?
        var rollbackFloor: Date { latestObserved ?? checkedAt }
    }
    private let storage: EntitlementMaterialStore
    private let verify: (String) async -> CachedEntitlementVerification?
    public init(storage: EntitlementMaterialStore, verify: @escaping (String) async -> CachedEntitlementVerification?) { self.storage = storage; self.verify = verify }
    public func save(material: String, checkedAt: Date) async throws {
        guard material.utf8.count <= 65536, await verify(material) != nil else { throw LicensingError.unverified }
        // Re-observing the same signed transaction is not a fresh verification event.
        // Keep its original grace start even if the caller's clock has advanced.
        if let data = try storage.read(), data.count <= 131072,
           let previous = try? JSONDecoder().decode(Record.self, from: data) {
            guard checkedAt >= previous.rollbackFloor else { throw LicensingError.unavailable }
            if previous.material == material { return }
        }
        try storage.write(JSONEncoder().encode(Record(material: material, checkedAt: checkedAt, latestObserved: checkedAt)))
    }
    public func load(now: Date) async -> EntitlementState {
        guard let data = try? storage.read(), data.count <= 131072,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              let verified = await verify(record.material) else { return .unavailable }
        guard now >= record.rollbackFloor else { return .unavailable }
        if now > record.rollbackFloor {
            let advanced = Record(material: record.material, checkedAt: record.checkedAt, latestObserved: now)
            guard (try? storage.write(JSONEncoder().encode(advanced))) != nil else { return .unavailable }
        }
        if verified.revoked { return .revoked }
        return EntitlementPolicy.offline(lastVerified: record.checkedAt, expires: verified.expires, now: now)
    }
}
public struct KeychainEntitlementMaterialStore: EntitlementMaterialStore {
    private let service: String
    public init(service: String) { self.service = service }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "verified-entitlement-v1"] }
    public func read() throws -> Data? {
        guard !service.isEmpty else { throw LicensingError.unavailable }
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess else { throw LicensingError.unavailable }; return result as? Data
    }
    public func write(_ data: Data) throws {
        guard !service.isEmpty, data.count <= 131072 else { throw LicensingError.unavailable }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw LicensingError.unavailable }
        } else if status != errSecSuccess { throw LicensingError.unavailable }
    }
}
