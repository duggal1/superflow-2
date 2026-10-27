import Foundation
import SuperflowInferenceHelperCore
import SuperflowInferenceHelperProtocol
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import XCTest

final class InferenceHelperServiceTests: XCTestCase {
    private actor FakeLlamaRuntime: LlamaRuntime {
        private var loaded = false
        private let loadError: String?

        init(loadError: String? = nil) { self.loadError = loadError }

        func load(modelURL: URL) async throws {
            if let loadError { throw NSError(domain: "FakeLlamaRuntime", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: loadError]) }
            loaded = true
        }

        func countTokens(_ text: String) async -> Int? { loaded ? text.split(separator: " ").count : nil }

        func complete(prompt: String, maxTokens: Int) async throws -> String {
            guard loaded else { throw NSError(domain: "FakeLlamaRuntime", code: 2) }
            return "cleaned: \(prompt.prefix(maxTokens))"
        }
    }

    func testPingReturnsProtocolVersion() {
        let replied = expectation(description: "ping reply")
        var version: String?
        InferenceHelperService().ping { value in
            version = value
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(version, InferenceHelperProtocolVersion.current)
    }

    func testPrepareRejectsEmptyPath() {
        let replied = expectation(description: "empty path reply")
        var success: Bool?
        var reason: String?
        InferenceHelperService().prepareModel(atPath: "") { ok, message in
            success = ok
            reason = message
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(success, false)
        XCTAssertEqual(reason, "Model path is empty.")
    }

    func testPrepareRejectsMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-missing-\(UUID().uuidString)")
        let replied = expectation(description: "missing path reply")
        var reason: String?
        InferenceHelperService().prepareModel(atPath: missing.path) { ok, message in
            XCTAssertFalse(ok)
            reason = message
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(reason, "Model path does not exist: \(missing.path)")
    }

    func testPrepareLoadsRuntimeForTokenizationAndCompletion() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-model-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let service = InferenceHelperService(runtime: FakeLlamaRuntime())
        let replied = expectation(description: "model load reply")
        var success: Bool?
        service.prepareModel(atPath: file.path) { ok, _ in
            success = ok
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(success, true)

        let tokenReply = expectation(description: "token count reply")
        var tokenCount: Int?
        var tokenError: String?
        service.countTokens(in: "hello there") { count, error in
            tokenCount = count
            tokenError = error
            tokenReply.fulfill()
        }
        wait(for: [tokenReply], timeout: 1)
        XCTAssertEqual(tokenCount, 2)
        XCTAssertNil(tokenError)

        let completionReply = expectation(description: "completion reply")
        var completion: String?
        var completionError: String?
        service.complete(prompt: "raw text", maxTokens: 100) { text, error in
            completion = text
            completionError = error
            completionReply.fulfill()
        }
        wait(for: [completionReply], timeout: 1)
        XCTAssertEqual(completion, "cleaned: raw text")
        XCTAssertNil(completionError)
    }

    func testLoadFailureIsReturnedToTheClient() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-model-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let service = InferenceHelperService(runtime: FakeLlamaRuntime(loadError: "bad model"))
        let replied = expectation(description: "failed model load reply")
        var success: Bool?
        var reason: String?
        service.prepareModel(atPath: file.path) { ok, message in
            success = ok
            reason = message
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(success, false)
        XCTAssertEqual(reason, "bad model")
    }
}
