import Foundation
import SuperflowKernel

public extension SQLiteStore {
    /// Finished sessions whose age (ended at, else started at) is past `cutoff`.
    /// Active recordings are never returned, matching the retention rule that
    /// an in-flight capture waits for a later pass. Keyset on the age column
    /// with a hard cap so a sweep cannot scan an unbounded history.
    func sessions(expiredBefore cutoff: Date, limit: Int = 500) async throws -> [SessionRecord] {
        let cap = min(max(1, limit), 5_000)
        let statement = try db.prepare("""
        SELECT \(Self.sessionColumns) FROM sessions
        WHERE COALESCE(ended_at, started_at) < ?
          AND status NOT IN ('recording', 'finalizing')
        ORDER BY COALESCE(ended_at, started_at) ASC LIMIT ?
        """)
        try statement.bind([.real(cutoff.timeIntervalSince1970), .integer(Int64(cap))])
        var result: [SessionRecord] = []
        result.reserveCapacity(cap)
        while try statement.step() { result.append(Self.session(from: statement)) }
        return result
    }
}
