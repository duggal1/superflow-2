# S1-mini quality and speed verification

The headless probe sends synthetic broken ASR text through the production text stages, CleanupService, and the installed Superwhisper S1-mini Q4_K_M model in llama.cpp. It records the model's completed calls and the service's acceptance events separately. The probe also exercises a genuine cold request before loading the model. The probe uses native GPU inference directly through the runtime. It does not open the packaged app.

The corpus checks literal paths, identifiers, money, times, negation, revisions, ordinary language near technical terms, quoted text, line breaks, Markdown list markers, and repeated phrases across chunk seams. Medium and long cases verify every batch ID and every repeated literal. The audio case uses streaming Nemotron output from the existing 30-second local fixture.

From the repository root, with the existing local models and audio.cpp CLI available:

```sh
swift build --package-path .proof/s1/Probe --jobs 1
ThirdParty/audio.cpp/build/macos-metal-release/bin/audiocpp_cli --task asr --family nemotron_asr --model .models/audio-cpp/nemotron-q8_0.gguf --backend metal --mode streaming --threads 2 --audio fixtures/audio/00_30s_technical_dictation.wav --request-option language=en-US --request-option lookahead_tokens=3 --log > .proof/s1/asr.log 2>&1
sed -n 's/^text_output=//p' .proof/s1/asr.log > .proof/s1/asr.raw
nice -n 12 .proof/s1/Probe/.build/debug/Probe .proof/s1/asr.raw > .proof/s1/trial.jsonl
python3 .proof/s1/check.py .proof/s1/trial.jsonl
```

The probe uses the production default context count unless `S1_SESSIONS` is set. Run trials sequentially on an 8 GB Mac. The validator expects the audio replay input as well as the synthetic corpus.
