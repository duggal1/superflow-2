import Foundation
import SuperflowASRSherpaOnnx
import SuperflowModelStore
import XCTest

final class SherpaOnnxModelStoreTests: XCTestCase {
    func testCorruptArchiveNeverBecomesAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = SherpaOnnxModelStore(root: root, downloader: CorruptArchiveDownloader())

        do {
            try await models.prepare { _ in }
            XCTFail("A corrupt archive must fail integrity verification.")
        } catch {
            let available = await models.isAvailable()
            XCTAssertFalse(available)
        }
    }
}

private struct CorruptArchiveDownloader: ModelDownloading {
    func download(from url: URL, to destination: URL, expectedBytes: Int64?,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        try Data("incomplete archive".utf8).write(to: destination)
        progress(1)
    }
}
