# Streaming dictation replay

The headless executable feeds 16 kHz mono WAV audio into the real Nemotron streaming adapter and starts S1-mini through the production text pipeline and SessionEngine. It records the engine's stop-to-inserter-return metric, the number of segments already cleaned when input stops, and the number of model outputs accepted. The repository, journal, and insertion sink are in memory. No keyboard event, microphone, or target app is used.

```sh
swift build --package-path .proof/stream/Replay --jobs 1
.proof/stream/Replay/.build/debug/Replay fixtures/audio/01_min_technical_dictation.wav old 1 2 1
.proof/stream/Replay/.build/debug/Replay fixtures/audio/01_min_technical_dictation.wav latest 1 2 1
```

Arguments are WAV path, legacy or current path (use `old` for legacy), resident S1-mini contexts, playback acceleration, and repetitions. Use the existing local Nemotron and S1-mini models. The run writes raw fixture transcripts under this directory for comparison. Run cases sequentially on a memory-constrained Mac.
