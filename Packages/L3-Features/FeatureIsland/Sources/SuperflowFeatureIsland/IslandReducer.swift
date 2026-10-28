/// Pure phase reducer. Every rule the Island obeys about state lives here.
public enum IslandReducer {
    public static func reduce(_ phase: IslandPhase, _ event: IslandEvent) -> IslandPhase {
        switch event {
        case .holdBegan:
            return .listening
        case .handsFreeBegan:
            return .handsFree
        case .meetingBegan:
            return .meeting
        case .holdEnded:
            return phase.isBusy ? .processing : phase
        case .escapeCancelled:
            // IslandModel decides whether the Escape earns an undo card. By the
            // time the reducer sees this, the decision is already made.
            return phase.isBusy ? .idle : phase
        case .cancelled:
            return phase.isBusy ? .idle : phase
        case .landed(let words):
            return phase.isBusy ? .landed(words: words) : phase
        case .pasteFailed(let transcript):
            return phase.isBusy ? .failed(transcript) : phase
        case .notice(let notice):
            switch phase {
            case .failed, .undo, .recent:
                // A failure or a live undo owns the card. Never cover it.
                return phase
            case .idle, .hover, .listening, .handsFree, .meeting, .processing, .landed, .notice:
                return .notice(notice)
            }
        case .dismissed:
            return phase.isDismissable ? .idle : phase
        }
    }
}
