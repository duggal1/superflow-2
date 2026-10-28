<p align="center">
  <img src="docs/brand/superflow-banner.svg" alt="Superflow — hold a key, speak, it types" width="880">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-2563EB?style=flat-square" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-2563EB?style=flat-square" alt="Swift 6">
  <img src="https://img.shields.io/badge/100%25-on--device-2563EB?style=flat-square" alt="100% on-device">
</p>

### Dictation that feels like typing.

Hold a key, say the thing, let go. The words appear in whatever app you were
already in — cursor where you left it, formatting intact, no window to manage.
Superflow is a macOS dictation app that runs the whole pipeline on your Mac:
speech recognition, cleanup and insertion. No account, no cloud, no telemetry.

It is built for the kind of writing people actually do at a keyboard — messages,
notes, tickets, prompts, code comments — and for the long tail of words a generic
model gets wrong: names, product terms, file paths, `camelCase` identifiers.

---

## How it feels

| Gesture | What happens |
| --- | --- |
| **Hold** the dictation key | Push-to-talk. Release and the text is inserted. |
| **Double-tap** the dictation key | Hands-free. Talk for as long as you like; tap once to stop. |
| **Press Escape** while dictating | Cancel the take. Nothing is inserted. |
| **Hold right ⌘** | Starts a meeting. Tap right ⌘ again to stop it. |

Fn is the default dictation key because it is already under your left thumb. If
you would rather use another modifier, setup lets you pick one — the gesture,
not the key, is what the rest of the app understands.

Everything visible is one small app: a menu-bar item, a dashboard, a notch
island while recording, and a settings window. There is no editor to live in and
no new workflow to learn.

## What is inside

- **Streaming dictation** — partial text arrives while you speak, so releasing
  the key feels like the end of a sentence, not the start of a wait.
- **Local cleanup** — a small on-device language model removes fillers, fixes
  punctuation and formats lists, without rewriting what you meant.
- **A text pipeline, not a prompt** — spoken commands, personal shortcuts,
  numbers and dates, your dictionary, code-aware spans and line formatting all
  run as deterministic stages around the model.
- **Meetings** — record microphone and system audio together, transcribe, and
  separate speakers when the diarization model is installed.
- **History** — every take, its raw and cleaned text, and (optionally) the audio
  behind it, searchable and copyable.
- **Recovery** — audio is journaled while you record. If the app or the machine
  dies mid-sentence, the take can be replayed instead of lost.
- **A real dictionary** — teach it the words it keeps missing; they are protected
  through cleanup.
- **Stats** — words, time saved, streaks and meeting time, computed locally.

## Architecture

Superflow is a set of Swift packages with a strict dependency direction. The app
is the composition root; everything below it is replaceable, testable, and
unaware of SwiftUI unless it is a feature.

```text
App/SuperflowApp          Composition root, coordinator, menu bar, packaging
        │
Packages/L3-Features      SwiftUI screens and their view models
        │                 Dashboard · History · Dictionary · Shortcuts
        │                 Meetings · Onboarding · Settings · Island
Packages/L4-UI            Design tokens, icons, reusable controls
        │
Packages/L2-Engines       Pure state machines and text stages
        │                 Session · Meeting · Recovery · Gesture · Stats
        │                 TextPipeline + its ordered stages
Packages/L1-Adapters      The outside world, behind ports
        │                 Core ML ASR · llama.cpp · audio · SQLite
        │                 key taps · permissions · journals · insertion
Packages/L0-Core          Kernel value types, port protocols, test doubles
```

The arrow only points one way. `L0` knows nothing about `L1`; engines do not
import AppKit; features do not open a database. `make deps-check` enforces this
with a dependency graph, so a shortcut through the layers fails the build instead
of quietly becoming architecture.

### One dictation, end to end

1. **Capture the gesture.** The hotkey adapter watches modifier flags and emits
   a key event. `GestureKit` turns that into a push-to-talk hold, a double-tap
   hands-free toggle, or a meeting.
2. **Open a session.** `SessionEngine` starts microphone capture, opens the audio
   journal, and streams fixed-size chunks to the recognizer.
3. **Recognize.** The ASR adapter runs Nemotron 3.5 streaming through Core ML /
   FluidAudio and emits partial and committed segments.
4. **Clean.** `TextPipeline` runs the stored text through its stages in order,
   with the local model only where language judgement is actually needed.
5. **Insert.** The insertion adapter writes into the frontmost app, then the
   session is finalized in SQLite and the island returns to idle.
6. **Recover if needed.** A take that never finalized is replayed from its
   journal the next time the app starts.

Long recordings rotate recognizer segments internally; a pause is not the end of
a dictation. Only the key coming up ends the take.

### The text pipeline

Order matters more than any single stage. Each one either improves the text or
returns it unchanged with a diagnostic — never a guess.

```text
spoken commands → personal shortcuts → disfluency collapse → numbers & dates
→ opt-in code speak → dictionary / protected spans → code-aware spans
→ local cleanup → numbers & dictionary assertion → grammar gate
→ line formatting
```

Stages are pure Swift where they can be, so they are cheap to test and easy to
reason about. The model is one stage, not the system. The cleanup model runs in
an XPC helper process, so a wedged model restarts the helper instead of taking
the app down with it.

## Design language

The interface is deliberately quiet: one accent (blue 600), SF Symbols only, a
4 pt pixel grid, no gradients and no decorative strokes. Depth is a fill step or
a second surface, never a shadow. The onboarding pixel field and the recording
island are drawn as whole cells so nothing lands on a half pixel. Motion is
short, one-shot and respects **Reduce Motion**; nothing loops in the background.

Dark and light are the same design, not two themes. Type is one UI face with two
weights; the display face is reserved for the few moments that deserve it.

## Privacy and data

- **On device by default.** Models are downloaded once and run locally. There is
  no account, no sync, no analytics endpoint.
- **You own the database.** Transcripts live in a local SQLite store. History,
  dictionary and settings can be exported or deleted.
- **Storage is a choice.** “Don’t store transcripts” skips transcript
  persistence. Audio retention is separate, defaults to one week, and can be
  turned off entirely.
- **Journals are temporary.** They exist to recover an interrupted take and are
  deleted when the session finalizes, unless you ask to keep them.
- **No hidden microphone.** Capture starts on an explicit gesture and stops when
  the take ends.

## Repository map

| Path | What lives there |
| --- | --- |
| `App/SuperflowApp` | App target, `AppCoordinator`, `AppEnvironment`, menu bar, windowing |
| `App/InferenceHelper` | XPC helper that owns the local model runtimes |
| `Packages/L0-Core` | `Kernel` value types, `Ports` protocols, `TestKit` fakes |
| `Packages/L1-Adapters` | ASR, LLM, audio capture, SQLite, hotkeys, model store, insertion |
| `Packages/L2-Engines` | Session, meeting, recovery, gesture, stats, text pipeline |
| `Packages/L3-Features` | One package per screen: dashboard, history, settings, … |
| `Packages/L4-UI` | `DesignSystem`, `Icons`, `UIComponents` |
| `Tests` | Golden transcripts, integration and soak suites |
| `tools` | Packaging, dependency check, forbidden-pattern lint, fixtures |
| `docs` | ADRs, architecture notes, runbooks, quality log, status |

## Build and run

Requirements: **macOS 15 or newer**, **Xcode 16 / Swift 6**, and enough disk for
the models (several GB on first run). Apple silicon is recommended for the
streaming path.

```bash
git clone https://github.com/duggal1/superflow-2.git
cd superflow-2

make app       # build and assemble dist/Superflow.app
make run       # assemble, then open the app
make verify    # build + all tests + dependency check + forbidden-pattern lint
```

Useful narrower commands:

```bash
make test-fast     # everything except the model-heavy packages
make test-models   # ASR, diarization, llama.cpp and grammar adapters
make lint          # dependency direction + forbidden patterns
make app-smoke     # package the bundle and check it launches
```

Models are not committed. The app downloads and verifies them on first use into
`.models/`; the checksums and sizes are in `docs/STATUS.md`.

### Tests

The suite is layered the same way as the code:

- **Golden** transcripts pin the text pipeline against real speech fixtures.
- **Integration** runs capture → recognition → cleanup → insertion with fakes at
  the hardware boundary.
- **Soak** replays long audio in accelerated and real time to catch journal,
  memory and finalization bugs that a unit test cannot see.
- **Package tests** cover engines, adapters and features individually.

## Status

Superflow is under active development. The dictation path, meetings, history,
dictionary, shortcuts and settings are implemented; model choices and performance
numbers are still being measured on real hardware. `docs/STATUS.md` is the honest
log — what works, what was discarded, and what is still blocked.

If you are reading the code for the first time, start at
`App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator.swift`, then follow one
event through `GestureKit` → `SessionEngine` → `TextPipeline`. That path explains
most of the repository.

## Credits

Superflow stands on excellent local-first work:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) for streaming ASR
  and diarization on Apple silicon.
- [llama.cpp](https://github.com/ggml-org/llama.cpp) for local model inference.
- [Harper](https://github.com/Automattic/harper) for the grammar gate.
- **S1-mini** by Superwhisper for the cleanup model.

Their licenses and notices are collected in `docs/licenses/` and shipped with
the app.
