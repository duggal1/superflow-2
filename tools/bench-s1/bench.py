#!/usr/bin/env python3
"""Opt-in, offline S1-mini latency probe.

WHAT THIS IS
------------
A pure-stdlib harness that measures *isolated* llama-server completion latency
for the S1-mini Q4_K_M model, using the exact pinned system prompt + control
line and the documented thinking-off/greedy server flags.

WHAT THIS IS NOT
----------------
It is NOT an end-to-end dictation benchmark. A single number from this script
does not measure key-down->capture, first partial, stop->paste, real-time
factor (RTF), or warmup. Those stages remain UNVERIFIED. See
docs/benchmarks/README.md and docs/benchmarks/audit-unverified-claims.md.

SAFETY
------
* Opt-in: nothing happens unless --i-opt-in is passed explicitly.
* Offline: only 127.0.0.1 is contacted; nothing is downloaded.
* No production data: only the embedded synthetic transcripts (or an offline
  --input-file the user supplies) are sent. No user/owner corpus is read.
* The model file is opened read-only. The only write is a result JSON under
  docs/benchmarks/results/ (override with --outdir).
* Batches are <= 10 calls, each call is capped at 30 s, and the whole run is
  capped at ~300 s. A short pause separates batches to keep the Mac responsive.

USAGE
-----
    python3 tools/bench-s1/bench.py --i-opt-in

    # connect to an already-running llama-server instead of starting one:
    python3 tools/bench-s1/bench.py --i-opt-in --base-url http://127.0.0.1:8080

    # verify the pure logic without loading any model:
    python3 tools/bench-s1/test_bench.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Sequence

# ---------------------------------------------------------------------------
# Pinned contract (copied verbatim from the repo's pinned prompt resource).
# Source: Packages/L1-Adapters/LLMLlamaCpp/Sources/SuperflowLLMCore/Resources/s1-prompt.json
# Rendering: LlamaPrompt.render / LlamaPrompt.controlLine in LlamaCleaner.swift.
# Keep these in sync; do not "improve" the prompt for a benchmark.
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)
CONTROL_LINE = "[Styling: semi-formal] [Structure: lists] [Context: general]"
PROMPT_RESOURCE = (
    "Packages/L1-Adapters/LLMLlamaCpp/Sources/SuperflowLLMCore/Resources/s1-prompt.json"
)

# Documented installed location; override with --model or SUPERFLOW_BENCH_MODEL.
DEFAULT_MODEL = os.path.expanduser(
    "~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf"
)

PER_CALL_TIMEOUT_S = 30.0
TOTAL_CAP_S = 300.0
MAX_BATCH_SIZE = 10
DEFAULT_BATCH_SIZE = 5
DEFAULT_BATCH_PAUSE_S = 1.0
DEFAULT_MAX_TOKENS = 512

# Synthetic, offline, invented inputs. These are latency fixtures, not quality
# goldens and not any user's dictated text. Short inputs stay well under the
# model's ~1000-token recommended chunk length.
SYNTHETIC_TRANSCRIPTS: tuple[str, ...] = (
    "um okay so I need to send the report by Thursday no wait by Friday",
    "the budget is one hundred twenty five thousand dollars not twenty five thousand",
    "first open the paywall screen then add a new pricing page with three tiers",
    "i think the answer is forty two no sorry forty three",
    "um use S1 mini and Nemotron with the new deployment next week",
    "call Morgan and Priya and send them the updated notes by Thursday",
    "the deadline is October thirty first and we cannot miss it you know",
    "set the status code from five hundred to four twenty nine when rate limited",
    "change the constant max retry count from three to five in the config",
    "uh the meeting is at ten thirty AM in the main conference room",
    "please make sure the next JS app still builds after the upgrade",
    "the tailwind config broke last week so check it before shipping",
    "increment the counter dash get call by one for each retry attempt",
    "i need a list of three items first the paywall second pricing third docs",
    "no wait the total is twelve thousand not one hundred and twenty thousand",
    "um the API endpoint returns a four oh four when the id is missing",
    "schedule a follow up for next Tuesday with the whole engineering team",
    "she said the temperature is thirty seven degrees celsius not thirty",
    "run the migration on staging first and then we can do production",
    "the client wants the file in lib backend main engine router folder",
)

RESULT_SCHEMA = "superflow.s1-benchmark.v1"
CLAIM_SCOPE = (
    "Isolated llama-server /v1/chat/completions latency for the pinned S1-mini "
    "prompt only. NOT a measurement of key-down->capture, first partial, "
    "stop->paste, RTF, or warmup. Those remain UNVERIFIED."
)


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested by test_bench.py; no model, no network).
# ---------------------------------------------------------------------------
def percentiles(values: Sequence[float]) -> dict[str, float]:
    """p50/p95/p99 with linear interpolation between closest ranks (type 7).

    Returns empty dict for an empty input so callers cannot mistake it for a
    measurement. Values are not rounded here; the JSON writer rounds for display.
    """
    data = sorted(float(v) for v in values)
    if not data:
        return {}

    def at(q: float) -> float:
        if len(data) == 1:
            return data[0]
        pos = (len(data) - 1) * q
        lo = int(pos)
        hi = min(lo + 1, len(data) - 1)
        frac = pos - lo
        return data[lo] + (data[hi] - data[lo]) * frac

    return {"p50": at(0.50), "p95": at(0.95), "p99": at(0.99),
            "min": data[0], "max": data[-1],
            "mean": sum(data) / len(data)}


def build_messages(transcript: str) -> list[dict[str, str]]:
    """Exact system prompt + control line, then the raw transcript line."""
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": CONTROL_LINE + "\n" + transcript},
    ]


def build_request_body(transcript: str, max_tokens: int = DEFAULT_MAX_TOKENS) -> dict[str, Any]:
    """Greedy, non-streaming chat request.

    The empty think prefix is produced by the server's Jinja template with
    --chat-template-kwargs '{"enable_thinking":false}', matching the pinned
    assistantPrefix; it is deliberately not injected here.
    """
    return {
        "messages": build_messages(transcript),
        "temperature": 0,
        "max_tokens": max_tokens,
        "stream": False,
    }


def server_command(server_bin: str, model: str, port: int) -> list[str]:
    """Documented flags plus loopback-only host/port for safety."""
    return [
        server_bin,
        "-m", model,
        "--jinja",
        "--chat-template-kwargs", '{"enable_thinking":false}',
        "--temp", "0",
        "-c", "2048",
        "--host", "127.0.0.1",
        "--port", str(port),
    ]


def free_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def post_completion(base_url: str, body: dict[str, Any],
                    timeout_s: float = PER_CALL_TIMEOUT_S) -> tuple[dict[str, Any], float]:
    """POST one chat completion; return (payload, latency_ms). Never retries."""
    url = base_url.rstrip("/") + "/v1/chat/completions"
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.monotonic()
    with urllib.request.urlopen(request, timeout=timeout_s) as response:
        raw = response.read()
    latency_ms = (time.monotonic() - start) * 1000.0
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("completion response is not a JSON object")
    return payload, latency_ms


def _extract_call(body: dict[str, Any], payload: dict[str, Any],
                  latency_ms: float) -> dict[str, Any]:
    usage = payload.get("usage") or {}
    prompt_tokens = int(usage.get("prompt_tokens", -1))
    completion_tokens = int(usage.get("completion_tokens", -1))
    choice = (payload.get("choices") or [{}])[0]
    finish_reason = choice.get("finish_reason")

    e2e_tps = None
    if completion_tokens > 0 and latency_ms > 0:
        e2e_tps = completion_tokens / (latency_ms / 1000.0)

    decode_tps = None
    timings = payload.get("timings") or {}
    if isinstance(timings, dict):
        for key in ("predicted_per_second", "predicted_perSecond"):
            if key in timings and timings[key] is not None:
                try:
                    decode_tps = float(timings[key])
                    break
                except (TypeError, ValueError):
                    pass

    transcript = body["messages"][-1]["content"].split("\n", 1)[-1]
    return {
        "latency_ms": round(latency_ms, 3),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "finish_reason": finish_reason,
        "hit_token_cap": finish_reason == "length",
        "e2e_output_tokens_per_s": (round(e2e_tps, 3) if e2e_tps is not None else None),
        "server_decode_tokens_per_s": (round(decode_tps, 3) if decode_tps is not None else None),
        "input_chars": len(transcript),
    }


def run_bench(
    transcripts: Sequence[str],
    call_fn: Callable[[dict[str, Any]], tuple[dict[str, Any], float]],
    *,
    batch_size: int = DEFAULT_BATCH_SIZE,
    batch_pause_s: float = DEFAULT_BATCH_PAUSE_S,
    per_call_timeout_s: float = PER_CALL_TIMEOUT_S,
    total_cap_s: float = TOTAL_CAP_S,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    time_fn: Callable[[], float] = time.monotonic,
    sleep_fn: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    """Drive bounded batches; injectable clock/sleeper/caller for offline tests."""
    if not 1 <= batch_size <= MAX_BATCH_SIZE:
        raise ValueError(f"batch_size must be 1..{MAX_BATCH_SIZE}")

    started = time_fn()
    deadline = started + total_cap_s
    calls: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    attempted = 0
    stopped_by_cap = False

    for batch_index in range(0, len(transcripts), batch_size):
        batch = transcripts[batch_index:batch_index + batch_size]
        for offset, transcript in enumerate(batch):
            if time_fn() >= deadline:
                stopped_by_cap = True
                break
            attempted += 1
            body = build_request_body(transcript, max_tokens)
            try:
                payload, latency_ms = call_fn(body)
                calls.append(_extract_call(body, payload, latency_ms))
            except Exception as exc:  # noqa: BLE001 - record, do not crash the harness
                errors.append({
                    "batch": batch_index // batch_size + 1,
                    "call": offset + 1,
                    "type": type(exc).__name__,
                    "message": str(exc)[:300],
                })
        if stopped_by_cap:
            break
        if batch_index + batch_size < len(transcripts):
            remaining = deadline - time_fn()
            if remaining <= 0:
                stopped_by_cap = True
                break
            sleep_fn(min(batch_pause_s, remaining))

    return {
        "calls": calls,
        "errors": errors,
        "attempted": attempted,
        "stopped_by_cap": stopped_by_cap,
        "elapsed_s": round(time_fn() - started, 3),
        "limits": {
            "per_call_timeout_s": per_call_timeout_s,
            "total_cap_s": total_cap_s,
            "batch_size": batch_size,
            "max_batch_size": MAX_BATCH_SIZE,
            "batch_pause_s": batch_pause_s,
            "max_tokens": max_tokens,
        },
    }


def summarize(run: dict[str, Any]) -> dict[str, Any]:
    calls = run["calls"]
    latencies = [c["latency_ms"] for c in calls]
    e2e = [c["e2e_output_tokens_per_s"] for c in calls
           if c["e2e_output_tokens_per_s"] is not None]
    decode = [c["server_decode_tokens_per_s"] for c in calls
              if c["server_decode_tokens_per_s"] is not None]

    succeeded = len(calls)
    failed = len(run["errors"])
    if succeeded == 0:
        status = "EMPTY_NOT_MEASURED"
    elif failed or run["stopped_by_cap"] or any(c["hit_token_cap"] for c in calls):
        status = "PARTIAL"
    else:
        status = "MEASURED"

    return {
        "status": status,
        "calls_attempted": run["attempted"],
        "calls_succeeded": succeeded,
        "calls_failed": failed,
        "calls_hit_token_cap": sum(1 for c in calls if c["hit_token_cap"]),
        "stopped_by_total_cap": run["stopped_by_cap"],
        "elapsed_s": run["elapsed_s"],
        "latency_ms": percentiles(latencies),
        "e2e_output_tokens_per_s": percentiles(e2e),
        "server_decode_tokens_per_s": (percentiles(decode) if decode else None),
        "prompt_tokens_total": sum(c["prompt_tokens"] for c in calls
                                   if c["prompt_tokens"] >= 0),
        "completion_tokens_total": sum(c["completion_tokens"] for c in calls
                                       if c["completion_tokens"] >= 0),
        "throughput_definition": (
            "e2e_output_tokens_per_s = completion_tokens / request latency "
            "(includes prefill). server_decode_tokens_per_s is the value llama-server "
            "reports in `timings`, when present; it excludes prefill."
        ),
        "percentile_method": "linear interpolation between closest ranks (type 7)",
    }


# ---------------------------------------------------------------------------
# Server lifecycle and result persistence.
# ---------------------------------------------------------------------------
def wait_healthy(base_url: str, proc: subprocess.Popen[bytes] | None,
                 timeout_s: float, sleep_fn: Callable[[float], None] = time.sleep) -> None:
    url = base_url.rstrip("/") + "/health"
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if proc is not None and proc.poll() is not None:
            raise RuntimeError(f"llama-server exited early with code {proc.returncode}")
        try:
            with urllib.request.urlopen(url, timeout=2.0) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, OSError, ValueError):
            pass
        sleep_fn(0.25)
    raise TimeoutError(f"llama-server did not become healthy within {timeout_s:.0f}s")


def stop_server(proc: subprocess.Popen[bytes] | None) -> None:
    """Stop only the process this script started, never anything else."""
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)


def optional_sha256(path: str, enabled: bool) -> str | None:
    if not enabled:
        return None
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_result(outdir: Path, result: dict[str, Any]) -> Path:
    outdir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    path = outdir / f"s1-{stamp}.json"
    counter = 1
    while path.exists():
        path = outdir / f"s1-{stamp}-{counter}.json"
        counter += 1
    path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def load_inputs(path: str | None) -> tuple[tuple[str, ...], str]:
    if path is None:
        return SYNTHETIC_TRANSCRIPTS, "embedded synthetic offline fixtures"
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(raw, dict):
        raw = raw.get("transcripts")
    if not isinstance(raw, list) or not all(isinstance(x, str) and x for x in raw):
        raise ValueError("--input-file must be a JSON list of non-empty strings "
                         "(or an object with a `transcripts` list)")
    return tuple(raw), f"user-supplied offline file: {path}"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Opt-in offline S1-mini latency probe (isolated llama-server calls).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Refuses to do anything without --i-opt-in.",
    )
    parser.add_argument("--i-opt-in", action="store_true",
                        help="Explicit consent to start a model/load a GGUF. Required.")
    parser.add_argument("--model", default=os.environ.get("SUPERFLOW_BENCH_MODEL", DEFAULT_MODEL),
                        help="Path to the Q4_K_M GGUF (read-only). Never downloaded.")
    parser.add_argument("--server-bin", default=shutil.which("llama-server") or "llama-server",
                        help="llama-server executable (default: llama-server on PATH).")
    parser.add_argument("--base-url", default=None,
                        help="Use an already-running server instead of starting one "
                             "(must be loopback).")
    parser.add_argument("--input-file", default=None,
                        help="Optional offline JSON list of transcript strings.")
    parser.add_argument("--outdir", default=None,
                        help="Result JSON directory (default: docs/benchmarks/results).")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE,
                        help=f"Calls per batch, 1..{MAX_BATCH_SIZE} (default {DEFAULT_BATCH_SIZE}).")
    parser.add_argument("--batch-pause-s", type=float, default=DEFAULT_BATCH_PAUSE_S,
                        help=f"Pause between batches (default {DEFAULT_BATCH_PAUSE_S}).")
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS,
                        help=f"max_tokens per call (default {DEFAULT_MAX_TOKENS}).")
    parser.add_argument("--total-cap-s", type=float, default=TOTAL_CAP_S,
                        help=f"Whole-run wall clock cap (default {TOTAL_CAP_S}).")
    parser.add_argument("--hash-model", action="store_true",
                        help="Also SHA-256 the model file (read-only; slower).")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.i_opt_in:
        print(
            "REFUSING TO RUN. This probe starts llama-server / loads a GGUF.\n"
            "It is offline, uses only synthetic offline transcripts, and writes only\n"
            "to docs/benchmarks/results/. Re-run with --i-opt-in to confirm.\n"
            "To verify logic with no model load: python3 tools/bench-s1/test_bench.py",
            file=sys.stderr,
        )
        return 2

    if args.base_url:
        parsed = urllib.parse.urlsplit(args.base_url)
        if parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
            print("REFUSING TO RUN: --base-url must be a loopback address (offline).",
                  file=sys.stderr)
            return 2
        base_url = args.base_url
        proc = None
    else:
        model = os.path.expanduser(args.model)
        if not os.path.isfile(model):
            print(f"Model file not found: {model}\n"
                  "Pass --model or set SUPERFLOW_BENCH_MODEL. Nothing is downloaded.",
                  file=sys.stderr)
            return 2
        port = free_loopback_port()
        base_url = f"http://127.0.0.1:{port}"
        args.server_bin = str(args.server_bin)
        cmd = server_command(args.server_bin, model, port)
        print("Starting:", " ".join(cmd), file=sys.stderr)
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
        except OSError as exc:
            print(f"Could not start llama-server: {exc}", file=sys.stderr)
            return 2

    outdir = Path(args.outdir) if args.outdir else (
        Path(__file__).resolve().parents[2] / "docs" / "benchmarks" / "results"
    )
    payload: dict[str, Any] = {}
    proc_local = proc
    try:
        if proc_local is not None:
            wait_healthy(base_url, proc_local, timeout_s=min(60.0, args.total_cap_s))
        transcripts, source = load_inputs(args.input_file)

        def call(body: dict[str, Any]) -> tuple[dict[str, Any], float]:
            return post_completion(base_url, body, timeout_s=PER_CALL_TIMEOUT_S)

        run = run_bench(
            transcripts, call,
            batch_size=args.batch_size,
            batch_pause_s=args.batch_pause_s,
            per_call_timeout_s=PER_CALL_TIMEOUT_S,
            total_cap_s=args.total_cap_s,
            max_tokens=args.max_tokens,
        )
        payload = {
            "schema": RESULT_SCHEMA,
            "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "claim_scope": CLAIM_SCOPE,
            "measured_stage": "isolated llama-server /v1/chat/completions",
            "opt_in": True,
            "offline": True,
            "prompt_contract": {
                "resource": PROMPT_RESOURCE,
                "system_prompt": SYSTEM_PROMPT,
                "control_line": CONTROL_LINE,
                "user_message": "control line + newline + transcript",
                "thinking_off_flag": "--chat-template-kwargs {\"enable_thinking\":false}",
                "temperature": 0,
                "chat_template": "--jinja",
            },
            "model": {
                "path": os.path.expanduser(args.model) if not args.base_url else None,
                "size_bytes": (os.path.getsize(os.path.expanduser(args.model))
                               if not args.base_url and os.path.isfile(os.path.expanduser(args.model))
                               else None),
                "sha256": (optional_sha256(os.path.expanduser(args.model), args.hash_model)
                           if not args.base_url else None),
                "flags": server_command(args.server_bin, os.path.expanduser(args.model), 0)[1:-4],
            },
            "server": {
                "managed_by_script": proc_local is not None,
                "base_url": base_url,
            },
            "inputs": {"source": source, "count": len(transcripts)},
            "run": run,
            "summary": summarize(run),
            "environment": {
                "python": sys.version.split()[0],
                "platform": platform.platform(),
                "machine": platform.machine(),
            },
        }
    except (KeyboardInterrupt, Exception) as exc:  # noqa: BLE001 - always persist partials
        payload = {
            "schema": RESULT_SCHEMA,
            "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "status": "ABORTED",
            "claim_scope": CLAIM_SCOPE,
            "error": {"type": type(exc).__name__, "message": str(exc)[:500]},
            "opt_in": True,
            "offline": True,
        }
    finally:
        stop_server(proc_local)

    path = write_result(outdir, payload)
    status = payload.get("summary", {}).get("status", payload.get("status"))
    print(f"Wrote {path} (status: {status})")
    print("Scope: " + CLAIM_SCOPE)
    return 0 if status in ("MEASURED", "PARTIAL", "EMPTY_NOT_MEASURED") else 1


if __name__ == "__main__":
    raise SystemExit(main())
