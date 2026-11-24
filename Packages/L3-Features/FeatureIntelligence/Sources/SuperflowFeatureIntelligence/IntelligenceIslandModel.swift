import Foundation
import Observation
import SuperflowKernel
import SuperflowMeetingIntelligence

/// Thin observable state for the rebuilt Intelligence surface. The App owns one
/// instance; Agent 1's Island hosts `IntelligenceContent` for each live slot.
/// All IO goes through the two injected seams, so headless tests use fakes.
@MainActor @Observable
public final class IntelligenceIslandModel {
    public private(set) var slot: IntelligenceIslandSlot = .compose
    public var input = ""
    public private(set) var answer = ""
    public private(set) var phase: IntelligenceAnswerPhase = .idle
    public private(set) var lastError: String?

    public private(set) var themes = IntelligenceTheme.allFromSource()
    public private(set) var selectedThemeID = "normal"
    public private(set) var screenAware = true
    /// Live TCC state, refreshed whenever settings or compose appear. Answers
    /// never wait on these: a missing permission only removes its signal.
    public private(set) var permissions: [IntelligencePermission: IntelligencePermissionStatus] = [:]
    public private(set) var effort: ReasoningEffort = .low
    public var customInstructions = ""
    public private(set) var settingsExpanded = false
    private var slotBeforeSettings: IntelligenceIslandSlot = .compose

    public private(set) var history: [IntelligenceHistoryItem] = []
    public var historyQuery = ""
    public private(set) var selectedHistory: IntelligenceHistoryItem?
    public private(set) var isLoadingHistory = false
    public private(set) var historyError: String?
    private var historyGeneration = 0
    @ObservationIgnored public var liveTranscriptProvider: (() async -> String)?

    public private(set) var suggestions: [String] = []
    public private(set) var pendingDetectedQuestion: String?
    public private(set) var meetingTranscript = ""

    public var selectedTheme: IntelligenceTheme {
        themes.first { $0.id == selectedThemeID } ?? themes[0]
    }

    private let answerService: any IntelligenceAnswerServing
    private let historyStore: any IntelligenceHistoryServing
    private let permissionsService: any IntelligencePermissionServing
    private let copy: @MainActor (String) -> Void
    private let defaults: UserDefaults
    private var answersBySession: [SessionID: [String]] = [:]
    private var priorSlot: IntelligenceIslandSlot = .compose

    /// Optional hooks set by an Island host so its own callbacks fire when the
    /// user sends or copies from this view. The model never owns a window.
    @ObservationIgnored public var onSend: ((String) -> Void)?
    @ObservationIgnored public var onCopy: (() -> Void)?

    public init(answerService: any IntelligenceAnswerServing,
                historyStore: any IntelligenceHistoryServing,
                copy: @escaping @MainActor (String) -> Void,
                defaults: UserDefaults = .standard,
                permissionsService: any IntelligencePermissionServing = NoopIntelligencePermissionService()) {
        self.answerService = answerService
        self.historyStore = historyStore
        self.permissionsService = permissionsService
        self.copy = copy
        self.defaults = defaults

        if let stored = defaults.string(forKey: "intelligence.mode"),
           themes.contains(where: { $0.id == stored }) {
            selectedThemeID = stored
        }
        if defaults.object(forKey: "intelligence.screenAware") != nil {
            screenAware = defaults.bool(forKey: "intelligence.screenAware")
        } else {
            defaults.set(true, forKey: "intelligence.screenAware")
        }
        effort = ReasoningEffort(rawValue: defaults.string(forKey: "intelligence.effort") ?? "low") ?? .low
        customInstructions = defaults.string(forKey: "intelligence.customInstructions") ?? ""

        answerService.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .thinking:
                answer = ""
                phase = .thinking
                lastError = nil
            case .delta(let text):
                answer += text
                phase = .streaming
            case .finished(let reason):
                phase = reason == "length" ? .truncated : .done
                storeAnswer()
            case .failed(let message):
                phase = .failed(message)
                lastError = message
            }
        }
    }

    // MARK: compose -> answer

    /// Switches the live Island state. The host calls this when the user enters
    /// compose / answer / settings / history / suggestions.
    public func show(_ slot: IntelligenceIslandSlot) {
        self.slot = slot
    }

    public func submit(_ explicit: String? = nil) async {
        let question = (explicit ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        onSend?(question)
        input = ""
        pendingDetectedQuestion = nil
        answer = ""
        lastError = nil
        let liveTranscript = await liveTranscriptProvider?() ?? meetingTranscript
        let request = IntelligenceAskRequest(
            question: question,
            task: IntelligencePrompts.askTask(question),
            transcript: liveTranscript,
            background: customInstructions,
            mode: mode(from: selectedThemeID),
            effort: effort,
            screenAware: screenAware
        )
        slot = .answer
        await answerService.ask(request)
    }

    public func cancel() {
        answerService.cancel()
        phase = .idle
        if slot == .answer { slot = .compose }
    }

    public func retry() { answerService.retry() }
    public func goDeeper() { answerService.goDeeper() }

    public func copy() async {
        guard !answer.isEmpty else { return }
        copy(answer)
        onCopy?()
    }

    /// Called by an Island host that owns its own content value. Keeps the
    /// model's rendered state in step with the host without any second store.
    public func applyHostContent(slot: IntelligenceIslandSlot,
                                 prompt: String, answer hostAnswer: String,
                                 streaming: Bool, suggestions hostSuggestions: [String],
                                 errorMessage: String?,
                                 onSend: ((String) -> Void)?, onCopy: (() -> Void)?) {
        show(slot)
        if !prompt.isEmpty, input.isEmpty { input = prompt }
        if !hostAnswer.isEmpty { answer = hostAnswer }
        if streaming { phase = .streaming }
        if !hostSuggestions.isEmpty { suggestions = hostSuggestions }
        if let errorMessage, !errorMessage.isEmpty {
            phase = .failed(errorMessage)
            lastError = errorMessage
        }
        self.onSend = onSend
        self.onCopy = onCopy
    }

    // MARK: shared messy-transcript intent path (PTT + meeting)

    public func ingestMeetingUtterance(_ text: String) async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSubstantive(value) else { return }
        meetingTranscript = String((meetingTranscript + "\n" + value).suffix(7_000))
        if IntelligenceQuestionDetector.looksLikeQuestion(value) {
            pendingDetectedQuestion = value
        }
    }

    private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "ah", "hmm", "you", "know", "like", "okay", "right", "well",
    ]

    private static func isSubstantive(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.contains { !fillerWords.contains($0) }
    }

    public func askDetectedQuestion() async {
        guard let question = pendingDetectedQuestion else { return }
        await submit(question)
    }

    // MARK: settings / themes

    public func toggleSettings() {
        settingsExpanded.toggle()
        if settingsExpanded {
            slotBeforeSettings = slot
            slot = .settings
        } else {
            slot = slotBeforeSettings
        }
    }

    public func selectTheme(_ theme: IntelligenceTheme) {
        selectedThemeID = theme.id
        defaults.set(theme.id, forKey: "intelligence.mode")
    }

    public func setScreenAware(_ value: Bool) {
        screenAware = value
        defaults.set(value, forKey: "intelligence.screenAware")
    }

    public func setEffort(_ value: ReasoningEffort) {
        effort = value
        defaults.set(value.rawValue, forKey: "intelligence.effort")
    }

    public func setCustomInstructions(_ value: String) {
        customInstructions = value
        defaults.set(value, forKey: "intelligence.customInstructions")
    }

    /// Reload after the app's credential/configuration page changes the shared defaults.
    public func reloadPreferences() {
        if let id = defaults.string(forKey: "intelligence.mode"),
           themes.contains(where: { $0.id == id }) { selectedThemeID = id }
        screenAware = defaults.bool(forKey: "intelligence.screenAware")
        effort = ReasoningEffort(rawValue: defaults.string(forKey: "intelligence.effort") ?? "low") ?? .low
        customInstructions = defaults.string(forKey: "intelligence.customInstructions") ?? ""
    }

    // MARK: permissions

    public func status(for permission: IntelligencePermission) -> IntelligencePermissionStatus {
        permissions[permission] ?? .notDetermined
    }

    public func refreshPermissions() async {
        permissions = await permissionsService.statuses()
    }

    /// Requests the grant first. Only when the OS did not grant it do we hand the
    /// user the exact Settings deep link — a "Fix" button always has a next step.
    public func fixPermission(_ permission: IntelligencePermission) async {
        let current = await permissionsService.request(permission)
        if current.isGranted {
            permissions[permission] = .granted
        } else {
            await permissionsService.openSettings(permission)
            await refreshPermissions()
        }
    }

    // MARK: history

    public func loadHistory(query: String? = nil) async {
        let raw = query ?? historyQuery
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        historyQuery = q
        historyGeneration += 1
        let generation = historyGeneration
        isLoadingHistory = true
        historyError = nil
        defer { if generation == historyGeneration { isLoadingHistory = false } }
        do {
            var items = try await historyStore.list(query: q.isEmpty ? nil : q, limit: 200)
            for index in items.indices {
                if let saved = answersBySession[items[index].id], !saved.isEmpty {
                    items[index].answers = saved
                }
            }
            guard generation == historyGeneration, !Task.isCancelled else { return }
            history = items
            // A list row holds only a preview; never replace an open full transcript with it.
        } catch {
            guard generation == historyGeneration, !Task.isCancelled else { return }
            historyError = "Could not load history. \(error.localizedDescription)"
        }
    }

    public func openHistoryItem(_ id: SessionID) async {
        do {
            guard var item = try await historyStore.detail(id: id) else { return }
            if let saved = answersBySession[id], !saved.isEmpty { item.answers = saved }
            selectedHistory = item
            priorSlot = slot
            slot = .history
        } catch {
            historyError = "Could not open this session. \(error.localizedDescription)"
        }
    }

    public func copyHistoryItem(_ id: SessionID) async {
        do {
            let item = try await historyStore.detail(id: id)
            guard let text = item?.fullText, !text.isEmpty else { return }
            copy(text)
        } catch {
            historyError = "Could not copy this session. \(error.localizedDescription)"
        }
    }

    public func deleteHistoryItem(_ id: SessionID) async throws {
        try await historyStore.delete(id: id)
        answersBySession[id] = nil
        if selectedHistory?.id == id { selectedHistory = nil }
        historyQuery = ""
        await loadHistory(query: "")
    }

    public func closeHistory() { selectedHistory = nil; slot = priorSlot }

    // MARK: post-meeting suggestions

    public func generateSuggestions() async {
        let request = IntelligenceAskRequest(
            question: "suggestions",
            task: IntelligencePrompts.suggestionsTask(),
            transcript: meetingTranscript,
            background: customInstructions,
            mode: mode(from: selectedThemeID),
            effort: effort,
            screenAware: screenAware
        )
        await answerService.ask(request)
        suggestions = Self.parseSuggestions(answer)
        if !suggestions.isEmpty { slot = .suggestions }
    }

    public func askSuggestion(_ question: String) async {
        await submit(question)
    }

    // MARK: helpers

    private func mode(from id: String) -> MeetingMode {
        MeetingMode(rawValue: id) ?? .normal
    }

    private func storeAnswer() {
        guard !answer.isEmpty, let target = selectedHistory?.id else { return }
        answersBySession[target, default: []].append(answer)
    }

    static func parseSuggestions(_ text: String) -> [String] {
        var result: [String] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let withoutNumber = line.replacingOccurrences(of: "^\\s*\\d+[\\).:-]?\\s*",
                                                          with: "", options: .regularExpression)
            let cleaned = withoutNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { result.append(cleaned) }
            if result.count >= 5 { break }
        }
        return result
    }
}
