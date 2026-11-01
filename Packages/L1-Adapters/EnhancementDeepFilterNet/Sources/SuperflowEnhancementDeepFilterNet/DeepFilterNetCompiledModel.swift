@preconcurrency import CoreML
import Foundation

actor DeepFilterNetCompiledModel {
    static let shared = DeepFilterNetCompiledModel()

    private let cacheVersion: String
    private let compile: @Sendable (URL) async throws -> URL
    private var preparing: [URL: Task<Void, Error>] = [:]

    init(cacheVersion: String = DeepFilterNetModelStore.revision + "\n"
            + ProcessInfo.processInfo.operatingSystemVersionString,
         compile: @escaping @Sendable (URL) async throws -> URL = {
             try await MLModel.compileModel(at: $0)
         }) {
        self.cacheVersion = cacheVersion
        self.compile = compile
    }

    func prepare(in directory: URL) async throws {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = preparing[directory] { try await existing.value; return }
        let task = Task { try await self.compileIfNeeded(in: directory) }
        preparing[directory] = task
        defer { preparing[directory] = nil }
        try await task.value
    }

    private func compileIfNeeded(in directory: URL) async throws {
        let files = FileManager.default
        let destination = directory.appendingPathComponent("DeepFilterNet3-Streaming.mlmodelc")
        let marker = directory.appendingPathComponent(".deepfilternet-coreml-version")
        if files.fileExists(atPath: destination.path),
           (try? String(contentsOf: marker, encoding: .utf8)) == cacheVersion { return }

        let package = directory.appendingPathComponent("DeepFilterNet3-Streaming.mlpackage")
        let compiled = try await compile(package)
        defer { try? files.removeItem(at: compiled) }
        let staging = directory.appendingPathComponent(".compiled-\(UUID().uuidString).mlmodelc")
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: compiled, to: staging)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: staging)
        } else {
            try files.moveItem(at: staging, to: destination)
        }
        try Data(cacheVersion.utf8).write(to: marker, options: .atomic)
    }
}
