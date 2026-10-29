# Dictation reliability

Work strictly P1 → P7; advance only after the preceding behavior is verified.
Preserve the visual design and unrelated dirty files. Commit explicit owned paths per priority.

P1: identify launch SQLite failure from files/logs and deterministic reproductions; protect history, serialize initialization/recovery, retain extended I/O diagnostics; test absent directories, stale sidecars, concurrent opens and interrupted writes; run isolated launch stress.
P2: profile actual model startup, then fix measured blocking/loading and measure cold/warm launches.
P3: observe persistence changes and verify History latency.
P4: derive live dictation statistics from sessions, test local calendar boundaries/streaks.
P5: trace audio capture/archive/player and verify real playback.
P6: guard loading/recording lifecycle, hammer early triggers and verify idle recovery.
P7: correct download action eligibility and inspect/resume slow transfer.

Initial P1 evidence: live local APFS database has quick_check=ok and 34 sessions; directory and files writable, no sandbox; 3.4 GiB free. Reported historical IOERR not yet reproduced. Factory currently quarantines on every error with ignored move failures, risking history loss. Existing actor serializes one connection and sets 5000 ms busy timeout.
