import Combine
import Foundation

@MainActor
public final class MeetingIntelligence: ObservableObject {
    public enum Phase: Equatable {
        case idle, thinking, streaming, done, truncated, failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var answer = ""
    @Published public var effort: ReasoningEffort = .low
    @Published public var mode: MeetingMode = .normal
    @Published public var screenAware = false
    @Published public var customInstructions = ""
    @Published public var background = ""

    private struct Request {
        let system: String
        let user: String
        var effort: ReasoningEffort
    }

    private let transcript: TranscriptBuffer
    private let client: ReflectionClient
    private let screen: ScreenReader
    private var job: Task<Void, Never>?
    private var generation = 0
    private var last: Request?
    private var lastTask: String?

    public init(client: ReflectionClient, transcript: TranscriptBuffer, screen: ScreenReader = ScreenReader()) {
        self.client = client
        self.transcript = transcript
        self.screen = screen
    }

    public var canGoDeeper: Bool { last?.effort.deeper != nil }

    public func help() { submit(task: Prompts.helpTask) }

    public func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        submit(task: Prompts.questionTask(question))
    }

    public func retry() {
        if let last { run(last) }
        else if let lastTask { submit(task: lastTask) }
    }

    public func goDeeper() {
        guard var request = last, let next = request.effort.deeper else { return }
        request.effort = next
        run(request)
    }

    public func cancel() {
        invalidate()
        answer = ""
        phase = .idle
    }

    public func clear() async {
        cancel()
        last = nil
        lastTask = nil
        background = ""
        await transcript.reset()
    }

    private func submit(task: String) {
        invalidate()
        last = nil
        lastTask = task
        answer = ""
        phase = .thinking
        let current = generation
        let system = Prompts.system(mode: mode, custom: customInstructions)
        let context = background
        let level = effort
        let captureScreen = screenAware
        job = Task {
            do {
                let screenText: String?
                if captureScreen { screenText = try await screen.readText() }
                else { screenText = nil }
                try Task.checkCancellation()
                let snapshot = await transcript.snapshot()
                guard generation == current, !Task.isCancelled else { return }
                let request = Request(system: system,
                                      user: Prompts.user(background: context, transcript: snapshot,
                                                         screen: screenText, task: task), effort: level)
                last = request
                await consume(request, generation: current)
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func run(_ request: Request) {
        invalidate()
        answer = ""
        phase = .thinking
        last = request
        let current = generation
        job = Task { await consume(request, generation: current) }
    }

    private func consume(_ request: Request, generation current: Int) async {
        do {
            var finished = false
            for try await event in client.stream(system: request.system, user: request.user, effort: request.effort) {
                guard generation == current, !Task.isCancelled else { return }
                switch event {
                case .thinking: break
                case .text(let text):
                    answer += text
                    phase = .streaming
                case .finished(let reason, _):
                    finished = true
                    switch reason {
                    case "length": phase = .truncated
                    case "stop": phase = answer.isEmpty ? .failed("No answer was returned. Try again.") : .done
                    case "content_filter": phase = .failed("The response was filtered. Try another question.")
                    default: phase = .failed("The response could not be completed. Try again.")
                    }
                }
            }
            if !finished { throw ReflectionError.incomplete }
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func invalidate() {
        generation += 1
        job?.cancel()
        job = nil
    }
}
