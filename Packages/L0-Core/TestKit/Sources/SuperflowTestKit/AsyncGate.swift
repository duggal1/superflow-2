import Foundation

/// A one-shot async gate for tests that need to hold a call inside an await.
/// `wait()` suspends until `open()` resumes every waiter; after that it returns
/// immediately, so a gated stream can be released once and never block again.
public actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var opened: Bool { isOpen }

    public func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
