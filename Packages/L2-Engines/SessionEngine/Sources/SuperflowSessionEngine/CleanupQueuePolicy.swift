/// Pure ordering rule for the cleanup queue.
///
/// Interactive push-to-talk rows jump ahead of queued background
/// meeting/dictation work so text the user is waiting on is not stuck behind a
/// long backlog. They never jump ahead of earlier interactive rows, which keeps
/// that class of work in submission order.
enum CleanupQueuePolicy {
    /// Index at which a new request should be inserted. `queued` holds the
    /// interactivity flag of every request already waiting, in drain order.
    static func insertionIndex(isInteractive: Bool, queued: [Bool]) -> Int {
        guard isInteractive, let firstBackground = queued.firstIndex(of: false) else {
            return queued.count
        }
        return firstBackground
    }
}
