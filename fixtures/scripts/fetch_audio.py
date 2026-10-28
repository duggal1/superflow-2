#!/usr/bin/env python3
"""Fetch audio-only reference material and cut nested ASR fixtures.

Downloads ONLY an audio track from a source URL (no video stream is kept),
converts it to 16 kHz mono WAV, then derives nested fixtures:

    30 min  -> first 30:00 of the reference window
    10 min  -> first 10:00
     5 min  -> first  5:00
     1 min  -> first  1:00

The nested cuts share the same start sample so RTF and transcript quality are
comparable across durations.

Usage:
    python3 fixtures/scripts/fetch_audio.py [--url URL] [--start 600] [--window 1830]

Requires: yt-dlp and ffmpeg on PATH.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures" / "audio"
SCRIPTS = ROOT / "fixtures" / "scripts"

DEFAULT_URL = "https://www.youtube.com/watch?v=mQBuZ6Dp0u0"
# Mid-video window: skip the cold open and sample sustained tutorial speech.
DEFAULT_START = 600
DEFAULT_WINDOW = 1830  # 30:30, leaves margin for the 30:00 cut

NAMES = {
    "01": "01_min_technical_dictation.wav",
    "05": "05_min_mixed_stutter_tech.wav",
    "10": "10_min_agentic_coding.wav",
    "30": "30_min_long_session.wav",
}


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), file=sys.stderr)
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--start", type=int, default=DEFAULT_START,
                        help="source offset in seconds")
    parser.add_argument("--window", type=int, default=DEFAULT_WINDOW,
                        help="seconds of audio to download")
    args = parser.parse_args()

    for tool in ("yt-dlp", "ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            print(f"missing required tool: {tool}", file=sys.stderr)
            return 2

    FIXTURES.mkdir(parents=True, exist_ok=True)
    SCRIPTS.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="superflow-asr-") as tmp:
        tmpdir = Path(tmp)
        raw = tmpdir / "reference.%(ext)s"
        end = args.start + args.window

        # Audio-only selection. The android client is the one YouTube currently
        # serves without a login on this machine; sections avoid pulling 2h+.
        run([
            "yt-dlp", "--no-warnings", "--no-playlist",
            "--extractor-args", "youtube:player_client=android",
            "-f", "bestaudio/best",
            "--download-sections", f"*{args.start}-{end}",
            "--force-keyframes-at-cuts",
            "-x", "--audio-format", "wav",
            "--postprocessor-args", "-ar 16000 -ac 1",
            "-o", str(raw),
            args.url,
        ])

        master = tmpdir / "reference.wav"
        if not master.exists():
            candidates = list(tmpdir.glob("reference*"))
            if not candidates:
                raise SystemExit("yt-dlp produced no audio file")
            master = candidates[0]

        # Re-encode so every fixture has exactly the same format and length.
        for key, seconds in (("30", 1800), ("10", 600), ("05", 300), ("01", 60)):
            out = FIXTURES / NAMES[key]
            run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(master), "-t", str(seconds),
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                str(out),
            ])
            duration = probe_duration(out)
            print(f"{out.relative_to(ROOT)}: {duration:.2f}s", file=sys.stderr)

        source = {
            "url": args.url,
            "source_offset_s": args.start,
            "downloaded_window_s": args.window,
            "note": "Third-party audio downloaded locally for evaluation only; not redistributed.",
            "fixtures": {k: NAMES[k] for k in NAMES},
        }
        (SCRIPTS / "source.json").write_text(json.dumps(source, indent=2) + "\n")
    return 0


def probe_duration(path: Path) -> float:
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path),
    ], text=True)
    return float(out.strip())


if __name__ == "__main__":
    raise SystemExit(main())
