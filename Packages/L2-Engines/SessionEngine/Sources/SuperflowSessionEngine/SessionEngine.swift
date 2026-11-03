import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

/// Dictation session state machine and orchestration. Raw segments are persisted the moment
/// ASR commits them; cleanup runs per segment in the background and only the final insert waits.
public actor SessionEngine {
    let audio: any AudioSource
    let enhancer: (any SpeechEnhancer)?
    let recognizer: any SpeechRecognizer
    var pipeline: TextPipeline
    let repository: any TranscriptRepository
    let journals: any JournalStore
    /// Internal so `SessionEngine+AudioPath` can open the archive lane.
    let archive: (any AudioArchiveStore)?
    let inserter: any TextInserter
    let metrics: MetricsSink
    let clock: TimeSource
    var settings: AppSettings
    /// Session-scoped project passed to the pipeline context. Never discovered by
    /// the text stages; nil means no filesystem scope is exposed.
    var project: ProjectContext?

    public nonisolated let events: AsyncStream<SessionEvent>
    let continuation: AsyncStream<SessionEvent>.Continuation

    var state: SessionState = .idle
    /// Serializes `start` across its awaits. The state machine only becomes
    /// active after the model and stream are ready, so without this a second
    /// call during that window could create a second recording.
    var isStarting = false
    var captureStopRequested = false
    var record: SessionRecord?
    var recognitionStream: (any RecognitionStream)?
    var writer: (any AudioJournalWriter)?
    var archiveWriter: (any AudioArchiveWriter)?
    var sampleTask: Task<Void, Never>?
    var eventTask: Task<Void, Never>?
    var recognitionTask: Task<Void, Never>?
    /// Recognition is fed from a bounded relay, never from the capture consumer.
    /// A model call that stalls must not stop levels, journaling or archiving.
    var recognitionFeed: AsyncStream<AudioChunk>.Continuation?
    var recognitionDrainTask: Task<Void, Never>?
    var cleanupCoordinator: SessionCleanupCoordinator?
    var warmTask: (id: UUID, task: Task<Bool, Never>)?
    /// The last transcript the OS refused to paste because Accessibility was
    /// off. Granting the permission retries this text instead of asking the
    /// owner to dictate it again. Never logged.
    var pendingInsertion: String?
    var nextIndex = 0
    var lastEndMs = 0
    var cumulativeTokenCount = 0
    var levelCounter = 0
    var latency = SessionLatency()
    let speculative = SpeculativePipeline()
    let speculativeCleanupEnabled: Bool
    var pipelineRevision = UUID()
    var recognitionOverflow = false
    var journalWarned = false
    /// True only after `begin()` succeeded for this session. A missing or broken
    /// DeepFilterNet must never fail dictation; the capture lane uses raw audio.
    var enhancementActive = false
    /// Worst case: modifier wait + key resolution + verify + AX fallback + re-verify.
    let insertionDeadline: Duration
    /// Bounded model waits. A Core ML call cannot be cancelled, so a deadline abandons the call
    /// and lets the session continue instead of wedging in `warming`/`finalizing` forever. The
    /// warm-up bound is generous because the first prediction on a cold machine pays the ANE
    /// specialization cost.
    let modelDeadline: Duration = .seconds(120)
    let finishDeadline: Duration = .seconds(20)

    public init(audio: any AudioSource, recognizer: any SpeechRecognizer, pipeline: TextPipeline,
                repository: any TranscriptRepository, journals: any JournalStore,
                inserter: any TextInserter, archive: (any AudioArchiveStore)? = nil,
                settings: AppSettings = .default, enhancer: (any SpeechEnhancer)? = nil, project: ProjectContext? = nil,
                metrics: MetricsSink = NoopMetrics(), clock: TimeSource = SystemTimeSource(),
                insertionDeadline: Duration = .seconds(8), speculativeCleanupEnabled: Bool = false) {
        self.audio = audio
        self.recognizer = recognizer
        self.enhancer = enhancer
        self.pipeline = pipeline
        self.repository = repository
        self.journals = journals
        self.archive = archive
        self.inserter = inserter
        self.settings = settings
        self.project = project
        self.metrics = metrics
        self.clock = clock
        self.insertionDeadline = insertionDeadline
        self.speculativeCleanupEnabled = speculativeCleanupEnabled
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    public var currentState: SessionState { state }
    public var currentSession: SessionRecord? { record }

    public func update(settings: AppSettings) async {
        pipelineRevision = UUID()
        self.settings = settings
    }

    /// Replaces the explicit project scope for the rest of the session. Cleanup
    /// rows already queued keep the scope they captured.
    public func update(project: ProjectContext?) async {
        pipelineRevision = UUID()
        self.project = project
    }

    /// Replaces the pipeline after a settings, dictionary or shortcut change.
    /// Segments already being cleaned keep the pipeline they captured.
    public func update(pipeline: TextPipeline, settings: AppSettings) async {
        pipelineRevision = UUID()
        self.pipeline = pipeline
        self.settings = settings
    }

    /// Promotes a speculative push-to-talk session to hands-free without
    /// interrupting capture.
    public func setMode(_ mode: SessionMode) {
        guard case .recording = state else { return }
        transition(.recording(mode))
    }

    func finalText(session: SessionID) async -> String? {
        do {
            return try await repository.transcriptTextForProcessing(session: session)
        } catch {
            emit(.notice("Could not load the final transcript: \(error.localizedDescription)"))
            return nil
        }
    }

    func resetBuffers() {
        nextIndex = 0
        lastEndMs = 0
        cumulativeTokenCount = 0
        levelCounter = 0
        recognitionOverflow = false
        journalWarned = false
        enhancementActive = false
        cleanupCoordinator = nil
    }

    func transition(_ next: SessionState) {
        state = next
        emit(.state(next))
    }

    func emit(_ event: SessionEvent) {
        recordLatency(event)
        continuation.yield(event)
    }

}
