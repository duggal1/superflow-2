SuperFlow: Native macOS Dictation and Meeting App, Master Build Plan

Working codename: Superflow (rename any time). Audience: the coding agent that builds this. Read the whole document before writing code.
0. Operating rules for the coding agent
1. Read design.md in the repo root before touching any UI. It is the source of truth for visual design. If it is silent on something, log the gap in docs/open-questions.md, pick the most conservative option, and continue.
2. Do not guess third-party APIs. Read the FluidAudio docs and source, the llama.cpp headers, and Harper's crate docs before writing adapters. Every adapter starts as a throwaway spike in Phase 0.
3. Pure native Swift (Swift 6, strict concurrency on). No Python in the shipped app. The only non-Swift code allowed is a tiny Rust C-ABI shim for Harper (section 11) and the vendored llama.cpp C library.
4. Extreme modularity from day one (section 4). One SwiftPM package per module, strict layers, protocols in a Ports package, tests in their own folders. If a change would blur a boundary, stop and write an ADR instead.
5. Phase 0 comes first. Several facts in the original brief were wrong or unverified (section 2). Record every decision as a short ADR in docs/adr/.
6. make verify must be green after every phase: build, unit tests, dependency-layer check, forbidden-pattern lint.
7. Privacy: everything is on-device. Never log transcript text or audio. Network use is limited to model downloads and an optional update check.
8. Degrade, never block. Any stage that fails or times out falls back to the previous stage's output, so the user always gets text.
1. Goal, requirements, non-goals
Goal: a local, private, extremely reliable dictation and meeting-transcription app for macOS (Wispr Flow / Willow Voice / Superwhisper class), built only in Swift, Apple Silicon only, macOS 15 or later.
Hard requirements
• Streaming ASR only, from day one. NVIDIA models only (no Apple speech models), run through FluidAudio on the Apple Neural Engine.
• Reliability means: a 1, 2, or 10 hour recording never loses audio, never crashes, never slows down, and stop-to-final-text takes seconds, not minutes.
• Raw ASR text goes through a deterministic Tier 0 layer, then S1-mini cleanup (llama.cpp), then a Harper grammar gate that is applied only when it demonstrably helps.
• Boring, reliable storage: SQLite in WAL mode for history and settings.
• Two UI surfaces: a draggable Dynamic Island pill (recording control) and a normal macOS main window.
Non-goals for v1: cloud anything, built-in AI summaries, Intel Macs, App Store distribution, non-English ASR or UI, mobile.
2. Verified facts and locked decisions (as of October 2026)
The original brief mixed correct and incorrect assumptions. These are the corrected facts. Anything marked UNVERIFIED must be resolved in Phase 0.
Brief assumed
What research found
Decision
Parakeet TDT 0.6B v3 can be the streaming model in FluidAudio
In FluidAudio, TDT v2 and v3 are batch models working on roughly 15 second windows. Streaming ASR there is Parakeet EOU 120M (English, 320 ms chunks, about 4.9% WER) plus a Nemotron streaming 0.6B model.
TDT v3 stays out of the live path. It may later serve as an optional offline re-pass for finished meetings.
nvidia/parakeet-unified-en-0.6b
Real. English RNN-T, one model for offline and streaming, minimum latency about 160 ms. NVIDIA recommends its Nemotron streaming model if you need 80 ms. UNVERIFIED: whether a Core ML build usable by FluidAudio exists.
Phase 0 spike A. If no Core ML build exists, do not convert it in v1; use the next profile.
nvidia/nemotron-3.5-asr-streaming-0.6b
No model with that name was found. Real names: nvidia/nemotron-speech-streaming-en-0.6b (English) and a multilingual nemotron-asr-streaming-multilingual-0.6b (about 40 languages) that FluidAudio supports.
Use the real IDs. Confirm exact Hugging Face repo IDs in Phase 0.
MLX forces Python or a heavy bridge
Wrong. MLX has a Swift package.
llama.cpp is still the pick because the official S1-mini artifact is GGUF. Hide it behind the TextCleaner port so MLX can be swapped in later.
S1-mini stops at 1000 tokens
UNVERIFIED in anything found.
Measure the real failure point in Phase 0 spike B. Chunk size comes from the measurement, not from this number.
Use S1-mini through the named Swift wrapper packages
Those wrappers were not verified.
Prefer vendoring llama.cpp's own Swift package or XCFramework behind our own thin bridge (roughly 300 lines). Decide in Phase 0.
Harper can just be added
Harper is a Rust library (harper-core, Apache-2.0) with a language server and JS/WASM bindings. No Swift package was found.
Build a small Rust static library with a C ABI, wrapped by a Swift package.
Custom vocabulary boosting can fix terms
FluidAudio's vocabulary boosting is not supported with streaming ASR.
Terms are fixed by post-processing dictionary stages, as the brief says.
S1-mini facts (from its public release notes): 0.6B Qwen3 fine-tune, English only, Apache 2.0 plus a naming clause, Q4_K_M GGUF is about 462 MB. Input is a fixed system prompt, then a control line, then the raw transcript. Thinking must be off (the assistant turn opens with an empty think block) and temperature must be 0. Copy the system prompt and control-line format verbatim from the model card into a resource file pinned by a hash test. Read its license before shipping.
3. Architecture overview
Layers. A package may only depend on layers below it.
• L0 Kernel and Ports: domain types and protocols. Depend on nothing.
• L1 Adapters: one package per external technology (AVAudioEngine, Core Audio tap, FluidAudio, llama.cpp, Harper, SQLite, CGEventTap, pasteboard). Each depends only on L0.
• L2 Engines: pure logic and orchestration (text stages, session engine, meeting engine, stats, recovery). Depend on L0 only, never on adapters.
• L3 Features: SwiftUI views plus view models, one package per feature. Depend on L0, L2 protocols and L4.
• L4 UI kit: design system, icons, shared components.
• L5 App: composition root. The only place that knows concrete types and wires adapters into engines.
Data flow
Mic and system audio, then ring buffer, then crash-safe journal on disk, then VAD segmenter, then streaming ASR, then raw text events, then Tier 0, Tier 1, Tier 2, line formatter, then insert into the focused app and save to SQLite.
Tiers
• Tier 0 (deterministic, under 5 ms, cannot fail): spoken commands, number and currency formatting, personal dictionary, tech dictionary, shortcuts, line formatter.
• Tier 1 (S1-mini): per-chunk cleanup with timeout and fallback.
• Tier 2 (Harper): grammar fixes behind a strict acceptance gate.
Two execution paths
• Short dictation (about 600 tokens or less): synchronous. Raw text passes through all tiers before pasting, under a hard latency budget (default 1.5 s). On timeout or error, paste the Tier 0 text.
• Long sessions (long dictation and meetings): pipelined. As soon as ASR commits a segment it is chunked and cleaned in the background while recording continues. At stop only the last chunk remains, so finish time is flat whether the recording is 5 minutes or 10 hours. The raw transcript is persisted immediately and the cleaned text replaces it when ready.
The pipelining is the real answer to the 10-hour requirement. Never design cleanup to run only after recording ends.
4. Repository layout and modularity rules
Superflow/
├─ design.md                        # visual source of truth (already in repo)
├─ Makefile                         # verify | build | test | lint | deps-check | soak
├─ docs/
│  ├─ adr/                          # 0001-asr-profile.md, 0002-llama-bridge.md ...
│  ├─ architecture/                 # module map, generated dependency graph
│  ├─ runbooks/                     # crash recovery, model cache repair, permissions
│  └─ open-questions.md
├─ tools/
│  ├─ check-deps/                   # fails CI on layer violations
│  ├─ lint-forbidden/               # pointer cursor, icon, print(), file size rules
│  ├─ gen-fixtures/                 # synthetic 1h and 10h audio generator
│  └─ Superflowctl/                    # headless CLI: audio file in, full pipeline, text out
├─ App/
│  ├─ Superflow.xcodeproj
│  ├─ SuperflowApp/                    # @main + composition root ONLY, zero logic
│  ├─ Resources/                    # asset catalog, Info.plist, entitlements
│  └─ InferenceHelper/              # XPC service target, empty until Phase 8
├─ Packages/
│  ├─ L0-Core/        Kernel/  Ports/  TestKit/
│  ├─ L1-Adapters/    AudioCapture/  SystemAudioCapture/  AudioJournal/
│  │                  ASRFluidAudio/  DiarizationFluidAudio/  LLMLlamaCpp/
│  │                  GrammarHarper/  StorageSQLite/  ModelStore/
│  │                  HotkeyEngine/  TextInsertion/  PermissionsKit/  Diagnostics/
│  ├─ L2-Engines/     TextCommands/  TextNumbers/  TextLexicon/  TextShortcuts/
│  │                  TextCleanup/  TextGrammarGate/  TextLineFormat/  TextPipeline/
│  │                  SessionEngine/  MeetingEngine/  StatsEngine/  RecoveryEngine/
│  ├─ L3-Features/    FeatureIsland/  FeatureDashboard/  FeatureHistory/
│  │                  FeatureDictionary/  FeatureShortcuts/  FeatureMeetings/
│  │                  FeatureSettings/  FeatureOnboarding/
│  └─ L4-UI/          DesignSystem/  Icons/  UIComponents/
└─ Tests/                           # cross-module tests only
   ├─ Integration/   E2E/   Performance/   Soak/   Golden/   Fixtures/
Inside every package:
TextCleanup/
├─ Package.swift
├─ Sources/TextCleanup/
│  ├─ Chunking/       # SentenceSplitter, TokenBudget, ChunkPlanner
│  ├─ Scheduling/     # CleanupPool, WorkerLease, Backpressure
│  ├─ Assembly/       # OrderedStitcher, SeamRepair
│  ├─ Safety/         # TruncationDetector, RetryPolicy, FallbackPolicy
│  └─ TextCleanup.swift   # public surface only
└─ Tests/TextCleanupTests/   # unit tests for this package, mirrors Sources layout
Rules (enforced by tools/check-deps and tools/lint-forbidden, not by good intentions)
1. One SwiftPM package per module. Package name equals folder name. Target names are prefixed Superflow (for example SuperflowTextCleanup).
2. Layer rule from section 3. Engines never import adapters. Features never import adapters. Only SuperflowApp imports concrete adapters.
3. All cross-module contracts are protocols in Ports. Every port ships with a fake in TestKit.
4. No folder named Utils, Helpers, Common, Misc, or Shared. Name folders by responsibility.
5. No more than about 10 files in a folder before it gets subfolders. One primary type per file. Soft limit 300 lines per file, hard limit 400.
6. No logic in SwiftUI views. Views render state and forward intents; view models own behavior.
7. No singletons, no global mutable state, no NotificationCenter for internal events. Constructor injection only.
8. Tests live in their own folders: per-package unit tests under Tests/<Package>Tests, and cross-module Integration, E2E, Performance, Soak, Golden and Fixtures folders at the repo root. Test code never lives next to source files.
5. Module catalog
Module
Layer
Responsibility
Depends on
Kernel
L0
Value types (Session, Segment, Utterance, WordTiming, TranscriptDraft), IDs, errors, Clock
nothing
Ports
L0
Protocols: AudioSource, SpeechRecognizer, TextCleaner, GrammarChecker, TranscriptRepository, SettingsStore, HotkeySource, TextInserter, ModelProvider, SpeakerDiarizer, PermissionGate
Kernel
TestKit
L0
Fakes, builders, ReplayAudioSource, fixture loader (tests only)
Kernel, Ports
AudioCapture
L1
Microphone via AVAudioEngine, 16 kHz mono conversion, ring buffer
Ports
SystemAudioCapture
L1
System audio via Core Audio process tap (ScreenCaptureKit fallback)
Ports
AudioJournal
L1
Crash-safe on-disk PCM journal and recovery reader
Ports
ASRFluidAudio
L1
FluidAudio streaming recognizers, model profiles, VAD
Ports
DiarizationFluidAudio
L1
Streaming speaker diarization
Ports
LLMLlamaCpp
L1
llama.cpp bridge and S1-mini adapter implementing TextCleaner
Ports
GrammarHarper
L1
Rust C-ABI shim plus Swift wrapper implementing GrammarChecker
Ports
StorageSQLite
L1
SQLite repositories, migrations
Ports
ModelStore
L1
Download, verify, cache and repair model files
Ports
HotkeyEngine
L1
CGEventTap, Fn and Command key gestures
Ports
TextInsertion
L1
Pasteboard plus simulated paste, Accessibility fallback
Ports
PermissionsKit
L1
Microphone, Accessibility, Input Monitoring, system audio status
Ports
Diagnostics
L1
os.Logger wrappers, signposts, local metrics (no network)
Kernel
Text* packages
L2
One text stage each (sections 9 to 12), plus TextPipeline composing them
Kernel, Ports
SessionEngine
L2
Dictation session state machine and orchestration
Kernel, Ports, TextPipeline
MeetingEngine
L2
Two-source meeting session, speaker labeling, export
Kernel, Ports, TextPipeline
StatsEngine
L2
Daily aggregates, streak, time saved
Kernel, Ports
RecoveryEngine
L2
Detect and rebuild interrupted sessions from the journal
Kernel, Ports
Feature*
L3
One feature each: view plus view model
L0, L2 protocols, L4
DesignSystem, Icons, UIComponents
L4
Tokens from design.md, Hugeicons wrapper, shared controls
Kernel
Key ports (sketch; keep them small and stable)
• AudioSource: samples: AsyncStream<AudioChunk> (16 kHz mono Float32, sample-count timestamps), start(), stop(), events for route changes and failures.
• SpeechRecognizer: makeStream(profile) returns a stream with feed(chunk) and events: AsyncStream<RecognitionEvent> where an event is partial, committed segment, endpoint, or failure.
• TextCleaner: clean(chunk, options) async throws -> String, cancellable, with a per-call deadline.
• GrammarChecker: lint(text, protectedSpans) -> [Lint].
• TextInserter: insert(text, strategy) async throws.
• TranscriptRepository: append segment, finalize session, query history, delete, export.
6. Concurrency and runtime model
• Swift 6 language mode with complete strict concurrency. Actors for every long-lived component. @MainActor only for UI and view models.
• The audio render callback must not allocate, take locks, log, or touch Swift concurrency. It copies samples into a pre-allocated single-producer single-consumer ring buffer. A consumer task drains it.
• Stages are connected by typed AsyncStreams with an explicit buffering policy and a bounded size. Unbounded buffers are a bug.
• Each session owns a structured Task tree. Cancel (Escape) cancels the tree; submit drains it.
• Inject Clock everywhere. Sample count is the source of truth for audio time; wall-clock is for display only.
• Start and stop of every component are idempotent and safe to call from any state.
7. Audio capture and journal
Microphone
• Keep the AVAudioEngine prepared at launch so recording starts in under 100 ms from key down. Do not keep the microphone open while idle.
• Capture begins on key down (speculative start; see section 14), so the first words are never lost.
• Convert to 16 kHz mono Float32 with FluidAudio's AudioConverter or AVAudioConverter.
• Survive engine configuration changes (AirPods connect, default device change, sample rate change) by rebuilding the engine without ending the session. Handle permission revocation mid-session by stopping cleanly and keeping what exists.
Journal (the reliability backbone)
• Every captured sample is written to disk before anything else consumes it. Format: Int16 PCM, 16 kHz mono, split into 60 second segment files, plus an append-only manifest.
• Writes happen on a dedicated serial queue. fdatasync about every 5 seconds and on segment close; full fsync at session end. Recovery must tolerate a torn last segment.
• Size: about 115 MB per hour, about 1.15 GB for 10 hours. Refuse to start below 3 GB free, warn below 1 GB, and if disk nearly fills mid-session keep transcribing and stop journaling with a visible warning. Never crash on a full disk.
• After the session transcript is committed and verified, delete the journal unless the user enabled retention.
• Meetings use two journals (mic and system) that share one session clock.
System audio (used by meeting mode)
• Primary: Core Audio process tap (macOS 14.2+ API) so no video capture permission is needed. Fallback: ScreenCaptureKit audio-only stream. Pick in Phase 0 spike D based on what works with Zoom and Meet on current macOS.
• Output is the same AudioSource port, so the rest of the system does not know where audio came from.

Reliability invariants and recovery
• Memory use is O(1) in recording length: never retain a whole recording or transcript in memory. Use bounded buffers; partial text and waveform updates are ephemeral UI data only.
• Persist committed raw transcript segments immediately. Durable audio and transcript data must not depend on an in-memory queue; after a restart, use the journal and SQLite state to identify work that needs replay or cleanup.
• On launch, RecoveryEngine scans sessions left recording or finalizing. Re-feed journaled audio that has no committed transcript through ASR, resume cleanup for committed raw segments, mark the session recovered, and show a non-blocking notice with the recovered text and a copy action.
• A failed or timed-out cleanup chunk falls back to its Tier 0 text and must not block later resolved chunks. Keep the existing bounded worker queue and per-chunk deadlines; never replace them with an unbounded in-memory queue.
• Treat these as release gates: a 10-hour real-time soak grows resident memory by less than 50 MB total after warm-up; accelerated and real-time runs produce matching transcript row counts; fault-injection recovery restores every journaled sample and committed transcript row, with at most the most recent 5 seconds at risk if not yet flushed. The full soak and performance assertions live in section 20.

8. ASR runtime
• ASRFluidAudio implements SpeechRecognizer on top of FluidAudio only. No other ASR library.
• Model profiles live in a registry: id, display name, repo, language, chunk size, streaming capability, verification status. Planned profiles: parakeetEOU120M (streaming, verified in FluidAudio), nemotronStreaming (verified in FluidAudio; confirm the English variant), parakeetUnified (only if Spike A finds a Core ML build). The default is chosen by a Phase 0 benchmark on recordings of the owner's real speech: latency to first partial, final accuracy, memory, CPU.
• Segment rotation keeps long sessions bounded. Use FluidAudio's Silero VAD. After at least 30 s of audio and a pause of at least 600 ms (or at a hard cap of 120 s), commit the segment, flush recognizer state, and start a fresh segment. Timestamps and ordering are owned by SessionEngine, not the recognizer.
• Watchdog: if VAD hears speech but no tokens arrive for 8 s, recreate the recognizer and replay uncommitted audio from the journal.
• Warm the model in the background at launch. The Island shows a warming state if the user records before it is ready. Never download models at record time.
• Meeting mode runs two recognizer streams at once (mic, system). Spike C verifies two concurrent streams fit the Neural Engine and memory budget; if not, fall back to a time-sliced single recognizer.
• Output is words with timings where available, so formatting, diarization alignment and export do not need a second pass.
9. Text pipeline: stage order and contracts
Every stage implements one small TextStage protocol: it takes a draft plus context and returns text, protected spans, and diagnostics. A stage never throws into the pipeline. On any failure it returns its input unchanged plus a diagnostic. TextPipeline builds the stage list from configuration, and the order is covered by a test.
Order for each committed segment or utterance
1. TextCommands: spoken commands such as new line and new paragraph (an addition to the brief; setting, default on, whole-phrase matches only).
2. TextShortcuts: if the utterance is a shortcut trigger, expand verbatim and short-circuit. Skip every later stage.
3. TextNumbers: spoken numbers and currency to written form.
4. TextLexicon: personal dictionary first, then the bundled tech dictionary.
5. TextCleanup: S1-mini via llama.cpp (section 10).
6. TextNumbers and TextLexicon again as an assertion pass. Deterministic stages run before the model so the model sees the user's preferred forms, and again after so the model cannot undo them.
7. TextGrammarGate: Harper behind the acceptance gate (section 11).
8. TextLineFormat (section 12).
Property tests every deterministic stage must pass: idempotent (running it twice equals running it once), never edits protected spans, never throws, stable on empty and whitespace-only input, output length bounded relative to input.
Numbers and currency (TextNumbers)
• FluidAudio documents a text-processing component (a Rust port of NVIDIA NeMo text processing, English included) for post-processing ASR output. Evaluate it in Phase 0 before writing your own. If it covers cardinals, currency and percentages and binds cleanly, wrap it behind the stage. Otherwise write a table-driven Swift implementation.
• Mirror the spoken form. Two hundred dollars becomes $200. Two hundred thousand dollars becomes $200k. Two million becomes $2M. Two point five million becomes $2.5M. One thousand two hundred fifty dollars becomes $1,250.
• Setting LargeNumberStyle: abbreviated (default; k, M, B when the speaker said thousand, million or billion and the value has at most three significant digits) or full ($200,000).
• Long bare digit strings from the ASR get thousands separators, except phone numbers, IDs, zip codes, version numbers and years.
• Also handle percentages (a hundred percent becomes 100%), years (twenty twenty-six becomes 2026), ordinals, and decimals. Keep zero through nine as words in plain prose unless followed by a unit, currency or percent (setting).
• Currency table is data-driven: USD, EUR, GBP, INR at launch. Add words like lakh and crore later through the same table.
• Never touch tokens that already contain digits, and never touch protected spans.
Dictionaries (TextLexicon)
• Entry model: id, kind (term or correction), triggers, canonical form, enabled, source (user or bundled). A term is a word the user wants spelled correctly. A correction maps what the model usually outputs to what the user wants.
• Matching: tokenized, whole-word, case-insensitive, multi-word triggers allowed, longest match wins, single pass using a trie (Aho-Corasick if the list is large). Output uses the canonical casing exactly as entered. For plain terms, match with case, spacing, hyphens and the word dot normalized away. No fuzzy or phonetic matching in v1.
• Bundled tech dictionary: Resources/tech-dictionary.v1.json, schema-validated, small and curated (roughly 150 entries at most: Next.js, TanStack Query, Tailwind and similar terms that models reliably get wrong). Every entry carries negative examples. CI runs all triggers over a bundled false-positive corpus of ordinary English and fails if any trigger fires.
• Users can disable any bundled entry individually.
• UI warns when a trigger is a common English word sequence (check against a bundled frequency list). The brief's own example, mapping next years to Next.js, would also rewrite normal English; the warning exists for exactly that.
• Dictionary terms are passed to Harper as custom dictionary words and as protected spans.
• Future, not v1: auto-learn from the user's manual corrections.
Shortcuts (TextShortcuts)
• Trigger normalization: lowercase, strip surrounding punctuation, map spoken dot to a period, and similarly slash and dash, collapse spaces. So design dot md and design.md both match.
• Default match mode: whole utterance only. Per-shortcut option: inline match on word boundaries.
• Expansion is inserted verbatim, multi-line markdown preserved, and skips cleanup, grammar and formatting. Content limit: 200 KB.
• Same collision warning as the dictionary for triggers made of common words.
10. Cleanup engine (S1-mini via llama.cpp)
Goal: reliable on 10-hour transcripts with bounded latency. S1-mini is the speed layer; correctness comes from the safety net around it.
Runtime
• Load one model per process (memory-mapped weights, all layers offloaded to Metal). One context per worker with a small n_ctx (start at 2048, shrink if measurement allows).
• Prompt assembly follows the model card exactly: fixed system prompt, control line, raw transcript. The prompt resource is pinned by a hash test. The control line only receives S1-mini's trained values: styling casual, semi-casual, semi-formal or formal; structure prose or lists; context general or email. App-level profile values (direct, code, prompt, chat, list, bullets) are clamped at this adapter boundary, so saved profiles stay unchanged while the model never sees an untrained value.
• Decode greedily with thinking off and size `max_new_tokens` to the input: `min(configured cap, 1.3 × input tokens + 32)`. The configured 1024 is a ceiling, not the normal request.
Chunk planner
• Count tokens with the model's own tokenizer, never with a character estimate.
• Size comes from Spike B: target about 55 to 60 percent of the measured safe limit. Until measured, use a soft target of 600 tokens and a hard cap of 850. The brief's 1000 token figure is an upper bound at best.
• Split preference: ASR committed-segment and VAD pause boundaries first, then sentence boundaries, then clause boundaries. Never mid-word, never inside protected spans, never merge two speakers' words in one chunk.
Scheduling
• CleanupPool actor with N workers over a bounded queue with backpressure. Do not assume linear speedup: parallel contexts share one Apple GPU. Benchmark N = 1, 2, 3, 4, 6, 8 and keep the value that maximizes throughput without raising p95 chunk latency (likely 2 to 4).
• Interactive requests (short dictation) jump ahead of background meeting chunks.
• Deadlines: interactive 1.5 s total, background 30 s per chunk. Everything is cancellable.
Safety net (this is what makes it reliable)
• TruncationDetector flags a result when: output is empty for content-bearing input (a filler/noise-only input legitimately returns an empty string and is stored as a successful `.cleaned` result); output-to-input word ratio is below a loose threshold (cleanup legitimately drops fillers, so start at 0.6 and tune on goldens); the last few input words are missing from the output; the output ends mid-sentence while the input did not; or generation hit the input-sized token cap.
• Retry policy: on a flag, split the chunk at the best boundary and retry each half, up to depth 3. After that, use the Tier 0 text for that chunk and mark it fallback in the database. A failed chunk must never block the stitch.
• Hallucination guard: output words must be explained by input words plus a small allowed set (digits, punctuation, contractions, spoken-form conversions like dot to a period or at to an at sign). Violations fall back to Tier 0. Tune the threshold on goldens.
• Every chunk records latency, tokens in and out, and outcome.
Stitching
• OrderedStitcher emits chunk i only after chunks 0 through i-1 are resolved (cleaned or fallback) and publishes progress for the UI.
• SeamRepair is deterministic: fix capitalization at seams, collapse double spaces, drop a duplicated word at the seam, add a missing sentence terminator when the next chunk starts a new sentence.
• No LLM post-pass in v1. The brief's optional consistency pass costs latency and risks drift for little gain.
Failure modes: if the model fails to load or crashes, the app runs Tier 0 only, shows a subtle basic-cleanup state in the Island, and logs it. The model stays resident while the app runs (setting to unload after idle).
11. Harper grammar gate (TextGrammarGate, GrammarHarper)
Harper is an offline English grammar checker written in Rust. The brief's rule is: use it only if it is elite, otherwise ignore it completely. That becomes a measurable acceptance gate, not a hope.
Integration
• Create Rust/harper-ffi (cargo crate, static library) exposing a minimal C ABI: create linter for a dialect, lint a UTF-8 buffer returning a list of lints, add custom dictionary words, free. Build it into an XCFramework with make harper. GrammarHarper wraps it as a Swift package with a binary target.
• Be explicit about offsets (bytes, characters, or UTF-16 units) in the C ABI and test with emoji and CJK text.
• Do not run Harper's language server as a subprocess; the FFI route is simpler and faster.
Gate policy (data in grammar-gate-policy.json)
1. Allowlist by lint kind. Start with spelling (never for dictionary or protected words), agreement, repeated words and a/an. Ignore style, word choice, readability and miscellaneous kinds in v1. Confirm the exact rule names from the crate.
2. Apply only lints that carry a suggestion, using the top suggestion. Skip any lint overlapping a protected span (dictionary terms, numbers, URLs, emails, code-like tokens).
3. Edit budget: if Harper wants to change more than 3 percent of the words in a chunk, ignore all its edits for that chunk. That pattern means the input is not what Harper expects.
4. Evidence: Tests/Golden/grammar holds about 200 dictation-style sentences with expected outputs. Measure precision per rule category. Any category below 98 percent precision ships disabled.
5. Idempotence: Harper run on its own output must apply zero edits.
6. Time cap: if linting a chunk takes more than 50 ms, skip it.
12. Line formatter (TextLineFormat)
Purpose: never show a wall of text. Pure, deterministic, idempotent.
Defaults from the brief, all settings: minWords = 25, preferredMax = 35, hardMax = 45, breakStyle = paragraph (blank line; the alternative is a single newline).
Algorithm
1. Split into sentences with a boundary detector that does not break on abbreviations (Dr., e.g., vs., U.S.), decimals, ellipses, URLs, emails, version numbers, or periods inside tokens like Next.js and design.md. A sentence ends at a period, question mark or exclamation mark followed by whitespace or end of text.
2. Accumulate sentences into the current block. After each sentence, if the block has at least 25 words, break. The first sentence end that lands the count between 25 and 35 wins. If the count already exceeds 35 but is at most 45, break there too.
3. If one sentence would push a block past 45 words without a terminator, break at the clause boundary (semicolon, then comma) nearest words 35 to 45 inside it. With no punctuation at all, hard-break at a word boundary near 45 as a last resort.
4. Existing newlines (from S1-mini lists, spoken commands, code fences) are hard boundaries: reset the counter, never reflow list items.
5. Do not leave a trailing block under 8 words when merging it into the previous block keeps that block under 45.
Streaming: the formatter keeps carry-over state (words since the last break) so a 30 minute dictation formatted incrementally produces output identical to formatting it all at once. This equivalence is a required test.
Other basic formatting in the same stage, each toggleable: capitalize sentence starts and standalone i; collapse repeated spaces; no space before punctuation and one after; trim trailing whitespace; add a final period unless the dictation is three words or fewer (so short search-box dictation stays clean); optional trailing space for continuous dictation into the same field.
13. Persistence
• SQLite through GRDB (one dependency; migrations, WAL, async access) behind the TranscriptRepository and SettingsStore ports. A hand-rolled sqlite3 wrapper is acceptable if the agent prefers zero third-party dependencies; record the choice in an ADR.
• Location: ~/Library/Application Support/Superflow/Superflow.sqlite. WAL mode, synchronous=NORMAL, foreign keys on, busy timeout set, one writer actor plus a reader pool.
• Migrations are versioned and each is tested forward from fixtures of every earlier schema. Back the file up before a migration. On launch run quick_check; if the database is corrupt, quarantine it, create a fresh one, and keep the app running.
• Tables: sessions (id, kind dictation or meeting, started and ended times, status, frontmost app bundle id, model profile, duration, word count, cleanup state); segments (session id, index, start and end ms, speaker id, source mic or system, raw text, cleaned text, cleanup state); speakers (session id, label, is_self); daily_stats (local day, words, audio ms, sessions); lexicon_entries; shortcuts; settings (key, JSON value). Add an FTS5 index over segment text for history search.
• Write path: raw text is written when a segment commits; cleaned text is updated when cleanup resolves. A crash can therefore never lose committed text.
• Settings for retention (auto-delete after N days) and a no-transcript-storage privacy mode.
14. Hotkeys, gestures and the session state machine
HotkeyEngine details
• Use two event taps. A passive listen-only tap watches modifier changes at all times. An active tap that can swallow Enter and Escape is installed only while a recording is in progress. Re-enable taps on timeout or user-input disable events, run a health check, and rebuild after sleep and wake.
• Needs Input Monitoring (listen) and Accessibility (active tap and synthetic events).
• Fn is detected through the secondary-function flag on modifier-change events (key code 0x3F). Right Command is key code 0x36 (left is 0x37). Confirm both in Spike F.
• macOS binds the Globe/Fn key to emoji, dictation or input switching by default. Onboarding must tell the user to set Keyboard settings, Press Globe key to, Do Nothing, and the app should detect the conflict and warn.
• Fn is cancelled as a gesture if any other key is pressed while it is down (Fn plus arrow, Fn plus F-keys must pass through). Right Command only counts when pressed alone; any key pressed while it is held aborts the gesture so Cmd+C and friends keep working.
Gestures (all timings live in GestureConfig, defaults below)
Gesture
Result
Hold Fn for at least 200 ms
Push-to-talk dictation; release submits
Double-tap Fn (two taps within 350 ms)
Hands-free dictation
Fn tap or Enter while hands-free
Submit
Escape while recording (either mode)
Cancel, discard, nothing pasted
Hold right Command alone for at least 600 ms
Start meeting recording, latched after release
Double-tap right Command
Start meeting recording
Right Command tap or Enter during a meeting
Submit and finalize
Escape during a meeting
Cancel
Speculative start: recording begins on the first key down, so no words are lost. If it was a single tap that no second tap follows inside the window, cancel silently and discard.
The gesture logic is a pure GestureRecognizer (state plus event plus timestamp in, actions out) with no OS dependencies, so every transition is unit-testable with synthetic event sequences. States: idle, armed, pushToTalk, awaitingSecondTap, handsFree, meetingArmed, meetingLatched.
SessionEngine states: idle, warming, recording(mode), finalizing, inserting, then complete, cancelled or failed. Model it as an enum with exhaustive switches so illegal transitions cannot compile. Every transition emits an event for the Island and Diagnostics, and each state has a hard timeout.
15. Text insertion (TextInsertion)
• Strategy order: (1) for a confidently editable control, Accessibility selected-text (then whole-value) replacement, which never touches the clipboard; (2) pasteboard plus synthetic Cmd+V when AX is unavailable, ambiguous or fails; (3) for `.unknown` containers, paste first and use Accessibility as the recovery path; (4) if both fail, leave the text on the clipboard and show a toast saying to paste manually. Text must never be lost; it is also saved to history regardless.
• Resolve the target at recording start, not only at insert time. `TextInserter.prepareForInsertion()` runs before model warm-up so Chromium/Electron apps build their Accessibility tree while the user speaks; the prepared PID expires after 30 s, is consumed by one insertion, and is invalidated when the frontmost app changes, when there is no frontmost app, or when the frontmost app is Superflow itself. It is also exposed for explicit invalidation on focus loss. Before pasting, re-check that the target is still frontmost.
• Inspect the focused element. A secure field is never written and never overwrites the clipboard; the Island copy card carries the text instead. An unambiguously non-editable control (button, list, Finder) skips the paste to avoid side effects; a settable `AXValue` does not make a slider, checkbox or button an editable text control. Ambiguous containers (`AXWindow`, `AXGroup`, `AXScrollArea`, web areas) still get a paste because a real field often sits underneath.
• Snapshot every pasteboard item and type first. Write the text marked as transient and concealed per the nspasteboard.org conventions so clipboard managers ignore it. Restore adaptively: 50 ms after a confirmed insertion, or 500 ms only when a posted chord was never observed. Restore is cancellable, and a new insertion flushes the pending restore before it snapshots the board. Only restore if the pasteboard change count shows nothing else wrote in between; never restore an incomplete snapshot or over a newer write.
• Resolve the key code for v from the current keyboard layout; do not hardcode the QWERTY value. Post the chord from a private event source with explicit Command flags after held modifiers are released, and stamp every synthetic event with `SyntheticInputMarker` so the hotkey taps ignore it.
• Verify the insertion by comparing the focused element's whole value against the expected value (baseline plus inserted text) within 400 ms; a changed character count is only the secondary signal for views that expose no value. An unverified paste falls back to Accessibility selected-text insertion (then whole-value replacement), also verified. A field that exposes neither a value nor a count is `unverifiable`, not a failure.
• Serialize insertions. A second request waits for the in-flight one and flushes its pending clipboard restore first, so rapid dictation cannot interleave pasteboard writes or restore an old transcript over a new one.
• Detect macOS Secure Input; it swallows synthetic keystrokes even with Accessibility granted. Skip the chord and try the Accessibility fallback.
• The Island is a non-activating panel so the target app keeps focus. Add an automated check that insertion goes to the app that was frontmost. A failed insertion builds its copy card from the finalized session transcript, never from the last partial segment.
• SessionEngine bounds insertion with an 8 s deadline. On timeout it calls `.clipboardOnly` before telling the user the text is on the clipboard, so the message is always true.
• Live insertion into any app in the brief is implemented in v1 as live partial text in the Island plus insertion of the final text on submit. A progressive mode that types committed segments as they arrive is a post-v1 experiment because it needs reliable replace and undo behavior across apps.
16. Meeting intelligence (MeetingEngine)
• Triggered by the right Command gestures in section 14. Meeting mode is its own engine and its own session kind; it shares the text pipeline and journal with dictation.
• Two sources: the microphone and system audio (Zoom, Meet, anything playing). Each has its own journal and its own recognizer stream on one shared sample clock.
• Speaker labeling: everything on the microphone channel is labeled You (or the custom name from Settings) by channel, with no diarization needed. Diarize the system channel only, producing Speaker 1, Speaker 2 and so on. Use FluidAudio's streaming diarization. Verify its speaker cap in Spike C: Sortformer-class models are typically limited to four speakers. Four remote speakers plus You covers the 2 to 5 person requirement.
• Echo: without headphones the microphone hears the speakers and produces duplicate lines. Mitigation order: recommend headphones in onboarding; dedupe by dropping a mic segment that overlaps in time with a system segment and has text similarity above about 0.8 (tune on fixtures); evaluate voice-processing echo cancellation in Spike D as an alternative.
• Turns: cleanup chunks align to speaker turns and never mix two speakers.
• Timeline: merge both streams by segment start time on the shared clock. Speaker names are renameable after the fact, with stable internal speaker ids.
• Failure behavior: if the system audio tap dies mid-meeting (permission, device change), continue microphone-only, record a visible gap marker in the transcript, and warn in the Island. Never end the meeting because one source failed.
• No length cap. Resource use must stay flat for a 3 hour meeting (same pipelined cleanup as long dictation).
• Export only, no built-in AI summary:
    ◦ Markdown: title, date, duration, participants, then one block per turn with speaker name and timestamp.
    ◦ JSON: schemaVersion, meeting metadata, speakers[], segments[] with start_ms, end_ms, speaker, text, raw_text.
    ◦ Buttons: Export Markdown, Export JSON, Copy as Markdown (made for pasting into Claude, Cursor or any coding agent). Golden tests cover both formats.
17. Feature specifications
Dashboard (FeatureDashboard, StatsEngine)
• Total words: whitespace-delimited words in finalized dictation text.
• Time saved: max(0, words / typingWPM * 60000 - audioMs). typingWPM defaults to 40 and is configurable. Label it as an estimate.
• Average speed (words per minute): total words divided by total speaking minutes, where speaking time is VAD-detected speech, not wall-clock, so pauses do not drag it down.
• Day streak: consecutive local calendar days with at least one finalized dictation. Store the local day string at write time so time zone and daylight saving changes cannot corrupt it. If today has no dictation yet, show the streak through yesterday.
• Contribution graph: GitHub-style grid of 53 columns by 7 rows for the last 12 months, 5 intensity levels by quartile of daily words, tooltip on hover. Reads daily_stats only, so it is O(365) regardless of history size.
• Meetings are excluded from these dictation stats by default.
History (FeatureHistory)
• Full list with FTS5 search, pagination, keyboard navigation, one-click copy, one-click delete with an undo toast. A detail view toggles raw versus cleaned text (essential for debugging). Delete is a hard delete and adjusts daily_stats.
Dictionary and Shortcuts (FeatureDictionary, FeatureShortcuts)
• Add, edit, delete, search, import and export JSON. Two entry types for the dictionary (term, correction). Validation, plus the common-word collision warning from section 9. Shortcuts take a trigger, content and match mode.
Settings (FeatureSettings)
• Gesture timings and hotkeys, ASR model profile, cleanup on or off, Harper on or off, number style, line break parameters, typing speed, display name for meetings, launch at login, retention and privacy, diagnostics export.
Menu bar
• SwiftUI MenuBarExtra with Open App, Start or Stop, Settings, Quit. The Dock icon appears only while the main window is open.
18. UI and design
There are two separate surfaces with separate SwiftUI hierarchies: the Dynamic Island and the main window. Opening the main window never hides or destroys the Island.
18.1 Design system (DesignSystem, UIComponents)
• design.md in the repo root is the source of truth. Mirror its tokens (color, type, spacing, radius, elevation, motion) in DesignSystem, and keep a map in docs/architecture/design-token-map.md linking each token to its section in design.md. Never invent a token that design.md does not define; log the gap instead.
• Shared components (button, icon button, card, sidebar item, stat tile, contribution grid, search field, empty state, toast, toggle) live in UIComponents. Feature packages compose them and do not build raw controls.
• Every component supports light and dark mode (dark translucent is the priority), keyboard focus rings, VoiceOver labels, and reduce-motion.
18.2 Icons
• Hugeicons only. Do not use generic icon sets or SF Symbols, except where macOS itself requires a system symbol (for example standard menu items). The pasted Island brief mentions SF Symbols; that line is superseded by this one.
• Icons package: a typed HugeIcon enum with one case per used icon, SVGs exported into an asset catalog as template (single color) vector images, and one HugeIconView that handles size, weight and tint. Check Hugeicons' license tier and whether an official Swift distribution exists before bundling.
18.3 Cursor pointer rule
Every clickable element shows the pointing-hand cursor on hover. Models forget this, so it is enforced by construction:
• One pointerCursor() view modifier in UIComponents (push on hover enter, pop on hover exit and on disappear, with balanced calls). Disabled controls show the normal arrow.
• Every interactive component in UIComponents applies it internally, so features get it for free.
• tools/lint-forbidden fails the build on raw Button, onTapGesture or NSCursor calls in Feature packages, and on a NSCursor.push outside the modifier.
18.4 Dynamic Island (FeatureIsland)
Superseded by DESIGN.md §8.18 (Design Rebuild pass 4). The Island is rebuilt from scratch: one fixed 520 × 128 window flush at screen.frame.maxY, one notch-shaped silhouette that morphs between states, opaque black, no glass, no drag, no persisted origin, no `showIdlePill`. Geometry lives in NotchGeometry / IslandLayout / NotchShape; state in IslandReducer; the only boundary is the read-only IslandFeed port. See DESIGN.md §8.18 for the numbers.
18.5 Main window
• A normal resizable macOS window with standard controls, a sidebar and a content area of cards. Sidebar: Dashboard, History, Dictionary, Shortcuts, Meetings, Settings. Window state is restored across launches.
19. Permissions, onboarding and distribution
• Permissions: microphone, Accessibility, Input Monitoring, and system audio recording (lazily, at first meeting). PermissionsKit exposes live status streams and re-checks when the app becomes active. Verify each by exercising it (for example, the event tap actually installs), not by trusting a flag.
• Onboarding: welcome, permissions with deep links into System Settings, set the Globe key to Do Nothing, model download (resumable, checksum-verified, progress), a practice dictation in a sandbox text field, optional meeting setup.
• The app is not sandboxed (event taps, synthetic paste and process taps require that). Use the hardened runtime and a stable bundle id and signing identity from day one, because privacy grants are tied to the signing identity and break when it changes.
• Distribution: Developer ID signed and notarized DMG. Launch at login through SMAppService. Updates (for example Sparkle) are an ADR decision.
• Ship a third-party notices screen. Check the licenses of the NVIDIA models, S1-mini (Apache 2.0 with a naming clause), Harper, llama.cpp and FluidAudio before release.
20. Testing strategy
Tests live in their own folders (section 4, rule 8). Layers of tests:
• Unit (Packages/<Name>/Tests/<Name>Tests): pure logic, mirrors the Sources layout. Engines target at least 85 percent coverage. Text stages also get property tests (idempotence, protected spans, bounded growth).
• Contract (TestKit): each port has one contract suite (for example AudioSource: ordered chunks, idempotent stop, error events) that runs against the fake and against the real adapter.
• Golden (Tests/Golden): raw input to expected output, per stage: numbers/, lexicon/, shortcuts/, lineformat/, grammar/, cleanup/ (needs the model, tagged slow), meeting-export/. Updating goldens requires make golden-update and a reviewed diff.
• Integration (Tests/Integration): ReplayAudioSource into real ASR into the pipeline into a temp SQLite database and a fake inserter.
• E2E (Tests/E2E): XCUITest for the main window and Island drag, click-to-expand and context menu. Gesture logic is tested through the pure GestureRecognizer with synthetic event streams; keep a short manual checklist for real Fn and Command hardware.
• Performance (Tests/Performance): baselines for key down to audio flowing, stop to paste, cleanup tokens per second, and N-worker scaling. Fail on a regression above 15 percent.
• Soak (Tests/Soak): replay synthetic 1 hour audio nightly and 10 hour audio weekly (accelerated about 20 times, plus one real-time overnight run per release). Assert: journal sample count equals input sample count, 10-hour RSS growth under 50 MB total after warm-up, accelerated and real-time transcript row counts match, stop-to-final under 5 s, every chunk resolved, and database counts consistent.
• Fault injection (same folder): kill -9 mid-session then relaunch and recover every journaled sample and committed transcript row (at most the most recent 5 seconds may be unflushed); disk full; audio route change; ASR stall; llama crash and timeout; Harper timeout; system audio loss during a meeting.
• Fixtures (Tests/Fixtures): audio generated by tools/gen-fixtures from licensed speech clips or macOS speech synthesis. Keep large binaries out of git (generate on demand or use LFS).
• CI: split make test-fast (no models, runs everywhere) from make test-models (needs Neural Engine and Metal; run locally or on a self-hosted Apple Silicon runner).
21. Observability and performance budgets
• Logging with os.Logger, one category per module. Anything derived from user speech is marked private and is off by default. Signposts around every stage. A local ring buffer of metrics can be exported as a diagnostics bundle (no transcripts, no audio) from Settings. No network telemetry.
• Budgets (targets to validate in Phase 0 and Phase 8; change them only by ADR):
    ◦ Key down to audio flowing: under 100 ms at p95.
    ◦ Stop to text pasted for short dictation (up to 30 s of speech): under 700 ms at p50, under 1.5 s at p95, with the hard fallback at 1.5 s.
    ◦ Stop to final text for any session length: under 5 s.
    ◦ Idle CPU near zero. Recording CPU under 15 percent of one core, excluding the Neural Engine.
    ◦ 10 hour soak: RSS growth under 50 MB total after warm-up, zero lost journaled audio samples.
22. Build phases and acceptance criteria
Do the phases in order. Work inside a phase can be parallelized, especially the independent L1 adapters.
Phase 0: Spikes (throwaway code in spikes/, results recorded as ADRs).
• A. ASR availability and benchmark: Parakeet EOU 120M, Nemotron streaming, and Parakeet Unified (only if a Core ML build exists) through FluidAudio on the owner's own recordings. Pick the default profile.
• B. S1-mini: run through llama.cpp, then through the Swift bridge. Find the real truncation threshold, measure tokens per second, test parallel contexts N = 1 to 8, choose the wrapper.
• C. Two concurrent FluidAudio streams and diarization speaker cap.
• D. System audio capture (Core Audio tap versus ScreenCaptureKit) with Zoom and Google Meet; echo handling options.
• E. Harper FFI build; whether FluidAudio's text-processing component is usable for number formatting.
• F. Fn and right Command gestures through event taps on current macOS, including the Globe key setting conflict.
• Exit: six ADRs written and the section 2 table updated.
Phase 1: Skeleton. Repo, every package shell with Package.swift and one passing test, Kernel, Ports, TestKit fakes, Makefile, check-deps, lint-forbidden, DesignSystem tokens from design.md, Icons wrapper, CI. Exit: make verify green, dependency graph generated, and a deliberately bad import is rejected.
Phase 2: Audio, ASR, journal. AudioCapture, AudioJournal, ASRFluidAudio, a SessionEngine skeleton, and Superflowctl with transcribe file.wav and live. Exit: live transcript in the terminal; a 1 hour file replays in minutes; kill -9 mid-recording recovers from the journal.
Phase 3: Tier 0. TextCommands, TextNumbers, TextLexicon, TextShortcuts, TextLineFormat, with goldens and property tests. Exit: all golden suites green; incremental formatting equals batch formatting.
Phase 4: Tier 1 and Tier 2. LLMLlamaCpp, TextCleanup, TextGrammarGate, GrammarHarper. Exit: a 10 hour synthetic transcript is cleaned with every chunk resolved; injected llama crashes and timeouts fall back correctly; every enabled Harper category has at least 98 percent precision on the golden set.
Phase 5: Input, insertion, session, Island. HotkeyEngine, GestureRecognizer, TextInsertion, PermissionsKit, complete SessionEngine, FeatureIsland. Exit: hold Fn dictates into TextEdit, Notes, Slack, a browser, VS Code and Terminal; double-tap Fn is hands-free; Enter submits; Escape cancels; the Island never steals focus.
Phase 6: Storage and main window. StorageSQLite, StatsEngine, Dashboard, History, Dictionary, Shortcuts, Settings, Onboarding, menu bar. Exit: every feature in section 17 works and persists across relaunch.
Phase 7: Meeting. SystemAudioCapture, DiarizationFluidAudio, MeetingEngine, FeatureMeetings, export. Exit: a 60 minute real call produces correct You and remote labels and valid Markdown and JSON.
Phase 8: Hardening. Move ASR and LLM runtimes into the InferenceHelper XPC service behind the same ports, so a crash restarts the helper instead of the app. Add watchdogs, the full 10 hour soak, performance tuning, signing, notarization, update mechanism. Exit: all budgets in section 21 met.
Phase 9: Post-v1. Progressive insertion, auto-learn from corrections, larger tech dictionary, pause in the Island, retention polish.
23. Definition of done for v1
• Every feature in the brief works: dictation, dashboard and graph, history, personal dictionary, tech dictionary, number and currency formatting, shortcuts, meeting mode with export.
• make verify, the 1 hour soak and the 10 hour soak are green; no layer violations; no file over 400 lines.
• Kill -9, disk full, route change and ASR stall are all demonstrated to recover.
• Every clickable control shows the pointing-hand cursor; icons are Hugeicons only; visuals follow design.md.
• Signed, notarized build installs on a clean Mac and completes onboarding without manual steps beyond the permission prompts.
24. Open questions for the owner
The plan picks a default for each; change any of them without restructuring.
1. Meeting hold gesture: this plan latches after a 600 ms hold (since you submit with a Command tap). Alternative: hold-to-record only while held.
2. Idle Island: hidden when idle (default, matches your note). Alternative: optional idle pill.
3. Pause button on the Island: skipped in v1.
4. Live insertion: partials in the Island, final text pasted on submit. Alternative: progressive typing into the target app (post-v1).
5. Large numbers: $200k style by default; $200,000 is one setting away.
6. Line breaks: blank-line paragraphs by default; single newline is one setting away.
7. Meeting words counted in dashboard stats: excluded by default.
8. Default retention for journals and transcripts, and whether to ship a no-transcript-storage mode.
9. Product name (Superflow is only a codename).
25. References used for the facts in section 2
• FluidAudio: https://github.com/fluidinference/fluidaudio and https://docs.fluidinference.com/asr/getting-started.md
• Parakeet Unified: https://huggingface.co/nvidia/parakeet-unified-en-0.6b
• S1-mini GGUF: https://huggingface.co/superwhisper/s1-mini-GGUF and https://superwhisper.com/blog/s1
• S1-mini llama.cpp settings tutorial: https://aiindigo.com/tutorials/getting-started-with-superwhisper-s1-mini-gguf-local-high-fidelity-transcription
• Harper: https://github.com/Automattic/harper (repo link not fetched directly; Harper facts came from third-party binding pages)
Re-verify everything in section 2 in Phase 0; these projects move fast.