import Foundation

public enum RecoveryLedgerKind: String, Codable, Sendable, CaseIterable, Equatable {
    case started, watermark, segmentAppended, cleaned, finalized, journalDiscarded, journalRetained, needsUserAction
}

/// One durable, self-describing recovery event. `id` is the idempotency key: replay applies each
/// id at most once, so a crash between "record" and "act" cannot duplicate a side effect.
public struct RecoveryLedgerRecord: Codable, Sendable, Equatable {
    public var sequence: UInt64
    public var id: String
    public var kind: RecoveryLedgerKind
    public var session: String
    public var source: String?
    public var samplePosition: Int64?
    public var segmentIndex: Int?
    public var detail: String?

    public init(id: String, kind: RecoveryLedgerKind, session: String, source: String? = nil,
                samplePosition: Int64? = nil, segmentIndex: Int? = nil, detail: String? = nil,
                sequence: UInt64 = 0) {
        self.id = id
        self.kind = kind
        self.session = session
        self.source = source
        self.samplePosition = samplePosition
        self.segmentIndex = segmentIndex
        self.detail = detail
        self.sequence = sequence
    }
}

public enum RecoveryRecordDecode: Sendable, Equatable {
    case valid(RecoveryLedgerRecord)
    case truncated
    case corrupt
    case versionMismatch(UInt16)
}

public extension RecoveryRecordDecode {
    var isUsable: Bool {
        if case .valid = self { return true }
        return false
    }
}

public struct RecoveryLedgerIntegrity: Sendable, Equatable, Codable {
    public var valid: Int
    public var truncated: Int
    public var corrupt: Int
    public var versionMismatch: Int
    public var quarantined: Int

    public init(valid: Int = 0, truncated: Int = 0, corrupt: Int = 0,
                versionMismatch: Int = 0, quarantined: Int = 0) {
        self.valid = valid
        self.truncated = truncated
        self.corrupt = corrupt
        self.versionMismatch = versionMismatch
        self.quarantined = quarantined
    }

    public var isClean: Bool { truncated == 0 && corrupt == 0 && versionMismatch == 0 }
}

public struct RecoveryLedgerRead: Sendable, Equatable {
    public var records: [RecoveryLedgerRecord]
    public var integrity: RecoveryLedgerIntegrity
    public init(records: [RecoveryLedgerRecord] = [], integrity: RecoveryLedgerIntegrity = .init()) {
        self.records = records
        self.integrity = integrity
    }
}

/// Append-only, versioned, checksummed record log. Each record is its own atomically written file,
/// so a torn write can only ever damage one record and the rest of the history stays readable.
public actor RecoveryLedger {
    public static let currentVersion: UInt16 = 1
    private static let magic: [UInt8] = [0x53, 0x46, 0x52, 0x4c] // "SFRL"
    private static let headerLength = 28
    private let store: AtomicFileStore
    private var appliedIDs: Set<String> = []
    /// Cached so 120 appends do not re-read the whole log on every write.
    private var knownSequence: UInt64?

    public init(root: URL) {
        store = AtomicFileStore(root: root.appendingPathComponent("Records", isDirectory: true))
    }

    /// Writes the frame atomically. `crashAt` is for crash-point tests only.
    @discardableResult
    public func append(_ record: RecoveryLedgerRecord,
                       crashAt: AtomicWriteStage? = nil) throws -> UInt64 {
        if knownSequence == nil {
            knownSequence = (try read()).records.map(\.sequence).max() ?? 0
        }
        let sequence = (knownSequence ?? 0) + 1
        var stamped = record
        stamped.sequence = sequence
        let payload = try JSONEncoder().encode(stamped)
        let frame = Self.frame(payload: payload, sequence: sequence)
        try store.write(frame, named: Self.fileName(sequence: sequence, id: record.id), crashAt: crashAt)
        knownSequence = sequence
        return sequence
    }

    public func read() throws -> RecoveryLedgerRead {
        let fm = FileManager.default
        guard fm.fileExists(atPath: store.root.path) else { return RecoveryLedgerRead() }
        let files = (try fm.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "rec" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result = RecoveryLedgerRead()
        for file in files {
            let data: Data
            do { data = try Data(contentsOf: file) } catch {
                result.integrity.corrupt += 1
                continue
            }
            switch Self.decode(data) {
            case .valid(let record):
                result.records.append(record)
                result.integrity.valid += 1
            case .truncated:
                result.integrity.truncated += 1
            case .corrupt:
                result.integrity.corrupt += 1
            case .versionMismatch:
                result.integrity.versionMismatch += 1
            }
        }
        return result
    }

    /// Moves damaged records to `Quarantine/` so the user can inspect them; never deletes them.
    @discardableResult
    public func quarantineDamaged() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: store.root.path) else { return [] }
        let files = (try fm.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "rec" }
        var moved: [URL] = []
        for file in files {
            guard let data = try? Data(contentsOf: file), !Self.decode(data).isUsable else { continue }
            if let url = try store.quarantine(named: file.lastPathComponent) { moved.append(url) }
        }
        return moved
    }

    /// Applies each record once. A second call (or a restart followed by a call) is a no-op for
    /// ids that were already applied, even if the record file is still on disk.
    @discardableResult
    public func replay(handler: @Sendable (RecoveryLedgerRecord) async throws -> Void) async throws -> RecoveryLedgerRead {
        let result = try read()
        for record in result.records where !appliedIDs.contains(record.id) {
            try await handler(record)
            appliedIDs.insert(record.id)
        }
        return result
    }

    public var appliedCount: Int { appliedIDs.count }

    private static func fileName(sequence: UInt64, id: String) -> String {
        let safe = id.map { char in
            (char.isLetter || char.isNumber) ? char : "_"
        }.prefix(60)
        return String(format: "%020llu-%@.rec", sequence, String(safe))
    }

    private static func frame(payload: Data, sequence: UInt64) -> Data {
        var body = Data()
        body.append(contentsOf: magic)
        appendLE(currentVersion, to: &body)
        appendLE(UInt16(0), to: &body)
        appendLE(sequence, to: &body)
        appendLE(UInt32(payload.count), to: &body)
        let covered = body + payload
        appendLE(RecoveryChecksum.fnv1a(covered), to: &body)
        return body + payload
    }

    private static func decode(_ data: Data) -> RecoveryRecordDecode {
        guard data.count >= headerLength else { return .truncated }
        return data.withUnsafeBytes { raw -> RecoveryRecordDecode in
            guard Array(raw[0..<4]) == magic else { return .corrupt }
            let version = raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self).littleEndian
            guard version == currentVersion else { return .versionMismatch(version) }
            let length = Int(raw.loadUnaligned(fromByteOffset: 16, as: UInt32.self).littleEndian)
            guard raw.count >= headerLength + length else { return .truncated }
            guard raw.count == headerLength + length else { return .corrupt }
            let stored = raw.loadUnaligned(fromByteOffset: 20, as: UInt64.self).littleEndian
            let covered = Data(raw[0..<20]) + Data(raw[headerLength..<headerLength + length])
            guard RecoveryChecksum.fnv1a(covered) == stored else { return .corrupt }
            guard let record = try? JSONDecoder().decode(
                RecoveryLedgerRecord.self,
                from: Data(raw[headerLength..<headerLength + length])
            ) else { return .corrupt }
            return .valid(record)
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
