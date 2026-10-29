import Foundation

extension IslandModel {
    func receiveNotice(_ notice: IslandNotice) {
        guard Date().timeIntervalSince(notice.postedAt) <= 120 else { return }
        let next = IslandReducer.reduce(phase, .notice(notice))
        if next == .notice(notice) {
            go(next)
        } else if pendingNotices.count < 4, !pendingNotices.contains(notice) {
            pendingNotices.append(notice)
        }
    }

    func schedulePendingNotice() {
        guard !pendingNotices.isEmpty else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.phase.isRest else { return }
            self.pendingNotices.removeAll { Date().timeIntervalSince($0.postedAt) > 120 }
            guard !self.pendingNotices.isEmpty else { return }
            self.go(.notice(self.pendingNotices.removeFirst()))
        }
    }
}
