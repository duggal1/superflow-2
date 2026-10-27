#!/usr/bin/env python3
"""Generate deterministic speech fixtures with exact-duration PCM audio and ground truth."""

from __future__ import annotations

import argparse
import random
import re
import subprocess
import tempfile
import wave
from pathlib import Path


def vocabulary(path: Path, size: int, seed: int) -> list[str]:
    words = {
        value.lower()
        for value in path.read_text(encoding="utf-8", errors="ignore").splitlines()
        if re.fullmatch(r"[A-Za-z]{4,11}", value)
    }
    ordered = sorted(words)
    if len(ordered) < size:
        raise ValueError(f"word list has {len(ordered)} usable words; need {size}")
    random.Random(seed).shuffle(ordered)
    return ordered[:size]


def make_script(words: list[str], count: int, seed: int) -> str:
    rng = random.Random(seed)
    sequence = [rng.choice(words) for _ in range(count)]
    sentences = [" ".join(sequence[offset : offset + 12]) for offset in range(0, count, 12)]
    return ". ".join(sentences).capitalize() + ".\n"


def render(script: Path, wav_path: Path, rate: int) -> None:
    with tempfile.TemporaryDirectory(prefix="superflow-tts-") as temporary:
        aiff_path = Path(temporary) / "speech.aiff"
        subprocess.run(["say", "-r", str(rate), "-f", str(script), "-o", str(aiff_path)], check=True)
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", str(aiff_path), str(wav_path)],
            check=True,
        )


def tile_exact_duration(source: Path, destination: Path, ground_truth: Path, seconds: int) -> None:
    target_frames = seconds * 16_000
    with wave.open(str(source), "rb") as rendered:
        if rendered.getframerate() != 16_000 or rendered.getnchannels() != 1 or rendered.getsampwidth() != 2:
            raise ValueError("TTS conversion did not produce 16 kHz mono PCM16")
        frame_count = rendered.getnframes()
        if frame_count > target_frames:
            raise ValueError(
                f"generated speech is {frame_count / 16_000:.1f}s, longer than {seconds}s; "
                "raise --rate or lower --words"
            )
        copies = max(1, target_frames // frame_count)
        used_frames = copies * frame_count
        padding_frames = target_frames - used_frames
        with wave.open(str(destination), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16_000)
            for _ in range(copies):
                rendered.rewind()
                remaining = frame_count
                while remaining:
                    count = min(16_000, remaining)
                    output.writeframesraw(rendered.readframes(count))
                    remaining -= count
            while padding_frames:
                count = min(16_000, padding_frames)
                output.writeframesraw(b"\0\0" * count)
                padding_frames -= count
            output.writeframes(b"")

    text = ground_truth.read_text(encoding="utf-8")
    ground_truth.write_text(text * copies, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--words", type=int, choices=(1_000, 10_000, 100_000))
    parser.add_argument("--seconds", type=int, choices=(300, 600, 1_800, 3_600, 7_200, 18_000, 36_000), required=True)
    parser.add_argument("--rate", type=int, default=250)
    parser.add_argument("--seed", type=int, default=0x5F10)
    parser.add_argument("--dictionary", type=Path, default=Path("/usr/share/dict/words"))
    parser.add_argument("--source-audio", type=Path,
                        help="tile a previously generated WAV and its sibling .txt ground truth")
    args = parser.parse_args()
    if args.rate <= 0:
        parser.error("--rate must be positive")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    truth = args.output.with_suffix(".txt")
    if args.source_audio:
        source_truth = args.source_audio.with_suffix(".txt")
        if not source_truth.is_file():
            parser.error(f"ground truth does not exist: {source_truth}")
        truth.write_text(source_truth.read_text(encoding="utf-8"), encoding="utf-8")
        tile_exact_duration(args.source_audio, args.output, truth, args.seconds)
    else:
        if args.words is None:
            parser.error("--words is required unless --source-audio is provided")
        script = make_script(vocabulary(args.dictionary, 200, args.seed), args.words, args.seed)
        with tempfile.TemporaryDirectory(prefix="superflow-script-") as temporary:
            script_path = Path(temporary) / "script.txt"
            base_wav = Path(temporary) / "speech.wav"
            script_path.write_text(script, encoding="utf-8")
            truth.write_text(script, encoding="utf-8")
            render(script_path, base_wav, args.rate)
            tile_exact_duration(base_wav, args.output, truth, args.seconds)
    print(f"Wrote {args.output} ({args.seconds}s), ground truth {truth}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
