import XCTest
import NecarambaCore
@testable import NecarambaMac
private final class DeliveryURLProtocol: URLProtocol {
    static var responder: (URLRequest) throws -> (Int, [String: String], Data) = { _ in (404, [:], Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, body) = try Self.responder(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            // Chunking ensures the actual bytes, not Content-Length, drive the bound.
            for start in stride(from: 0, to: body.count, by: 4096) { client?.urlProtocol(self, didLoad: body.subdata(in: start..<min(start + 4096, body.count))) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class RuleDownloaderTests: XCTestCase {
    func client() -> BoundedHTTPSClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DeliveryURLProtocol.self]
        return .init(host: "test.invalid", configuration: config)
    }
    func testActualByteBoundCompression404TruncationAndTimeout() async throws {
        let endpoint = URL(string: "https://test.invalid/payload.json")!
        let cases: [(Int, [String: String], Data, RuleDownloadError)] = [
            (200, [:], Data(repeating: 0, count: 65), .oversize),
            (200, ["Content-Encoding": "gzip"], Data(), .compressedResponse),
            (404, [:], Data(), .httpStatus),
            (200, ["Content-Length": "12"], Data(repeating: 0, count: 3), .invalidResponse)
        ]
        for (code, headers, body, expected) in cases {
            DeliveryURLProtocol.responder = { _ in (code, headers, body) }
            do { _ = try await client().request(endpoint, limit: 64); XCTFail("accepted \(expected)") }
            catch { XCTAssertEqual(error as? RuleDownloadError, expected) }
        }
        DeliveryURLProtocol.responder = { _ in throw URLError(.timedOut) }
        do { _ = try await client().request(endpoint, limit: 64); XCTFail() } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }
    func testSameHostHTTPSOnlyAndNoKeyboardRequestFields() async throws {
        let c = client()
        for value in ["http://test.invalid", "https://other.invalid", "https://user:secret@test.invalid", "https://test.invalid:444"] { XCTAssertFalse(c.accepts(URL(string: value)!)) }
        DeliveryURLProtocol.responder = { request in
            XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
            return (200, [:], Data("ok".utf8))
        }
        let data = try await c.request(URL(string: "https://test.invalid/payload.json")!, limit: 64); XCTAssertEqual(data, Data("ok".utf8))
    }
}
