# Cleanup backend verification

The production pipeline now uses deterministic spoken-code and reference number cleanup, list planning before the model, bounded priority scheduling, guarded retries, owned-word seam fallback, protected-aware final polish, Harper, and line formatting. TextCleaner remains unchanged. The fixed S1 prompt resource remains pinned.

Exact literal metadata continues through Protected. Tokenizer projects it into Word.protected and Word.glue before planning; dictionary matching does not need a second independent representation. Word timings travel through session and meeting contexts. ASRFluidAudio currently provides no word timings, so unknown pauses remain unset.

The old tests that asserted model-controlled list carry-over now assert deterministic item boundaries and constant prose controls. Stage-order tests reflect the explicitly requested order. Transcript goldens and safety thresholds were not loosened.

Numeric settings retain the existing small-number and large-number preferences. Western/Indian grouping is available through NumberCleanupStage's initializer. The implicit-lists preference uses the existing persisted cleanupStructure setting. A persisted Western/Indian grouping preference cannot be integrated while ownership of concurrent Settings.swift edits is unresolved. A question requesting authorization to integrate those edits is pending.

Live S1 inference preserved protected tokens and removed the supplied filler phrase. It also invented a slash in unprotected prose. The service rejects this and retains Tier-0 content. See ../results/live-model.md and the live service/soak report for measured results.

Spikes B–E on 200 owner dictations and the 100-dictation live golden are unmeasured because that corpus was not supplied. Keep the provisional 600/850 token limits. Synthetic examples do not calibrate model quality or justify changing worker counts.

Repository-wide lint currently fails on concurrent onboarding edits: an over-400-line view model, a direct Button, and a raw font size. The original TextNumbers package tests also contain an unrelated async XCTest-autoclosure compile error. The new reference number suite was run in an isolated temporary Swift package against the real module. No original concurrent edits were reverted, staged, or committed by this task.
