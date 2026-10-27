# ADR 0013: Nemotron 3.5 v1 streaming profile

Status: Accepted

- The active 0.6B profile is NVIDIA `nvidia/nemotron-3.5-asr-streaming-0.6b` v1; the supplied plan’s claim that this repo does not exist is stale.
- Use FluidInference’s Core ML build `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML`, pinned to `1a41b75758b0337ff67db7d5408280aaaf23074e`.
- Download the English `latin/1120ms/` bundle because the existing profile and FluidAudio adapter use that path and tier.
- Do not substitute the English-only `nvidia/nemotron-speech-streaming-en-0.6b` model for 3.5; the owner’s latest instruction selects the exact multilingual v1 profile.
- Evidence: [NVIDIA model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) identifies v1; [FluidInference Core ML card](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML) documents FluidAudio loading and the `latin/1120ms` bundle.
