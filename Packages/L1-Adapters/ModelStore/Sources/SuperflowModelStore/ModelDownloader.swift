import CryptoKit
import Foundation
import SuperflowKernel
import SuperflowPorts

/// The transfer layer. A model is one large file on a CDN that honours byte
/// ranges, so the default path splits it into parallel range requests, which is
/// what actually saturates a fast connection: one connection tops out well below
/// the link. Every transfer reports real bytes to `DownloadTelemetry`, so the UI
/// shows measured MB/s rather than a progress fraction pretending to be a speed.
///
/// When the server will not range, or the size is unknown, it falls back to one
/// ordinary streaming download.
public final class URLSessionModelDownloader: NSObject, ModelDownloading, @unchecked Sendable {
    private let chunkCount: Int
    private let minimumSegmentedBytes: Int64
    /// Only set by tests, which inject a stub protocol. Production uses the
    /// tuned ephemeral configuration built in `TransferSession`.
    private let configuration: URLSessionConfiguration?

    public init(chunkCount: Int = 8, minimumSegmentedBytes: Int64 = 8 * 1024 * 1024,
                configuration: URLSessionConfiguration? = nil) {
        self.chunkCount = max(1, chunkCount)
        self.minimumSegmentedBytes = minimumSegmentedBytes
        self.configuration = configuration
        super.init()
    }

    public func download(from url: URL, to destination: URL, expectedBytes: Int64?,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let probe = await TransferProbe.inspect(url, configuration: configuration)
        let total = probe.totalBytes ?? expectedBytes
        if probe.supportsRanges, let total, total >= minimumSegmentedBytes, chunkCount > 1 {
            do {
                try await SegmentedTransfer(url: url, destination: destination, total: total,
                                            chunkCount: chunkCount, configuration: configuration,
                                            progress: progress).run()
                return
            } catch SegmentedTransfer.Failure.rangeUnsupported {
                // The server answered a range request with the whole body; one
                // stream is the only correct transfer left.
            }
        }
        try await SingleStreamTransfer(url: url, destination: destination,
                                       expectedBytes: expectedBytes,
                                       configuration: configuration, progress: progress).run()
    }
}

/// The tuned session every real transfer uses: ephemeral (a model is not a web
/// page), long enough for a slow gigabyte, and ready for the parallel chunks.
enum TransferSession {
    static func make(_ injected: URLSessionConfiguration?,
                     maxConnections: Int = 1) -> URLSessionConfiguration {
        let configuration = (injected?.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 4
        configuration.httpMaximumConnectionsPerHost = maxConnections
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

// MARK: - probing

private struct TransferProbe: Sendable {
    var totalBytes: Int64?
    var supportsRanges: Bool

    static func inspect(_ url: URL, configuration: URLSessionConfiguration?) async -> TransferProbe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        let session = URLSession(configuration: TransferSession.make(configuration))
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return TransferProbe(totalBytes: nil, supportsRanges: false)
        }
        let length = http.expectedContentLength
        let ranges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "")
            .lowercased().contains("bytes")
        return TransferProbe(totalBytes: length > 0 ? length : nil, supportsRanges: ranges)
    }
}

// MARK: - parallel ranged transfer

// MARK: - single stream fallback

private final class SingleStreamTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let expectedBytes: Int64?
    private let configuration: URLSessionConfiguration?
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var session: URLSession?

    init(url: URL, destination: URL, expectedBytes: Int64?,
         configuration: URLSessionConfiguration?,
         progress: @escaping @Sendable (Double) -> Void) {
        self.url = url
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.configuration = configuration
        self.progress = progress
    }

    func run() async throws {
        DownloadTelemetry.shared.begin(label: destination.lastPathComponent,
                                       totalBytes: expectedBytes)
        defer { DownloadTelemetry.shared.end() }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let session = URLSession(configuration: TransferSession.make(configuration),
                                     delegate: self, delegateQueue: nil)
            lock.withLock { self.session = session }
            session.downloadTask(with: url).resume()
        }
        progress(1)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = expectedBytes ?? (totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        if let total, expectedBytes == nil { DownloadTelemetry.shared.expect(totalBytes: total) }
        DownloadTelemetry.shared.record(receivedBytes: totalBytesWritten)
        guard let total, total > 0 else { return }
        progress(min(0.99, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.success(()))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !finished else { return nil }
            finished = true
            let value = self.continuation
            self.continuation = nil
            return value
        }
        guard let continuation else { return }
        continuation.resume(with: result)
        lock.withLock {
            session?.finishTasksAndInvalidate()
            session = nil
        }
    }
}

