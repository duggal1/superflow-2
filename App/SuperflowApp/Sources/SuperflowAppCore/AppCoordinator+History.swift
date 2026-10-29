import SuperflowFeatureHistory
import SuperflowUIComponents

extension AppCoordinator {
    func makeHistoryModel() -> HistoryViewModel? {
        guard let environment else { return nil }
        return HistoryViewModel(
            repository: environment.transcripts,
            inserter: environment.textInserter,
            toast: ToastCenter(),
            pageSize: 40,
            onDeleteAudio: { session in await environment.audioArchive.delete(session: session) }
        )
    }
}
