<p align="center">
  <img src="docs/brand/superflow-banner.svg" alt="Superflow" width="340">
</p>

<h1 align="center">Superflow</h1>

<p align="center">
  <strong>There are plenty of AI dictation tools. This one is yours.</strong>
</p>

<p align="center">
  Fast, private, native dictation for macOS. Hold a key, speak, and keep working.
</p>


<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-171717?style=flat-square&labelColor=09090b&color=1d4ed8" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-171717?style=flat-square&labelColor=09090b&color=1d4ed8" alt="Swift 6">
  <img src="https://img.shields.io/badge/AI-on--device-171717?style=flat-square&labelColor=09090b&color=1d4ed8" alt="On-device AI">
  <img src="https://img.shields.io/badge/Electron-none-171717?style=flat-square&labelColor=09090b&color=1d4ed8" alt="No Electron">
</p>


Superflow turns speech into properly formatted text in the app you're already using. No separate editor, account, cloud transcription, or subscription service is needed for the local pipeline. It is built for actual writing: messages, documents, notes, prompts, technical terms, and code-aware text.

## What makes it different

- **Native, not Electron.** A Swift 6 and SwiftUI macOS app, with Rust used for the Harper grammar integration. No bundled Chromium UI.
- **Streaming by design.** Core ML recognition through FluidAudio emits partial transcripts as you speak. You don't have to wait until the end to see recognition progress.
- **Runs on your Mac.** Recognition, cleanup, formatting, and transcript storage are local after the models are downloaded. No account or telemetry endpoint.
- **Small, local text storage.** SQLite stores transcripts, history, dictionary entries, and settings. Transcript data is lightweight; optional saved audio and downloaded AI models take additional disk space.
- **Formatting beyond transcription.** Handles fillers, punctuation, spoken commands, numbers, dates, line breaks, lists, personal shortcuts, and protected terminology.
- **Made for the keyboard.** Text lands in the frontmost app, at your cursor. No copy-and-paste ritual.
- **A quiet interface.** Menu bar access, a compact recording island, a focused dashboard, and matching light and dark appearances.

## Dictation modes

| Mode | Gesture | Behavior |
| --- | --- | --- |
| **Push to talk** | Hold the dictation key | Speak while held; release to insert text. |
| **Hands-free** | Double-tap the dictation key | Keep dictating without holding a key; tap again to stop. |
| **Meeting** | Hold right ⌘ | Record microphone and system audio; tap right ⌘ again to finish. |
| **Cancel** | Press Escape while dictating | Discard the current take without inserting text. |

`Fn` is the default dictation key. You can choose another modifier during setup.

## Features

- **Live speech recognition:** Streaming ASR with partial and committed segments, including support for long takes.
- **On-device cleanup:** Removes disfluencies and improves punctuation and readability while aiming to preserve the original meaning.
- **Structured formatting:** Converts spoken numbers and dates, applies line formatting, and handles lists through an ordered text pipeline.
- **Developer-friendly dictation:** Preserves file paths, names, and code-aware spans, with optional code-speak handling.
- **Personal dictionary and shortcuts:** Protects your custom vocabulary and expands repeatable phrases.
- **Meeting capture:** Records microphone and system audio together; speaker separation is available when the diarization model is installed.
- **Searchable history:** Browse, search, copy, and revisit raw or cleaned transcripts, with optional audio playback.
- **Crash recovery:** Journals audio during capture so interrupted takes can be recovered on a subsequent launch.
- **Private by default:** Configurable transcript persistence and audio retention, with local export and deletion.
- **Local usage insights:** Tracks words, estimated time saved, streaks, and meeting duration without an analytics service.

## How it works

```text
Hotkey / gesture
       ↓
Microphone capture + recovery journal
       ↓
Streaming ASR (Core ML / FluidAudio)
       ↓
Deterministic text stages + local AI cleanup
       ↓
Insert at cursor → finalize in SQLite
```

The text pipeline applies spoken commands, shortcuts, disfluency handling, numbers and dates, protected dictionary terms, code-aware spans, grammar checks, and final line formatting. A language model is one part of that pipeline, not a substitute for the rest.

The cleanup model runs in an XPC helper process to isolate inference failures from the main app.

## Built natively

Superflow uses a layered set of Swift packages rather than a web application wrapped for desktop:

| Layer | Responsibility |
| --- | --- |
| `App/SuperflowApp` | App lifecycle, coordination, menu bar, and packaging |
| `Packages/L3-Features` | Dashboard, onboarding, history, meetings, settings, and SwiftUI screens |
| `Packages/L4-UI` | Design system, icons, and reusable UI components |
| `Packages/L2-Engines` | Session management, gestures, recovery, and text processing |
| `Packages/L1-Adapters` | Core ML, audio, SQLite, insertion, permissions, and model runtimes |
| `Packages/L0-Core` | Kernel types, protocols, and testing support |
| `Rust/harper-ffi` | Rust-backed Harper grammar integration |

The dependency direction is checked with `make deps-check`. Native UI and local inference avoid Electron's bundled browser runtime, although actual speed and memory usage depend on the hardware and models in use.

## Privacy and storage

- Transcription and cleanup run locally after model setup.
- Transcripts and preferences are stored in local SQLite rather than a hosted database.
- Transcript storage can be disabled; saved audio has its own retention setting and can be turned off.
- Temporary audio journals support recovery and are removed after successful finalization unless retention is requested.
- Models are downloaded on first use and can require **several gigabytes**. Lightweight transcript storage does **not** mean the complete AI installation is tiny.
- Microphone recording begins with an explicit user gesture.

## Build and run

**Requirements:** macOS 15+, Xcode 16 / Swift 6, and disk space for the local models. Apple silicon is recommended for streaming recognition.

```bash
git clone https://github.com/duggal1/superflow-2.git
cd superflow-2
make app       # Build dist/Superflow.app
make run       # Build and launch
make verify    # Build, tests, dependency check, and lint
```

For focused checks:

```bash
make test-fast
make test-models
make lint
make app-smoke
```

Model files are not committed to Git. See `docs/STATUS.md` for model details and development status.

## Project status

Superflow is under active development. Dictation, meetings, history, dictionary, shortcuts, and settings are implemented, while hardware performance and model choices continue to be evaluated. No unverified speed, memory, accuracy, or disk-space benchmarks are claimed here.

Start reading the code at `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator.swift`, then follow `GestureKit` → `SessionEngine` → `TextPipeline`.

## Acknowledgments

Superflow builds on [FluidAudio](https://github.com/FluidInference/FluidAudio), [llama.cpp](https://github.com/ggml-org/llama.cpp), [Harper](https://github.com/Automattic/harper), and the **S1-mini** cleanup model by Superwhisper. Licenses and third-party notices are in `docs/licenses/`.
