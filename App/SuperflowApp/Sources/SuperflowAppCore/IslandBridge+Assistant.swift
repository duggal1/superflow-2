import Foundation
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowMeetingIntelligence

/// The assistant half of the bridge: owns the intelligence session behind the
/// Island card. Kept beside `IslandBridge` so both files stay under the line
/// limit and each owns one side of the Island's state.
extension IslandBridge {
    /// Opens the assistant card immediately; the model load finishes behind it.
    /// A second press retries the ask instead of stacking cards.
    func openAssistant(environment: AppEnvironment) {
        assistantEnvironment = environment
        // A dismissed card leaves its job to finish; never stack two sessions.
        intelligence?.cancel()
        cancellables.removeAll()
        if model?.phase == .assistant {
            // Already open: refresh the ask instead of stacking cards.
        } else {
            model?.setAssistant(answer: "", status: .thinking, canDeeper: false)
            box.send(.assistantOpened)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.prepareAssistant(environment: environment)
        }
    }

    func closeAssistant() {
        intelligence?.cancel()
        cancellables.removeAll()
        model?.setAssistant(answer: "", status: .idle, canDeeper: false)
        box.send(.dismissed)
    }

    func prepareAssistant(environment: AppEnvironment) async {
        // Feed the buffer from the last stored transcript only. When storage is
        // off there is nothing to ask about, and no network call is made.
        guard let transcript = box.lastTranscript, !transcript.text.isEmpty else {
            model?.setAssistant(answer: "Dictate something first, then ask.",
                                status: .failed("Dictate something first, then ask."),
                                canDeeper: false)
            return
        }
        let intelligence = await makeIntelligence(environment: environment)
        guard let intelligence else {
            model?.setAssistant(answer: "Save your Reflection key in Intelligence to ask.",
                                status: .failed("Save your Reflection key in Intelligence to ask."),
                                canDeeper: false)
            return
        }
        self.intelligence = intelligence
        observe(intelligence)
        await intelligence.transcript.reset()
        await intelligence.transcript.ingest(speaker: .me, text: transcript.text, isFinal: true)
        syncSettings(intelligence)
        intelligence.help()
    }

    func makeIntelligence(environment: AppEnvironment) async -> MeetingIntelligence? {
        // Off the main actor so a busy Keychain can never freeze the press.
        let key = await Task.detached(priority: .userInitiated) { [creds = environment.assistantCredentials] in
            try? creds.load()
        }.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty,
              let url = URL(string: "https://api.reflection.ai/openai/v1") else { return nil }
        return MeetingIntelligence(client: ReflectionClient(apiKey: key, baseURL: url),
                                   transcript: environment.assistantBuffer)
    }

    func syncSettings(_ intelligence: MeetingIntelligence) {
        let defaults = UserDefaults.standard
        intelligence.effort = ReasoningEffort(
            rawValue: defaults.string(forKey: "intelligence.effort") ?? "low") ?? .low
        intelligence.mode = MeetingMode(
            rawValue: defaults.string(forKey: "intelligence.mode") ?? "normal") ?? .normal
        intelligence.screenAware = defaults.bool(forKey: "intelligence.screenAware")
        intelligence.customInstructions = defaults.string(forKey: "intelligence.customInstructions") ?? ""
    }

    func observe(_ intelligence: MeetingIntelligence) {
        cancellables.removeAll()
        let sink = { [weak self] in
            guard let self, let model else { return }
            let status: AssistantStatus = switch intelligence.phase {
            case .idle: .idle
            case .thinking: .thinking
            case .streaming: .streaming
            case .done: .done
            case .truncated: .truncated
            case .failed(let message): .failed(message)
            }
            model.setAssistant(answer: intelligence.answer, status: status,
                               canDeeper: intelligence.canGoDeeper)
        }
        intelligence.$phase.sink { _ in sink() }.store(in: &cancellables)
        intelligence.$answer.sink { _ in sink() }.store(in: &cancellables)
    }

    func assistantHelp() {
        intelligence?.help()
    }

    func assistantDeeper() {
        intelligence?.goDeeper()
    }

    func assistantRetry() {
        if let intelligence {
            intelligence.retry()
        } else if let environment = assistantEnvironment {
            // Nothing built yet (empty transcript or no key): rebuild from
            // scratch so Retry always does something visible.
            Task { [weak self] in
                guard let self else { return }
                await self.prepareAssistant(environment: environment)
            }
        }
    }
}
