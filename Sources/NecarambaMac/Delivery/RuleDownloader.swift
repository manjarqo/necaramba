import Foundation
import NecarambaCore

public enum RuleDownloadError: Error, Equatable { case invalidEndpoint, httpStatus, compressedResponse, oversize, invalidResponse, invalidSignatureSize }
public protocol RulePackageDownloading { func fetch(from: URL) async throws -> RulePackage }

/// Bounded streaming reads; Content-Length is only an early hint. Session has no credential/cookie persistence.
final class BoundedHTTPSClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    private let configuration: URLSessionConfiguration
    init(host: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.host = host.lowercased(); self.configuration = configuration
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 15
    }
    func accepts(_ url: URL) -> Bool { url.scheme == "https" && url.host?.lowercased() == host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil && url.fragment == nil && url.query == nil }
    func request(_ url: URL, limit: Int, body: Data? = nil) async throws -> Data {
        guard accepts(url), !host.isEmpty else { throw RuleDownloadError.invalidEndpoint }
        try Task.checkCancellation()
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let responseURL = http.url, accepts(responseURL) else { throw RuleDownloadError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw RuleDownloadError.httpStatus }
        guard http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true else { throw RuleDownloadError.compressedResponse }
        guard response.expectedContentLength <= Int64(limit) else { throw RuleDownloadError.oversize }
        var data = Data(); data.reserveCapacity(min(limit, 65536))
        for try await byte in stream { try Task.checkCancellation(); guard data.count < limit else { throw RuleDownloadError.oversize }; data.append(byte) }
        if response.expectedContentLength >= 0 && Int64(data.count) != response.expectedContentLength { throw RuleDownloadError.invalidResponse }
        return data
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(accepts) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default TLS trust only; never provide credentials for HTTP authentication.
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

public struct RuleDownloader: RulePackageDownloading {
    private let client: BoundedHTTPSClient
    public init(allowedHost: String, configuration: URLSessionConfiguration = .ephemeral) { client = .init(host: allowedHost, configuration: configuration) }
    public func fetch(from url: URL) async throws -> RulePackage {
        guard client.accepts(url) else { throw RuleDownloadError.invalidEndpoint }
        async let manifest = client.request(url.appendingPathComponent("manifest.json"), limit: 65536)
        async let signature = client.request(url.appendingPathComponent("signature.ed25519"), limit: 64)
        async let payload = client.request(url.appendingPathComponent("payload.json"), limit: RulePackageVerifier.maximumPayloadSize)
        let result = try await RulePackage(manifest: manifest, signature: signature, payload: payload)
        guard result.signature.count == 64 else { throw RuleDownloadError.invalidSignatureSize }; return result
    }
}

public struct HTTPSRuleShareTransport: RuleShareTransport {
    private let endpoint: URL?
    private let client: BoundedHTTPSClient
    public init(endpoint: URL?, allowedHost: String) { self.endpoint = endpoint; client = .init(host: allowedHost) }
    public func send(_ payload: RuleSharePayload) async throws {
        guard let endpoint else { throw RuleDownloadError.invalidEndpoint }
        _ = try await client.request(endpoint, limit: 65536, body: JSONEncoder().encode(payload.validated()))
    }
}
