import Foundation
import SuperflowKernel
import SuperflowPorts

final class SegmentedTransfer: @unchecked Sendable {
    enum Failure: Error {
        case rangeUnsupported
    }

    private let url: URL
    private let destination: URL
    private let total: Int64
    private let chunkCount: Int
    private let configuration: URLSessionConfiguration?
    private let progress: @Sendable (Double) -> Void
    private let partsDirectory: URL

    init(url: URL, destination: URL, total: Int64, chunkCount: Int,
         configuration: URLSessionConfiguration?,
         progress: @escaping @Sendable (Double) -> Void) {
        self.url = url
        self.destination = destination
        self.total = total
        self.chunkCount = chunkCount
        self.configuration = configuration
        self.progress = progress
        self.partsDirectory = destination.deletingLastPathComponent()
            .appendingPathComponent(".segments-\(UUID().uuidString)", isDirectory: true)
    }

    func run() async throws {
        DownloadTelemetry.shared.begin(label: destination.lastPathComponent, totalBytes: total)
        defer { DownloadTelemetry.shared.end() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: partsDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: partsDirectory) }

        let aggregate = TransferAggregate(total: total, progress: progress)
        let parts = (0..<chunkCount).map { index in
            partsDirectory.appendingPathComponent("part-\(index)")
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<chunkCount {
                let bounds = bounds(for: index)
                let part = parts[index]
                group.addTask { [self] in
                    try await transferChunk(index: index, bounds: bounds, partURL: part,
                                            aggregate: aggregate)
                }
            }
            try await group.waitForAll()
        }

        try assemble(parts: parts)
        progress(1)
    }

    private func bounds(for index: Int) -> ClosedRange<Int64> {
        let chunkSize = total / Int64(chunkCount)
        let start = chunkSize * Int64(index)
        let end = index == chunkCount - 1 ? total - 1 : start + chunkSize - 1
        return start...end
    }

    private func transferChunk(index: Int, bounds: ClosedRange<Int64>, partURL: URL,
                               aggregate: TransferAggregate) async throws {
        var attempt = 0
        while true {
            aggregate.reset(chunk: index)
            let transfer = ChunkTransfer(url: url, bounds: bounds, partURL: partURL,
                                         expected: bounds.upperBound - bounds.lowerBound + 1,
                                         configuration: configuration,
                                         onBytes: { aggregate.add($0, chunk: index) })
            do {
                try await transfer.run()
                return
            } catch ChunkTransfer.Failure.rangeUnsupported {
                throw Failure.rangeUnsupported
            } catch {
                attempt += 1
                guard attempt < 3, !Task.isCancelled else { throw error }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
    }

    /// Parts carry the bytes in order, so a plain concatenation is the file.
    private func assemble(parts: [URL]) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? output.close() }
        var written: Int64 = 0
        for part in parts {
            let data = try Data(contentsOf: part, options: .mappedIfSafe)
            try output.write(contentsOf: data)
            written += Int64(data.count)
        }
        guard written == total else {
            throw SuperflowError.modelUnavailable(
                "Transfer ended at \(written) of \(total) bytes")
        }
    }
}

final class TransferAggregate: @unchecked Sendable {
    private let total: Int64
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var perChunk: [Int: Int64] = [:]
    private var lastEmitNanos: UInt64 = 0

    init(total: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.total = total
        self.progress = progress
    }

    func add(_ delta: Int64, chunk: Int) {
        let sum = lock.withLock { () -> Int64 in
            perChunk[chunk] = (perChunk[chunk] ?? 0) + delta
            return perChunk.values.reduce(0, +)
        }
        DownloadTelemetry.shared.record(receivedBytes: sum)
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldEmit = lock.withLock { () -> Bool in
            guard now &- lastEmitNanos >= 100_000_000 else { return false }
            lastEmitNanos = now
            return true
        }
        if shouldEmit { progress(min(0.99, Double(sum) / Double(total))) }
    }

    func reset(chunk: Int) {
        lock.withLock { perChunk[chunk] = 0 }
    }
}

final class ChunkTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error {
        case rangeUnsupported
    }

    private let url: URL
    private let bounds: ClosedRange<Int64>
    private let partURL: URL
    private let expected: Int64
    private let configuration: URLSessionConfiguration?
    private let onBytes: @Sendable (Int64) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var sawRangeResponse = false
    private var finished = false
    private var writeError: Error?

    init(url: URL, bounds: ClosedRange<Int64>, partURL: URL, expected: Int64,
         configuration: URLSessionConfiguration?,
         onBytes: @escaping @Sendable (Int64) -> Void) {
        self.url = url
        self.bounds = bounds
        self.partURL = partURL
        self.expected = expected
        self.configuration = configuration
        self.onBytes = onBytes
    }

    func run() async throws {
        try? FileManager.default.removeItem(at: partURL)
        guard FileManager.default.createFile(atPath: partURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                var request = URLRequest(url: url)
                request.setValue("bytes=\(bounds.lowerBound)-\(bounds.upperBound)",
                                 forHTTPHeaderField: "Range")
                request.timeoutInterval = 120
                let session = URLSession(configuration: TransferSession.make(configuration),
                                         delegate: self, delegateQueue: nil)
                lock.withLock { self.session = session }
                session.dataTask(with: request).resume()
            }
        } onCancel: { [self] in
            finish(.failure(CancellationError()))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
            completionHandler(.cancel)
            finish(.failure(Failure.rangeUnsupported))
            return
        }
        sawRangeResponse = true
        if handle == nil {
            handle = try? FileHandle(forWritingTo: partURL)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handle else {
            writeError = CocoaError(.fileWriteUnknown)
            return
        }
        do {
            try handle.write(contentsOf: data)
            received += Int64(data.count)
            onBytes(Int64(data.count))
        } catch {
            writeError = error
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        if let error {
            finish(.failure(error))
        } else if let writeError {
            finish(.failure(writeError))
        } else if !sawRangeResponse {
            finish(.failure(Failure.rangeUnsupported))
        } else if received != expected {
            finish(.failure(SuperflowError.modelUnavailable(
                "Range \(bounds.lowerBound)-\(bounds.upperBound) ended at \(received) bytes")))
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
            session?.invalidateAndCancel()
            session = nil
        }
    }
}

