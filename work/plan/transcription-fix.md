# Plan: transcription fix + F12 AI-era lexicon + audio leveler
## Verified facts
- S1-mini must keep exact trained prompt; back to byte-identical + hashes.
- HAL: first channel only, Float32, AVAudioConverter high-quality to 16k mono once; no double resample, no AGC. Enhancer adds fixed 1.32x gain, peak cap 0.98.
- Nemotron 3.5 0.6B: 16k mono, 320ms chunks (ModelProfile). Mel/norm inside audio.cpp, unverified locally.
- audiocpp.h exposes generic model options, no hotwords/bias setter; STT bias = resolver-only until proven.
- Textract/Cloudflare/Next.js already Tier B-gated; Fable/Mythos generic families added.
## F12 (do now)
- ai-era-lexicon.json data (canonical, category, meaning, casing, variants, boost); seed vibe/agentic/AI terms.
- Loader + resolver stage pre+post cleanup, whole-token casing (AI/LLM/API/MCP/GPU).
- Fixture #3 target + casing + add-term-no-code-change tests.
## Audio (do now, WER honest)
- Root cause: no AGC, level depends on macOS input volume; gain 1.32x only.
- Add causal AGC leveler (-20 dBFS RMS target, fast attack, frozen silence, -1dBFS limiter) after denoise; toggleable. Single resample stays at HAL.
- WER with real clips needs user audio; report as not-verified, no invented numbers.
## Verify: TextPipeline, TextCleanup, AudioEnhancement, LLMLlamaCpp tests + lint.
