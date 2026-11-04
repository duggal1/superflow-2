import Foundation
import SuperflowKernel
import SuperflowPorts

extension SQLiteStore: LearningRepository {
    public func learningCandidates() async throws -> [LearningCandidate] {
        let statement = try db.prepare("""
        SELECT id, heard, canonical, app_scope, confidence, observations,
               state, created_at, updated_at
        FROM learning_candidates ORDER BY updated_at DESC LIMIT 500
        """)
        var result: [LearningCandidate] = []
        while try statement.step() {
            result.append(LearningCandidate(
                id: statement.text(0) ?? "",
                heard: statement.text(1) ?? "",
                canonical: statement.text(2) ?? "",
                appScope: statement.text(3),
                confidence: statement.double(4),
                observations: Int(statement.int(5)),
                state: LearningState(rawValue: statement.text(6) ?? "") ?? .suggested,
                createdAt: Date(timeIntervalSince1970: statement.double(7)),
                updatedAt: Date(timeIntervalSince1970: statement.double(8))
            ))
        }
        return result
    }

    public func saveLearningCandidate(_ candidate: LearningCandidate) async throws {
        let statement = try db.prepare("""
        INSERT INTO learning_candidates
        (id, heard, canonical, app_scope, confidence, observations,
         state, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            heard = excluded.heard, canonical = excluded.canonical,
            app_scope = excluded.app_scope, confidence = excluded.confidence,
            observations = excluded.observations, state = excluded.state,
            updated_at = excluded.updated_at
        """)
        try statement.bind([
            .text(candidate.id), .text(candidate.heard), .text(candidate.canonical),
            candidate.appScope.map(SQLValue.text) ?? .null,
            .real(candidate.confidence), .integer(Int64(max(1, candidate.observations))),
            .text(candidate.state.rawValue),
            .real(candidate.createdAt.timeIntervalSince1970),
            .real(candidate.updatedAt.timeIntervalSince1970),
        ])
        try statement.step()
    }

    public func deleteLearningCandidate(id: String) async throws {
        let statement = try db.prepare("DELETE FROM learning_candidates WHERE id = ?")
        try statement.bind([.text(id)])
        try statement.step()
    }
}
