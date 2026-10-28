import Foundation
import XCTest
import SuperflowKernel
@testable import SuperflowProjectIndex

final class ProjectIndexerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testIndexesProjectRelativePaths() throws {
        try write("src/main.ts")
        try write("README.md")
        let context = try XCTUnwrap(ProjectIndexer().build(root: root, isCoding: true,
                                                           approvedByUser: true))
        XCTAssertEqual(context.root?.lastPathComponent, root.lastPathComponent)
        XCTAssertTrue(context.contains(relative: "src/main.ts"))
        XCTAssertTrue(context.paths.contains("src/"), "\(context.paths)")
        XCTAssertTrue(context.paths.contains("src/main.ts"), "\(context.paths)")
        XCTAssertTrue(context.paths.contains("README.md"), "\(context.paths)")
        XCTAssertTrue(context.isCoding)
        XCTAssertTrue(context.approvedByUser)
        XCTAssertTrue(context.paths.allSatisfy { !$0.hasPrefix("/") })
    }

    func testSkipsHeavyAndHiddenDirectories() throws {
        try write("src/main.ts")
        try write("node_modules/pkg/index.js")
        try write(".build/debug/artifact")
        try write(".hidden/secret.txt")
        let context = try XCTUnwrap(ProjectIndexer().build(root: root, isCoding: false))
        XCTAssertFalse(context.paths.contains { $0.hasPrefix("node_modules") })
        XCTAssertFalse(context.paths.contains { $0.hasPrefix(".build") })
        XCTAssertFalse(context.paths.contains { $0.hasPrefix(".hidden") })
    }

    func testDoesNotFollowSymlinks() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectIndex-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "escaped".write(to: outside.appendingPathComponent("secret.txt"),
                            atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: outside)
        let context = try XCTUnwrap(ProjectIndexer().build(root: root, isCoding: false))
        XCTAssertFalse(context.paths.contains { $0.contains("secret.txt") })
    }

    func testRespectsTheBound() throws {
        for index in 0..<40 { try write("src/file\(index).ts") }
        let context = try XCTUnwrap(ProjectIndexer().build(root: root, isCoding: false, limit: 5))
        XCTAssertLessThanOrEqual(context.paths.count, 5)
        XCTAssertLessThanOrEqual(context.paths.count, ProjectContext.pathLimit)
    }

    func testMissingRootReturnsNil() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertNil(ProjectIndexer().build(root: missing, isCoding: false))
    }

    func testDepthIsBounded() throws {
        try write("a/b/c/deep.ts")
        let context = try XCTUnwrap(ProjectIndexer().build(root: root, isCoding: false, maxDepth: 1))
        XCTAssertFalse(context.paths.contains("a/b/c/deep.ts"))
    }
}
