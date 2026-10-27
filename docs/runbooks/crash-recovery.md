# Crash recovery

## What is stored

The app stores session state in `~/Library/Application Support/Superflow/Superflow.sqlite` and audio journals under `~/Library/Application Support/Superflow/Journals/<session-id>/`. Each source has its own append-only manifest and 16 kHz mono Int16 PCM segments. The journal writer synchronizes about every five seconds and on close.

## Normal recovery

At launch, the app loads settings and starts model warm-up in a background task. After warm-up, `RecoveryEngine` scans SQLite for sessions left recording or finalizing. It replays audio after the last committed transcript sample, resumes pending cleanup, finalizes recoverable sessions, and removes the journal unless **Keep audio journals** is enabled. The app remains usable while this runs.

When text is recovered, the menu bar shows a notice and **Copy recovered text**. If recovery fails entirely, the incomplete database row and journal remain for a later retry. Meeting recovery can preserve a recovered source even when the other source fails; inspect the recovery notice before removing any journal.

## Manual inspection

1. Quit Superflow before inspecting or moving files.
2. Confirm the session is not active in SQLite. Do not alter a journal while the app is recording.
3. Inspect `<session-id>/<source>-manifest.jsonl` and the matching `<source>-NNNNNN.pcm` files. Segment files contain little-endian signed 16-bit samples at 16 kHz; the manifest records each segment's first sample.
4. Preserve a copy of both SQLite files (`Superflow.sqlite` and any `-wal`/`-shm` files) and the journal before manual repair.
5. Restart the app and check the menu bar recovery notice. Keep journals enabled only when preserving audio after successful recovery is intended.

Do not edit manifest entries or rename segment files by hand. If the journal must be discarded, quit the app and move the affected session directory out of `Journals`; retain the database until the user confirms the transcript is no longer needed.

## Privacy mode

No-transcript-storage suppresses transcript rows and text updates. Session metadata remains so journal recovery can identify interrupted work. Recovered text is held for the menu bar copy action and is not written as a transcript row.
