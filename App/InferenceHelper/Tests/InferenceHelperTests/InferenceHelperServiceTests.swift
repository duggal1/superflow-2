import Foundation
import SuperflowInferenceHelperCore
import SuperflowInferenceHelperProtocol
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import XCTest

final class InferenceHelperServiceTests: XCTestCase {
    private actor ManagedOnlyRuntime: LlamaRuntime {
        private(set) var deadlineMs: Int?
        private(set) var priority: CleanPriority?
        func load(modelURL: URL, compute: ModelCompute) async throws {}
        func complete(prompt: String, maxTokens: Int) async throws -> String {
            throw SuperflowError.invalidState("legacy completion lost the request budget")
        }
        func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion {
            self.deadlineMs = deadlineMs
            priority = CleanPriority.current
            return LlamaCompletion(text: "managed", generatedTokens: 7, hitTokenCap: true, prefillMs: 42, generationMs: 81)
        }
    }

    func testHelperUsesManagedRuntimeCompletion() async {
        let replied = expectation(description: "managed completion")
        let runtime = ManagedOnlyRuntime()
        let service = InferenceHelperService(runtime: runtime)
        service.complete(prompt: "fixture", maxTokens: 7, deadlineMs: 1_500,
                         interactive: true) { text, tokens, hitCap, prefill, generation, error in
            XCTAssertEqual(text, "managed")
            XCTAssertEqual(tokens, 7)
            XCTAssertTrue(hitCap)
            XCTAssertEqual(prefill, 42)
            XCTAssertEqual(generation, 81)
            XCTAssertNil(error)
            replied.fulfill()
        }
        await fulfillment(of: [replied], timeout: 1)
        let deadline = await runtime.deadlineMs
        let priority = await runtime.priority
        XCTAssertEqual(deadline, 1_500)
        XCTAssertEqual(priority, .interactive)
    }

    func testCompletionRejectsInvalidBudgets() {
        let service = InferenceHelperService(runtime: ManagedOnlyRuntime())
        for (tokens, deadline) in [(0, 1_500), (7, 0), (-1, -1)] {
            service.complete(prompt: "fixture", maxTokens: tokens, deadlineMs: deadline,
                             interactive: false) { text, count, hitCap, _, _, error in
                XCTAssertNil(text)
                XCTAssertEqual(count, -1)
                XCTAssertFalse(hitCap)
                XCTAssertNotNil(error)
            }
        }
    }

    private actor FakeLlamaRuntime: LlamaRuntime {
        private var loaded = false
        private let loadError: String?
        private(set) var loadedCompute: ModelCompute?

        init(loadError: String? = nil) { self.loadError = loadError }

        func load(modelURL: URL, compute: ModelCompute) async throws {
            if let loadError { throw NSError(domain: "FakeLlamaRuntime", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: loadError]) }
            loaded = true
            loadedCompute = compute
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
        InferenceHelperService().prepareModel(atPath: "", gpu: true) { ok, message in
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
        InferenceHelperService().prepareModel(atPath: missing.path, gpu: true) { ok, message in
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
        service.prepareModel(atPath: file.path, gpu: true) { ok, _ in
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
        service.complete(prompt: "raw text", maxTokens: 100, deadlineMs: 30_000,
                         interactive: false) { text, _, _, _, _, error in
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
        service.prepareModel(atPath: file.path, gpu: true) { ok, message in
            success = ok
            reason = message
            replied.fulfill()
        }
        wait(for: [replied], timeout: 1)
        XCTAssertEqual(success, false)
        XCTAssertEqual(reason, "bad model")
    }

    /// The app's Settings choice crosses XPC as a flag, so the helper must
    /// hand the same choice to the llama.cpp runtime.
    func testPrepareForwardsTheComputeChoiceToTheRuntime() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-model-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let runtime = FakeLlamaRuntime()
        let service = InferenceHelperService(runtime: runtime)
        let gpuReply = expectation(description: "gpu load reply")
        service.prepareModel(atPath: file.path, gpu: true) { _, _ in gpuReply.fulfill() }
        await fulfillment(of: [gpuReply], timeout: 1)
        var compute = await runtime.loadedCompute
        XCTAssertEqual(compute, .gpu)

        let cpuReply = expectation(description: "cpu load reply")
        service.prepareModel(atPath: file.path, gpu: false) { _, _ in cpuReply.fulfill() }
        await fulfillment(of: [cpuReply], timeout: 1)
        compute = await runtime.loadedCompute
        XCTAssertEqual(compute, .cpu)
    }
}
