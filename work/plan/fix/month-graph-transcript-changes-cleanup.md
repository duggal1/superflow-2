# Dashboard month graph, transcript changes, and cleanup tail

Root cause (graph): the dashboard draws a fixed 365-day year, so a new month's growth is lost in a wide grid.
Root cause (perf): cleanup fans out 3 GPU contexts the moment the mic opens, competing with latency-critical streaming ASR; every context also reserves a 4096-token KV cache.
Root cause (transcript): the meeting transcript shows cleaned text only; History already lists "What changed".

## Changes
1. `DashboardViewModel`: activity = 1st of the current month through the 15th of next month, every day included.
2. `ActivityYear`: square, device-pixel-snapped cells (no corner radius), month-named title, future days dust, empty days gap, hover readout, accessibility label names the month.
3. `MeetingDetail`: compact "What changed" disclosure under the turns, computed off-main from each turn's raw vs cleaned text.
4. `SessionCleanupCoordinator`: one cleanup worker while capture is live, fan out to the configured count on `finish()`.
5. `LlamaCppRuntime`: KV context 4096 to 2048 (max prompt + output is ~1500), fewer sessions by default.
6. S1-mini: keep the lists/semi-formal defaults and the existing safety gate; verify the pinned prompt and list output with a real model run.

## Verification
- FeatureDashboard tests for the new window, plus existing dashboard suite.
- SessionEngine tests for capture-time parallelism and the stop drain.
- Real S1-mini run (temp harness): 1/2/5-minute text timing, list output, no fallback regression.
- App build; do not stage the other worker's dirty files.
