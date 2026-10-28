#!/usr/bin/env python3
"""Drive the SuperFlow Nemotron-3.5 streaming ASR campaign.

Matrix (per backend: cpu, gpu, ane):
    1 min  x3, 5 min x3, 10 min x2, 30 min x2

Extra probes:
    1 min @ 1120 ms tier x1 per backend
    1 min @ real-time pace x1 per backend (true time-to-first-partial)

The first CPU run of each duration also runs the full cleanup pipeline; every
other run uses cleanup=off so repeated measurements isolate ASR.

Nothing here changes the product default. Backends are selected only through
SUPERFLOW_COMPUTE_UNITS for the child process.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "tools/Superflowctl/.build/release/superflowctl"
CACHE = ROOT / ".models/FluidAudio"
PROFILE = "nemotron-3.5-asr-streaming-0.6b"

FIXTURES = {
    1: ROOT / "fixtures/audio/01_min_technical_dictation.wav",
    5: ROOT / "fixtures/audio/05_min_mixed_stutter_tech.wav",
    10: ROOT / "fixtures/audio/10_min_agentic_coding.wav",
    30: ROOT / "fixtures/audio/30_min_long_session.wav",
}
REPEATS = {1: 3, 5: 3, 10: 2, 30: 2}
BACKENDS = ["cpu", "gpu", "ane"]
BACKEND_LABEL = {"cpu": "CPU", "gpu": "GPU", "ane": "ANE"}


def run_one(out_dir: Path, backend: str, minutes: int, rep: int,
            *, cleanup: str, pace: str = "inf", tier_dir: Path | None = None,
            tag: str = "") -> dict:
    audio = FIXTURES[minutes]
    suffix = f"{tag}_" if tag else ""
    name = f"{suffix}{minutes:02d}min_{backend}_r{rep}.json"
    json_path = out_dir / "performance/runs" / name
    log_path = out_dir / "performance/logs" / name.replace(".json", ".log")
    json_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["SUPERFLOW_COMPUTE_UNITS"] = backend
    env["SUPERFLOW_CLEANUP"] = cleanup
    if tier_dir is not None:
        env["SUPERFLOW_MODEL_DIR"] = str(tier_dir)
    else:
        env.pop("SUPERFLOW_MODEL_DIR", None)

    cmd = [str(CLI), "campaign", str(audio), PROFILE, str(CACHE), pace, str(json_path)]
    started = time.time()
    print(f"[{datetime.now():%H:%M:%S}] {name} cleanup={cleanup} pace={pace}"
          + (f" tier={tier_dir.name}" if tier_dir else ""), flush=True)
    try:
        proc = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True,
                              text=True, timeout=1800)
        elapsed = time.time() - started
        log_path.write_text(
            f"$ {' '.join(cmd)}\n\n--- stdout ---\n{proc.stdout}\n\n--- stderr ---\n{proc.stderr}\n")
        if proc.returncode != 0 or not json_path.exists():
            print(f"  FAIL exit={proc.returncode} after {elapsed:.0f}s", flush=True)
            return {"name": name, "status": "failed", "backend": backend,
                    "minutes": minutes, "rep": rep, "cleanup": cleanup,
                    "elapsed_s": elapsed, "stderr": proc.stderr[-2000:]}
        data = json.loads(json_path.read_text())
        print(f"  ok {elapsed:.1f}s wall={data['wall_clock_s']:.2f}s "
              f"RTFx={data['rtfx']:.2f} ttfp={data.get('ttfp_ms')}", flush=True)
        return {"name": name, "status": "ok", "backend": backend, "minutes": minutes,
                "rep": rep, "cleanup": cleanup, "pace": pace,
                "tier_ms": data.get("tier_ms"), "elapsed_s": elapsed}
    except subprocess.TimeoutExpired as exc:
        print(f"  TIMEOUT after 1800s", flush=True)
        log_path.write_text(f"TIMEOUT\n{exc}")
        return {"name": name, "status": "timeout", "backend": backend,
                "minutes": minutes, "rep": rep, "cleanup": cleanup,
                "elapsed_s": 1800}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=BACKENDS + ["all"], default="all")
    parser.add_argument("--durations", default="1,5,10,30")
    parser.add_argument("--skip-extras", action="store_true")
    parser.add_argument("--results", default=None)
    args = parser.parse_args()

    if not CLI.exists():
        print(f"missing CLI: {CLI}\nrun swift build -c release in tools/Superflowctl",
              file=sys.stderr)
        return 2

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.results) if args.results else ROOT / "results" / stamp
    out_dir.mkdir(parents=True, exist_ok=True)
    durations = [int(v) for v in args.durations.split(",") if v.strip()]
    backends = BACKENDS if args.only == "all" else [args.only]

    manifest: list[dict] = []
    manifest_path = out_dir / "manifest.json"

    def record(entry: dict) -> None:
        manifest.append(entry)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    # Main matrix. Rotate backend order per repetition so thermal drift does
    # not land on the same backend every time.
    for minutes in durations:
        reps = REPEATS[minutes]
        full_done = False
        for rep in range(reps):
            order = backends[rep % len(backends):] + backends[:rep % len(backends)]
            for backend in order:
                cleanup = "off"
                if not full_done and backend == "cpu":
                    cleanup = "full"
                    full_done = True
                record(run_one(out_dir, backend, minutes, rep, cleanup=cleanup))
        if not full_done and "cpu" not in backends:
            # Guarantee one cleaned transcript per duration even when CPU is
            # excluded: use whichever backend is present.
            record(run_one(out_dir, backends[0], minutes, 0, cleanup="full",
                           tag="quality"))

    if not args.skip_extras:
        # Tier comparison at 1 minute.
        for backend in backends:
            record(run_one(out_dir, backend, 1, 1, cleanup="off", tag="tier1120",
                           tier_dir=ROOT / ".models/nemotron35/latin/1120ms"))
        # Live-pace TTFP at 1 minute (takes ~60 s per backend).
        for backend in backends:
            record(run_one(out_dir, backend, 1, 1, cleanup="off", pace="1",
                           tag="paced"))

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nresults: {out_dir}", flush=True)
    failed = [m for m in manifest if m["status"] != "ok"]
    print(f"runs: {len(manifest)}  failed: {len(failed)}", flush=True)
    for item in failed:
        print(f"  {item['name']}: {item['status']}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
