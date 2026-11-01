import Foundation
import XCTest
@testable import SuperflowEnhancementDeepFilterNet

@MainActor
final class CompiledModelTests: XCTestCase {
    private actor Compiler {
        private(set) var calls = 0
        var shouldFail = false

        func setFailure(_ value: Bool) { shouldFail = value }

        func compile(_ package: URL) async throws -> URL {
            calls += 1
            if shouldFail { throw CocoaError(.fileReadCorruptFile) }
            await Task.yield()
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("compiled-model-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try Data("generation \(calls)".utf8).write(to: temporary.appendingPathComponent("model"))
            return temporary
        }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testNewCacheOwnerReusesCompilationFromThePreviousLaunch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = Compiler()
        for _ in 0..<2 {
            let cache = DeepFilterNetCompiledModel(cacheVersion: "v1", compile: { try await compiler.compile($0) })
            try await cache.prepare(in: root)
        }
        let calls = await compiler.calls
        XCTAssertEqual(calls, 1)
    }

    func testConcurrentRequestsCompileOnce() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = Compiler()
        let cache = DeepFilterNetCompiledModel(cacheVersion: "v1", compile: { try await compiler.compile($0) })
        async let first: Void = cache.prepare(in: root)
        async let second: Void = cache.prepare(in: root)
        _ = try await (first, second)
        let calls = await compiler.calls
        XCTAssertEqual(calls, 1)
    }

    func testRevisionChangePublishesTheNewCompiledBundle() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = Compiler()
        for revision in ["v1", "v2"] {
            let cache = DeepFilterNetCompiledModel(cacheVersion: revision, compile: { try await compiler.compile($0) })
            try await cache.prepare(in: root)
        }
        let model = root.appendingPathComponent("DeepFilterNet3-Streaming.mlmodelc/model")
        XCTAssertEqual(try String(contentsOf: model, encoding: .utf8), "generation 2")
    }

    func testMissingBundleIsRecompiledDespiteTheMarker() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = Compiler()
        let cache = DeepFilterNetCompiledModel(cacheVersion: "v1", compile: { try await compiler.compile($0) })
        try await cache.prepare(in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("DeepFilterNet3-Streaming.mlmodelc"))
        try await cache.prepare(in: root)
        let calls = await compiler.calls
        XCTAssertEqual(calls, 2)
    }

    func testFailedCompilationCanRetryWithoutPublishingAnIncompleteBundle() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = Compiler()
        await compiler.setFailure(true)
        let cache = DeepFilterNetCompiledModel(cacheVersion: "v1", compile: { try await compiler.compile($0) })
        do {
            try await cache.prepare(in: root)
            XCTFail("Expected compilation failure")
        } catch is CocoaError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("DeepFilterNet3-Streaming.mlmodelc").path))
        await compiler.setFailure(false)
        try await cache.prepare(in: root)
        let calls = await compiler.calls
        XCTAssertEqual(calls, 2)
    }
}
