import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowModelStore

/// Serves a fixed payload and honours `Range`, so the parallel transfer is
/// exercised the way a CDN serves one large model file.
private final class RangeProtocol: URLProtocol {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var supportsRanges = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.payload
        let headers = ["Accept-Ranges": Self.supportsRanges ? "bytes" : "none"]
        if request.httpMethod == "HEAD" {
            respond(status: 200, headers: headers.merging(["Content-Length": "\(data.count)"]) { $1 },
                    body: Data())
            return
        }
        if Self.supportsRanges,
           let header = request.value(forHTTPHeaderField: "Range"),
           let bounds = Self.parse(header, total: data.count) {
            let slice = data.subdata(in: bounds)
            var responseHeaders = headers
            responseHeaders["Content-Length"] = "\(slice.count)"
            responseHeaders["Content-Range"] = "bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(data.count)"
            respond(status: 206, headers: responseHeaders, body: slice)
        } else {
            respond(status: 200, headers: headers.merging(["Content-Length": "\(data.count)"]) { $1 },
                    body: data)
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, headers: [String: String], body: Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status,
                                             httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Two loads per chunk: the delegate must stitch writes, not assume one.
        let half = body.count / 2
        if half > 0 {
            client?.urlProtocol(self, didLoad: body.prefix(half))
            client?.urlProtocol(self, didLoad: body.suffix(from: half))
        } else {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func parse(_ header: String, total: Int) -> Range<Int>? {
        guard header.hasPrefix("bytes=") else { return nil }
        let parts = header.dropFirst("bytes=".count).split(separator: "-")
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]),
              start >= 0, end >= start, end < total else { return nil }
        return start..<(end + 1)
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func record(_ value: Double) { lock.withLock { values.append(value) } }
    var all: [Double] { lock.withLock { values } }
}

final class RangeDownloaderTests: XCTestCase {
    private let payload = Data((0..<(1 << 20)).map { UInt8($0 % 251) })

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeProtocol.self]
        return configuration
    }

    private func destination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-range-\\(UUID().uuidString).bin")
    }

    override func tearDown() {
        DownloadTelemetry.shared.end()
        super.tearDown()
    }

    func testParallelChunksAssembleTheExactFile() async throws {
        RangeProtocol.payload = payload
        RangeProtocol.supportsRanges = true
        let downloader = URLSessionModelDownloader(chunkCount: 4, minimumSegmentedBytes: 1,
                                                   configuration: configuration())
        let url = destination()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = ProgressLog()

        try await downloader.download(from: URL(string: "https://models.test/model.bin")!,
                                      to: url, expectedBytes: Int64(payload.count),
                                      progress: { log.record($0) })

        XCTAssertEqual(try Data(contentsOf: url), payload)
        XCTAssertEqual(log.all.last, 1)
        XCTAssertTrue(log.all.allSatisfy { $0 >= 0 && $0 <= 1 })
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: url.deletingLastPathComponent().path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".segments-") })
    }

    func testFallsBackToASingleStreamWhenTheServerCannotRange() async throws {
        RangeProtocol.payload = payload
        RangeProtocol.supportsRanges = false
        let downloader = URLSessionModelDownloader(chunkCount: 4, minimumSegmentedBytes: 1,
                                                   configuration: configuration())
        let url = destination()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = ProgressLog()

        try await downloader.download(from: URL(string: "https://models.test/model.bin")!,
                                      to: url, expectedBytes: Int64(payload.count),
                                      progress: { log.record($0) })

        XCTAssertEqual(try Data(contentsOf: url), payload)
        XCTAssertEqual(log.all.last, 1)
    }
}
