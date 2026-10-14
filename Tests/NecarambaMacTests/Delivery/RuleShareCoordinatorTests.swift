import XCTest
import NecarambaCore
@testable import NecarambaMac
actor ShareSpy: RuleShareTransport {
    private(set) var payloads: [RuleSharePayload] = []
    func send(_ payload: RuleSharePayload) async throws { payloads.append(payload) }
}
final class RuleShareCoordinatorTests: XCTestCase {
    @MainActor func testCancelNeverSendsAndConfirmConsumesSnapshot() async throws {
        let spy = ShareSpy(); let sut = RuleShareCoordinator(transport: spy)
        try sut.preview(.init(word: "синтетика", language: .russian, modelVersion: 2, feedback: nil))
        sut.cancel(); try await sut.confirm(); let first = await spy.payloads; XCTAssertEqual(first, [])
        let payload = RuleSharePayload(word: "hello", language: .english, modelVersion: 2, feedback: nil)
        try sut.preview(payload); try await sut.confirm(); try await sut.confirm()
        let sent = await spy.payloads; XCTAssertEqual(sent, [payload])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["word", "language", "modelVersion"])
    }
}
private actor RejectingShareTransport: RuleShareTransport {
    var attempts = 0
    func send(_ payload: RuleSharePayload) async throws { attempts += 1; throw URLError(.notConnectedToInternet) }
}
extension RuleShareCoordinatorTests {
    @MainActor func testFailureDoesNotRetryAndInvalidPreviewClearsOldSelection() async throws {
        let transport = RejectingShareTransport(); let sut = RuleShareCoordinator(transport: transport)
        try sut.preview(.init(word: "hello", language: .english, modelVersion: 2, feedback: nil))
        do { try await sut.confirm(); XCTFail() } catch {}
        try await sut.confirm(); let attempts = await transport.attempts; XCTAssertEqual(attempts, 1)
        try sut.preview(.init(word: "hello", language: .english, modelVersion: 2, feedback: nil))
        XCTAssertThrowsError(try sut.preview(.init(word: "bad\nword", language: .english, modelVersion: 2, feedback: nil)))
        try await sut.confirm(); let afterInvalid = await transport.attempts; XCTAssertEqual(afterInvalid, 1)
    }
    @MainActor func testPreviewNormalizesWordAndBoundsFeedback() throws {
        let sut = RuleShareCoordinator(transport: ShareSpy())
        let snapshot = try sut.preview(.init(word: "  E\u{301}cole  ", language: .english, modelVersion: UInt64.max, feedback: "  "))
        XCTAssertEqual(snapshot.word, "École"); XCTAssertNil(snapshot.feedback); XCTAssertEqual(snapshot.modelVersion, UInt64.max)
        XCTAssertThrowsError(try sut.preview(.init(word: "hello", language: .english, modelVersion: 1, feedback: String(repeating: "x", count: 2001))))
    }
}
