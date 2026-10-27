#!/usr/bin/env python3
"""Generate deterministic 16 kHz mono PCM WAV fixtures for journal and capture tests."""

from __future__ import annotations

import argparse
import math
import struct
import wave
from pathlib import Path


def generate(path: Path, seconds: int, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames_per_write = sample_rate
    total_frames = seconds * sample_rate
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        written = 0
        while written < total_frames:
            count = min(frames_per_write, total_frames - written)
            data = bytearray(count * 2)
            for offset in range(count):
                frame = written + offset
                # A low-level, slowly modulated tone provides non-silent deterministic samples.
                envelope = 0.12 + 0.03 * math.sin(2 * math.pi * frame / (sample_rate * 3))
                value = int(32767 * envelope * math.sin(2 * math.pi * 220 * frame / sample_rate))
                struct.pack_into("<h", data, offset * 2, value)
            output.writeframesraw(data)
            written += count
        output.writeframes(b"")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="destination WAV path")
    parser.add_argument("--seconds", type=int, required=True, help="fixture duration")
    parser.add_argument("--sample-rate", type=int, default=16_000)
    args = parser.parse_args()
    if args.seconds <= 0 or args.sample_rate <= 0:
        parser.error("seconds and sample-rate must be positive")
    generate(args.output, args.seconds, args.sample_rate)
    print(f"Wrote {args.seconds}s mono PCM16 fixture to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
