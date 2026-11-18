import Foundation
import SuperflowKernel
import SuperflowPorts

/// One page of segments from a single session. `nextIndex` is the index to pass
/// back for the following page; `nil` means this was the last one. A page holds
/// at most `limit` segments, so memory stays O(page size) no matter how long the
/// session is.
public struct SegmentPage: Sendable, Equatable {
    public let segments: [Segment]
    public let nextIndex: Int?
    public var isLast: Bool { nextIndex == nil }

    public init(segments: [Segment], nextIndex: Int?) {
        self.segments = segments
        self.nextIndex = nextIndex
    }
}

/// Keyset (seek) pagination over a session's segments. Unlike OFFSET paging,
/// each page seeks straight to `idx > afterIndex` through the existing
/// `segments_session` index, so the cost of a page does not grow with the
/// number of segments already read.
public extension SQLiteStore {
    static let maximumSegmentPageSize = 1_000

    func segmentPage(session: SessionID, afterIndex: Int = -1,
                     limit: Int = 200) async throws -> SegmentPage {
        let cap = min(max(1, limit), Self.maximumSegmentPageSize)
        let statement = try db.prepare("""
        SELECT session_id, idx, start_ms, end_ms, speaker_id, source, raw_text, cleaned_text,
               cleanup_state, created_at
        FROM segments WHERE session_id = ? AND idx > ? ORDER BY idx LIMIT ?
        """)
        try statement.bind([.text(session.value), .integer(Int64(afterIndex)),
                            .integer(Int64(cap + 1))])
        var page: [Segment] = []
        page.reserveCapacity(cap)
        while page.count < cap {
            guard try statement.step() else { break }
            page.append(Self.segment(from: statement))
        }
        // One extra row (capped + 1) tells us there is a next page without
        // loading it into the result.
        let hasMore = try statement.step()
        return SegmentPage(segments: page, nextIndex: hasMore ? page.last?.index : nil)
    }

    /// An async sequence of pages for a whole session. Each element is bounded
    /// by `pageSize`, so a caller that renders or exports incrementally never
    /// materialises a multi-hour transcript in memory.
    func segmentPages(session: SessionID, pageSize: Int = 200) -> SegmentPageSequence {
        SegmentPageSequence(store: self, session: session, pageSize: pageSize)
    }
}

public struct SegmentPageSequence: AsyncSequence, Sendable {
    public typealias Element = SegmentPage

    public let store: SQLiteStore
    public let session: SessionID
    public let pageSize: Int

    public struct Iterator: AsyncIteratorProtocol {
        let store: SQLiteStore
        let session: SessionID
        let pageSize: Int
        var afterIndex = -1
        var finished = false

        public mutating func next() async throws -> SegmentPage? {
            guard !finished else { return nil }
            let page = try await store.segmentPage(session: session,
                                                    afterIndex: afterIndex,
                                                    limit: pageSize)
            if let next = page.nextIndex {
                afterIndex = next
            } else {
                finished = true
            }
            return page.segments.isEmpty ? nil : page
        }
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(store: store, session: session, pageSize: pageSize)
    }
}
