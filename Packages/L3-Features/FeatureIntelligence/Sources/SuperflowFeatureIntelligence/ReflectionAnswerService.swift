import Foundation
import SuperflowMeetingIntelligence

/// Default answer service. Uses the existing `ReflectionClient` for streaming,
/// `ScreenReader` for on-by-default screen context, `TranscriptBuffer` for the
/// memory-only transcript and `Prompts` for the system/user envelopes. The
/// shared messy-transcript block is added through the task prompt.
@MainActor
public final class ReflectionAnswerService: IntelligenceAnswerServing {
    public var onEvent: ((IntelligenceAnswerEvent) -> Void)?

    private let clientFactory: @Sendable () async -> ReflectionClient?
    private let screen: ScreenReader
    public let transcript: TranscriptBuffer
    private var job: Task<Void, Never>?
    private var generation = 0
    private var last: IntelligenceAskRequest?

    public init(clientFactory: @escaping @Sendable () async -> ReflectionClient?,
                transcript: TranscriptBuffer,
                screen: ScreenReader = ScreenReader()) {
        self.clientFactory = clientFactory
        self.transcript = transcript
        self.screen = screen
    }

    public func ask(_ request: IntelligenceAskRequest) async {
        last = request
        await run(request)
    }

    public func retry() {
        guard let last else { return }
        Task { await run(last) }
    }

    public func goDeeper() {
        guard var request = last, let deeper = request.effort.deeper else { return }
        request.effort = deeper
        last = request
        Task { await run(request) }
    }

    public func cancel() {
        generation += 1
        job?.cancel()
        job = nil
    }

    private func run(_ request: IntelligenceAskRequest) async {
        cancel()
        let current = generation
        onEvent?(.thinking)
        job = Task {
            do {
                guard let client = await clientFactory() else {
                    onEvent?(.failed("Save your Reflection key in Intelligence to ask."))
                    return
                }
                let screenText: String?
                if request.screenAware {
                    screenText = try await screen.readText()
                } else {
                    screenText = nil
                }
                try Task.checkCancellation()
                guard current == generation else { return }
                let snapshot = await transcript.snapshot()
                let system = IntelligencePrompts.system(mode: request.mode, custom: "")
                let user = IntelligencePrompts.user(background: request.background,
                                                    transcript: snapshot,
                                                    screen: screenText,
                                                    task: request.task)
                var sawText = false
                var reason = "stop"
                for try await event in client.stream(system: system, user: user, effort: request.effort) {
                    guard current == generation, !Task.isCancelled else { return }
                    switch event {
                    case .thinking: break
                    case .text(let text):
                        sawText = true
                        onEvent?(.delta(text))
                    case .finished(let why, _): reason = why
                    }
                }
                guard current == generation else { return }
                if !sawText { onEvent?(.failed("No answer was returned. Try again.")) }
                else { onEvent?(.finished(reason)) }
            } catch {
                guard current == generation else { return }
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }
}
