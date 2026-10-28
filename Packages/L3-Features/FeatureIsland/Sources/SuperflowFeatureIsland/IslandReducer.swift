/// Pure phase reducer. Every rule the Island obeys about state lives here.
public enum IslandReducer {
    public static func reduce(_ phase: IslandPhase, _ event: IslandEvent) -> IslandPhase {
        switch event {
        case .holdBegan:
            return .listening
        case .holdEnded:
            return phase == .listening ? .processing : phase
        case .cancelled:
            return phase.isBusy ? .idle : phase
        case .landed(let words):
            return phase.isBusy ? .landed(words: words) : phase
        case .pasteFailed(let transcript):
            return phase.isBusy ? .failed(transcript) : phase
        case .dismissed:
            return phase.isDismissable ? .idle : phase
        }
    }
}
