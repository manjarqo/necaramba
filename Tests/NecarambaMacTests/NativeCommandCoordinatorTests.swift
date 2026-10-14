import XCTest
@testable import NecarambaMac

@MainActor final class NativeCommandCoordinatorTests: XCTestCase {
    func testDuplicateCommandIsNotExecutedTwice() async throws {
        var calls = 0
        let bridge = NativeCommandCoordinator(snapshot: { [:] }, execute: { _, _ in calls += 1; return [:] })
        let envelope = command(bridge, id: "one")
        let first = try await bridge.command("setPreferences", envelope: envelope)
        let second = try await bridge.command("setPreferences", envelope: envelope)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(first.state["revision"] as? Int, 1)
        XCTAssertEqual(second.state["revision"] as? Int, 1)
    }
    func testStaleRevisionAndReusedIDWithDifferentPayloadNeverMutate() async throws {
        var calls = 0
        let bridge = NativeCommandCoordinator(snapshot: { [:] }, execute: { _, _ in calls += 1; return [:] })
        let original = command(bridge, id: "one")
        _ = try await bridge.command("setPreferences", envelope: original)
        do { _ = try await bridge.command("clearWords", envelope: original); XCTFail("reused ID accepted") }
        catch let error as NativeCommandFailure { XCTAssertEqual(error.code, "conflict") }
        var stale = original; stale["requestID"] = "two"
        do { _ = try await bridge.command("setPreferences", envelope: stale); XCTFail("stale accepted") }
        catch let error as NativeCommandFailure { XCTAssertEqual(error.code, "conflict") }
        XCTAssertEqual(calls, 1)
    }
    func testFailedMutationKeepsRevisionAndErrorIsRedacted() async throws {
        let bridge = NativeCommandCoordinator(snapshot: { [:] }, execute: { _, _ in throw NSError(domain: "PRIVATE_TEXT", code: 1) })
        do { _ = try await bridge.command("setPreferences", envelope: command(bridge, id: "one")); XCTFail() }
        catch let error as NativeCommandFailure {
            XCTAssertEqual(error.code, "ioFailure")
            XCTAssertFalse(String(describing: error).contains("PRIVATE_TEXT"))
        }
        XCTAssertEqual(bridge.state()["revision"] as? Int, 0)
    }
    func testUnknownMethodAndBooleanRevisionRejectBeforeExecution() async {
        var calls = 0
        let bridge = NativeCommandCoordinator(snapshot: { [:] }, execute: { _, _ in calls += 1; return [:] })
        var envelope = command(bridge, id: "one"); envelope["expectedRevision"] = true
        do { _ = try await bridge.command("setPreferences", envelope: envelope); XCTFail() } catch {}
        do { _ = try await bridge.command("readTypedText", envelope: command(bridge, id: "two")); XCTFail() } catch {}
        XCTAssertEqual(calls, 0)
    }
    func testDelayedImportRejectsNativeRevisionChangeAtCommit() async throws {
        var commitCount = 0
        var resume: CheckedContinuation<Void, Never>?
        let bridge = NativeCommandCoordinator(snapshot: { [:] }, execute: { _, arguments in
            await withCheckedContinuation { resume = $0 }
            try (arguments["__nativeMutationGuard"] as? (() throws -> Void))?()
            commitCount += 1
            return [:]
        })
        let pending = Task { try await bridge.command("importArchive", envelope: command(bridge, id: "import")) }
        while resume == nil { await Task.yield() }
        bridge.publishChange()
        resume?.resume()
        do { _ = try await pending.value; XCTFail("stale import committed") }
        catch let failure as NativeCommandFailure { XCTAssertEqual(failure.code, "conflict") }
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(bridge.state()["revision"] as? Int, 1)
    }
    func testOtherFilePanelMutationsCarryCommitGuard() async throws {
        for method in ["chooseApp", "chooseSound"] {
            var resume:CheckedContinuation<Void,Never>?
            var committed = false
            let bridge = NativeCommandCoordinator(snapshot:{ [:] }, execute:{ _, arguments in
                await withCheckedContinuation { resume = $0 }
                try (arguments["__nativeMutationGuard"] as? (() throws -> Void))?()
                committed = true
                return [:]
            })
            let pending = Task { try await bridge.command(method, envelope:command(bridge,id:method)) }
            while resume == nil { await Task.yield() }
            bridge.publishChange()
            resume?.resume()
            do { _ = try await pending.value; XCTFail("\(method) committed after native change") }
            catch let failure as NativeCommandFailure { XCTAssertEqual(failure.code,"conflict") }
            XCTAssertFalse(committed)
        }
    }
    private func command(_ bridge: NativeCommandCoordinator, id: String) -> [String: Any] {
        ["requestID": id, "expectedSessionID": bridge.sessionID, "expectedRevision": 0, "arguments": [String: Any]()]
    }
}
