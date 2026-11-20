#!/usr/bin/env python3
"""Brutal, headless, offline S1-mini quality probe.

One job: feed extremely broken ASR transcripts to the *installed* S1-mini
llama-server with the exact pinned system prompt + control line, score grammar,
fact preservation and formatting (especially dash bullets / partial Markdown),
and record latency + streaming time-to-first-token. Bounded and opt-in.

Safety (matches tools/bench-s1/bench.py):
  * Requires --i-opt-in. Nothing starts without it.
  * Loopback only, no downloads, model opened read-only by the server.
  * Starts and stops ONLY the server it starts; never touches other processes.
  * Per-call timeout 30 s, whole-run cap 300 s, pause between requests.
  * Writes only under --outdir (default .proof/brutal-s1).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

SYSTEM_PROMPT = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)
DEFAULT_MODEL = os.path.expanduser(
    "~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf"
)
PER_CALL_TIMEOUT_S = 30.0
TOTAL_CAP_S = 300.0


# Each case: name, raw transcript, control overrides, required substrings,
# forbidden substrings, and structural checks.
CASES: list[dict[str, Any]] = [
    dict(name="ultra_broken_tech", structure="prose",
         raw="um okay so like the the the the JWT token it's it's like expired you know and the api is is is returning a a four zero three no wait no four two nine because uh the rate limiter it's kicking in you know",
         required=["JWT", "API", "429", "rate limiter"],
         forbidden=["403", "four zero three", "the the", "you know", " um "],
         checks=["capital", "final_punct", "no_fillers", "no_double_space"]),
    dict(name="ultra_broken_negation", structure="prose",
         raw="so um I I I don't not want to uh to to deploy the the config on Friday actually no wait Thursday because the the staging cluster is is still red",
         required=["Thursday", "staging", "red"],
         forbidden=["Friday", "don't not", " the the ", " uh "],
         checks=["capital", "final_punct", "no_fillers"]),
    dict(name="garbled_path", structure="prose",
         raw="open lib slash backend slash main slash engine slash router slash prospect dash main dash engine dot t s then fix the get user by id function no wait getUserById and change the timeout from three thousand to five thousand milliseconds",
         required=["lib/backend/main/engine/router/prospect-main-engine.ts", "getUserById", "3,000", "5,000"],
         forbidden=["backend/backend", "get user by id", "dot t s"],
         checks=["capital", "final_punct"]),
    dict(name="status_code_chaos", structure="prose",
         raw="the the response was a four oh four then a five oh three then a four two nine and uh finally a two hundred but but not a five hundred",
         required=["404", "503", "429", "200", "500", "not"],
         forbidden=[],
         checks=["capital", "final_punct", "no_fillers"]),
    dict(name="numbers_currency_date", structure="prose",
         raw="the invoice came to twenty three thousand four hundred and fifty dollars and it's due on march third twenty twenty six",
         required=["$23,450", "March 3, 2026"],
         forbidden=["twenty three thousand", "23.450"],
         checks=["capital", "final_punct"]),
    dict(name="filler_only", structure="prose",
         raw="um uh um you know like I mean um uh basically um",
         required=[], forbidden=["um", "uh"], checks=["short"]),
    dict(name="time_revision", structure="prose",
         raw="the meeting is at four p m on thursday actually no friday at five thirty",
         required=["5:30", "Friday"], forbidden=["four p m", "Thursday", "thursday"],
         checks=["capital", "final_punct"]),
    dict(name="self_correction_number", structure="prose",
         raw="i think the answer is forty two no sorry forty three",
         required=["43"], forbidden=["42", "forty two"],
         checks=["capital", "final_punct"]),
    dict(name="spoken_email", structure="prose",
         raw="send it to support at superwhisper dot com",
         required=["support@superwhisper.com"], forbidden=[" dot "],
         checks=["capital", "final_punct"]),
    dict(name="technical_vs_everyday", structure="prose",
         raw="we should react to the news and see you next year I need some cash tomorrow open the website please",
         required=["react", "cash", "website"],
         forbidden=["React", "Next.js", "OpenAI", "WebSocket"],
         forbidden_case_sensitive=True,
         checks=["capital", "final_punct"]),
    dict(name="technical_mixed", structure="prose",
         raw="um use s one mini and nemotron with the new deployment next week and check the next js app still builds",
         required=["S1-mini", "Nemotron", "Next.js"],
         forbidden=["s one mini", "next js"],
         checks=["capital", "final_punct", "no_fillers"]),
    dict(name="unicode_preserved", structure="prose",
         raw="um the the api returned a four zero three and sarah said café résumé naïve okay",
         required=["café", "résumé", "naïve", "403"],
         forbidden=[], checks=["no_fillers"]),
    # --- list / dash / partial-Markdown formatting (the user's key focus) ---
    dict(name="list_gaps_sunscreen", structure="lists",
         raw="so for the trip we need to pack um sunscreen and then also a first aid kit and um chargers for everything",
         required=["sunscreen", "first aid kit", "chargers"],
         forbidden=["sunscreen and then"],
         checks=["dash_bullets_3", "no_inline_dash", "capital"]),
    dict(name="list_ordinals", structure="lists",
         raw="first um we need to fix the paywall second add the pricing page third update the docs",
         required=["paywall", "pricing page", "docs"],
         forbidden=[],
         checks=["dash_or_number_bullets_3", "no_fillers"]),
    dict(name="list_dash_spoken", structure="lists",
         raw="the plan is dash ship the api dash update the docs dash tell the team",
         required=["ship", "api", "docs", "team"],
         forbidden=["dash ship", "dash update"],
         checks=["dash_bullets_3", "no_inline_dash"]),
    dict(name="list_gaps_points", structure="lists",
         raw="the results are um point one latency is high point two memory is fine point three cpu is low",
         required=["latency", "memory", "cpu"],
         forbidden=["point one latency"],
         checks=["dash_or_number_bullets_3", "no_fillers"]),
    dict(name="partial_markdown", structure="lists",
         raw="okay so the steps are um star clone the repo star install dependencies star run the tests",
         required=["clone", "install", "tests"],
         forbidden=["star clone"],
         checks=["dash_or_number_bullets_3", "no_fillers"]),
    dict(name="email_layout", structure="prose", context="email",
         raw="hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
         required=["Hey Sarah", "Thanks,", "John", "\n\n"],
         forbidden=["end of week thanks"],
         checks=["capital"]),
    dict(name="list_card_exact", structure="lists",
         raw="so for the trip we need to pack sunscreen and then also a first aid kit and um chargers for everything",
         required=["sunscreen", "first aid kit", "chargers"],
         forbidden=["sunscreen and then"],
         checks=["dash_bullets_3", "no_fillers"]),
    dict(name="list_hyphen_spoken", structure="lists",
         raw="the checklist is hyphen restart the server hyphen clear the cache hyphen verify the logs",
         required=["restart", "clear the cache", "verify the logs"],
         forbidden=["hyphen restart", "hyphen clear"],
         checks=["dash_bullets_3", "no_fillers"]),
    dict(name="list_bullet_spoken", structure="lists",
         raw="the agenda is bullet introductions bullet demo bullet questions",
         required=["introductions", "demo", "questions"],
         forbidden=["bullet introductions"],
         checks=["dash_bullets_3"]),
]


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def server_command(bin_path: str, model: str, port: int) -> list[str]:
    return [
        bin_path, "-m", model, "--jinja",
        "--chat-template-kwargs", '{"enable_thinking":false}',
        "--temp", "0", "-c", "2048", "--host", "127.0.0.1", "--port", str(port),
    ]


def wait_healthy(base: str, proc: subprocess.Popen[bytes], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    url = base + "/health"
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"llama-server exited early: {proc.returncode}")
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            time.sleep(0.25)
    raise TimeoutError("server not healthy in time")


def messages_for(case: dict[str, Any]) -> list[dict[str, str]]:
    structure = case.get("structure", "prose")
    context = case.get("context", "general")
    control = f"[Styling: semi-formal] [Structure: {structure}] [Context: {context}]"
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": control + "\n" + case["raw"]},
    ]


def body_for(case: dict[str, Any]) -> dict[str, Any]:
    approx_tokens = max(1, len(case["raw"]) // 4)
    cap = min(512, int(approx_tokens * 1.3) + 32)
    return {
        "messages": messages_for(case),
        "temperature": 0,
        "max_tokens": cap,
        "stream": False,
    }


def post(base: str, body: dict[str, Any]) -> tuple[dict[str, Any], float]:
    req = urllib.request.Request(
        base + "/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=PER_CALL_TIMEOUT_S) as r:
        payload = json.loads(r.read().decode("utf-8"))
    return payload, (time.monotonic() - t0) * 1000.0


def post_stream_ttft(base: str, body: dict[str, Any]) -> float:
    """Return time-to-first-token (ms) for one streaming request."""
    b = dict(body)
    b["stream"] = True
    req = urllib.request.Request(
        base + "/v1/chat/completions",
        data=json.dumps(b).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=PER_CALL_TIMEOUT_S) as r:
        for raw_line in r:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            chunk = line[5:].strip()
            if chunk == "[DONE]":
                break
            obj = json.loads(chunk)
            delta = (obj.get("choices") or [{}])[0].get("delta", {})
            if delta.get("content"):
                return (time.monotonic() - t0) * 1000.0
    return -1.0


def clean_text(payload: dict[str, Any]) -> str:
    choice = (payload.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content") or ""
    # Strip thinking leakage if the server emitted any.
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    return text.strip()


def structural_checks(text: str, checks: Iterable[str]) -> list[str]:
    misses: list[str] = []
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    dash_lines = [ln for ln in lines if ln.startswith("- ")]
    num_lines = [ln for ln in lines if re.match(r"^\d+[.)]\s", ln)]
    for check in checks:
        if check == "capital" and text[:1] and not text[:1].isupper():
            misses.append("no_capital")
        elif check == "final_punct" and (not text or text[-1] not in ".!?"):
            misses.append("no_final_punct")
        elif check == "no_fillers" and re.search(r"\b(um|uh|you know)\b", text, re.I):
            misses.append("fillers_present")
        elif check == "no_double_space" and "  " in text:
            misses.append("double_space")
        elif check == "short" and len(text) > 45:
            misses.append("too_long")
        elif check == "dash_bullets_3" and len(dash_lines) != 3:
            misses.append(f"dash_bullets_{len(dash_lines)}_expected_3")
        elif check == "dash_or_number_bullets_3" and (len(dash_lines) + len(num_lines)) != 3:
            misses.append(f"bullets_{len(dash_lines) + len(num_lines)}_expected_3")
        elif check == "no_inline_dash":
            # A spaced hyphen inside prose means the model failed to format a bullet.
            for ln in lines:
                if not ln.startswith("- ") and re.search(r"\s+-\s+", ln):
                    misses.append("inline_dash_in_prose")
                    break
    return misses


def score(case: dict[str, Any], text: str) -> dict[str, Any]:
    misses: list[str] = []
    low = text.lower()
    case_sensitive = case.get("forbidden_case_sensitive", False)
    for token in case.get("required", []):
        if token.lower() not in low:
            misses.append("missing:" + token)
    for token in case.get("forbidden", []):
        hit = (token in text) if case_sensitive else (token.lower() in low)
        if hit:
            misses.append("bad:" + token)
    misses.extend(structural_checks(text, case.get("checks", [])))
    return {"name": case["name"], "pass": not misses, "misses": misses,
            "output": text, "raw": case["raw"]}


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    data = sorted(values)
    pos = (len(data) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(data) - 1)
    return data[lo] + (data[hi] - data[lo]) * (pos - lo)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Brutal offline S1-mini quality probe")
    ap.add_argument("--i-opt-in", action="store_true", help="Required consent to load the model")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--server-bin", default=shutil.which("llama-server") or "llama-server")
    ap.add_argument("--base-url", default=None, help="Use an existing loopback server")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--case", action="append", default=[], help="Run only named case(s)")
    ap.add_argument("--total-cap-s", type=float, default=TOTAL_CAP_S)
    args = ap.parse_args(argv)

    if not args.i_opt_in:
        print("REFUSING: pass --i-opt-in to load the model. Offline, loopback, read-only.",
              file=sys.stderr)
        return 2
    if args.base_url:
        host = urllib.parse.urlsplit(args.base_url).hostname
        if host not in ("127.0.0.1", "localhost", "::1"):
            print("REFUSING: --base-url must be loopback", file=sys.stderr)
            return 2
        base, proc = args.base_url.rstrip("/"), None
    else:
        if not os.path.isfile(args.model):
            print(f"Model not found: {args.model}", file=sys.stderr)
            return 2
        port = free_port()
        base = f"http://127.0.0.1:{port}"
        proc = subprocess.Popen(
            server_command(args.server_bin, args.model, port),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_healthy(base, proc, timeout=min(60, args.total_cap_s))
        except Exception as exc:
            print(f"Server failed: {exc}", file=sys.stderr)
            proc.terminate()
            return 2

    outdir = Path(args.outdir) if args.outdir else (
        Path(__file__).resolve().parents[2] / ".proof" / "brutal-s1")
    outdir.mkdir(parents=True, exist_ok=True)
    cases = [c for c in CASES if not args.case or c["name"] in args.case]
    started = time.monotonic()
    deadline = started + args.total_cap_s
    results: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    latencies: list[float] = []
    ttfts: list[float] = []
    try:
        for case in cases:
            if time.monotonic() >= deadline:
                errors.append({"case": case["name"], "error": "total cap reached"})
                break
            body = body_for(case)
            try:
                payload, latency = post(base, body)
                text = clean_text(payload)
                latencies.append(latency)
                result = score(case, text)
                finish = (payload.get("choices") or [{}])[0].get("finish_reason")
                result["finish_reason"] = finish
                result["latency_ms"] = round(latency, 1)
                usage = payload.get("usage") or {}
                result["completion_tokens"] = usage.get("completion_tokens")
                # Streaming TTFT on a subset to verify "streaming is on, fast".
                if case["name"] in ("ultra_broken_tech", "list_gaps_sunscreen", "partial_markdown"):
                    try:
                        ttft = post_stream_ttft(base, body)
                        if ttft >= 0:
                            ttfts.append(ttft)
                            result["stream_ttft_ms"] = round(ttft, 1)
                    except Exception as exc:
                        result["stream_ttft_error"] = str(exc)[:120]
                results.append(result)
            except Exception as exc:
                errors.append({"case": case["name"], "error": f"{type(exc).__name__}: {exc}"[:300]})
            time.sleep(0.2)
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)

    passed = sum(1 for r in results if r["pass"])
    result = {
        "schema": "superflow.brutal-s1.v1",
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "claim_scope": ("Isolated S1-mini normalizer quality + latency on synthetic broken "
                        "ASR strings. NOT end-to-end dictation WER."),
        "model": args.model if not args.base_url else "external loopback server",
        "prompt": {"system": SYSTEM_PROMPT,
                   "control": "[Styling: semi-formal] [Structure: <case>] [Context: <case>]"},
        "elapsed_s": round(time.monotonic() - started, 2),
        "summary": {
            "passed": passed, "total": len(cases),
            "latency_ms": {"p50": percentile(latencies, 0.5),
                           "p95": percentile(latencies, 0.95)},
            "stream_ttft_ms": {"p50": percentile(ttfts, 0.5),
                               "max": max(ttfts) if ttfts else None},
            "errors": errors,
        },
        "cases": results,
    }
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    out = outdir / f"brutal-{stamp}.json"
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [f"BRUTAL S1-mini quality: {passed}/{len(cases)} pass",
             f"latency p50={result['summary']['latency_ms']['p50']}ms "
             f"p95={result['summary']['latency_ms']['p95']}ms "
             f"stream TTFT p50={result['summary']['stream_ttft_ms']['p50']}ms",
             ""]
    for r in results:
        verdict = "PASS" if r["pass"] else "FAIL " + ",".join(r["misses"])
        lines.append(f"== {r['name']} :: {verdict} (lat {r['latency_ms']}ms)")
        lines.append(f"IN : {r['raw']}")
        lines.append(f"OUT: {r['output']}")
        if r.get("stream_ttft_ms") is not None:
            lines.append(f"TTFT: {r['stream_ttft_ms']}ms")
        lines.append("")
    if errors:
        lines.append("ERRORS: " + json.dumps(errors))
    (outdir / f"brutal-{stamp}.txt").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines[:6]))
    print(f"Wrote {out}")
    return 0 if passed == len(cases) and not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
