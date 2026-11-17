import Foundation
import SuperflowFeatureIntelligence
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowMeetingIntelligence
import SuperflowPorts
import SwiftUI

/// App-side assembly for the rebuilt Intelligence surface. It wires the new
/// `IntelligenceIslandModel` to the existing Reflection credentials, screen
/// reader, transcript buffer, prompt library and transcript repository. No
/// backend is rewritten: each is passed in through its existing contract.
///
/// Agent 1 hosts `content(for:)` inside the Island's compose / answer / settings
/// / history / suggestions states. The seam never opens a window or a popover.
@MainActor
public final class IntelligenceIslandSeam {
    public let model: IntelligenceIslandModel
    public let credentials: ReflectionCredentials
    public let answerService: ReflectionAnswerService
    public let transcript: TranscriptBuffer

    private let repository: any TranscriptRepository

    public init(credentials: ReflectionCredentials,
                transcript: TranscriptBuffer,
                repository: any TranscriptRepository,
                clipboard: @escaping @MainActor (String) -> Void) {
        self.credentials = credentials
        self.transcript = transcript
        self.repository = repository

        let answerService = ReflectionAnswerService(
            clientFactory: { [credentials] in
                // Off the main actor: a busy keychain must never stall the Island.
                let key = await Task.detached(priority: .userInitiated) {
                    try? credentials.load()
                }.value?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let key, !key.isEmpty,
                      let baseURL = URL(string: "https://api.reflection.ai/openai/v1") else { return nil }
                return ReflectionClient(apiKey: key, baseURL: baseURL)
            },
            transcript: transcript
        )
        self.answerService = answerService
        model = IntelligenceIslandModel(
            answerService: answerService,
            historyStore: RepositoryHistoryStore(repository: repository),
            copy: clipboard
        )
    }

    /// The SwiftUI surface for one Island slot. `AnyView` keeps FeatureIsland
    /// free of an L3 -> L3 dependency while it hosts the content.
    public func content(for slot: IntelligenceIslandSlot) -> AnyView {
        model.show(slot)
        return AnyView(IntelligenceContent(model: model))
    }

    /// The existing meeting engine's intelligence session, configured with the
    /// same screen-aware default and prompt theme as the typed surface. Kept
    /// here so the meeting flow still goes through `MeetingIntelligence`.
    public func makeMeetingIntelligence() async -> MeetingIntelligence? {
        let key = await Task.detached(priority: .userInitiated) { [credentials] in
            try? credentials.load()
        }.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty,
              let baseURL = URL(string: "https://api.reflection.ai/openai/v1") else { return nil }
        let intelligence = MeetingIntelligence(
            client: ReflectionClient(apiKey: key, baseURL: baseURL),
            transcript: transcript
        )
        intelligence.mode = MeetingMode(rawValue: model.selectedThemeID) ?? .normal
        intelligence.effort = model.effort
        intelligence.screenAware = model.screenAware
        intelligence.customInstructions = model.customInstructions
        return intelligence
    }

    /// Refreshes the store-backed history list from the Island.
    public func refreshHistory() async {
        await model.loadHistory(query: nil)
    }
}

// MARK: Agent 1's hosting protocol

/// Conforms to FeatureIsland's `IslandIntelligenceSeam`. Once Agent 1 injects a
/// seam into `IslandRoot`, the Island renders `SuperflowFeatureIntelligence`'s
/// compose and answer views and routes send/copy through these callbacks.
extension IntelligenceIslandSeam: IslandIntelligenceSeam {
    public func composeView(content: SuperflowFeatureIsland.IntelligenceContent,
                            onSend: @escaping (String) -> Void) -> AnyView {
        AnyView(HostedIntelligenceView(model: model, slot: .compose, content: content,
                                       onSend: onSend, onCopy: nil))
    }

    public func answerView(content: SuperflowFeatureIsland.IntelligenceContent,
                           onCopy: @escaping () -> Void) -> AnyView {
        AnyView(HostedIntelligenceView(model: model, slot: .answer, content: content,
                                       onSend: nil, onCopy: onCopy))
    }
}

private struct HostedIntelligenceView: View {
    @Bindable var model: IntelligenceIslandModel
    let slot: IntelligenceIslandSlot
    let content: SuperflowFeatureIsland.IntelligenceContent
    let onSend: ((String) -> Void)?
    let onCopy: (() -> Void)?

    var body: some View {
        SuperflowFeatureIntelligence.IntelligenceContent(model: model)
            .onAppear(perform: apply)
            .onChange(of: content.prompt) { _, _ in apply() }
            .onChange(of: content.answer) { _, _ in apply() }
            .onChange(of: content.isStreaming) { _, _ in apply() }
            .onChange(of: content.suggestions) { _, _ in apply() }
            .onChange(of: content.errorMessage) { _, _ in apply() }
    }

    private func apply() {
        model.applyHostContent(slot: slot,
                               prompt: content.prompt,
                               answer: content.answer,
                               streaming: content.isStreaming,
                               suggestions: content.suggestions,
                               errorMessage: content.errorMessage,
                               onSend: onSend, onCopy: onCopy)
    }
}
