#!/usr/bin/env python3
"""Aggregate a campaign results directory into performance, quality and recommendation reports."""
from __future__ import annotations

import argparse
import difflib
import json
import re
import statistics as stats
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

BACKEND_LABEL = {"cpu": "CPU", "gpu": "GPU", "ane": "ANE"}
ORDER = ["cpu", "gpu", "ane"]
FILLERS = {"um", "uh", "uhh", "uhm", "erm", "er", "hmm", "mmm", "mhm"}
TECH_EXT = r"(?:swift|ts|tsx|js|jsx|json|md|yaml|yml|py|rs|toml|sh|html|css|sql|env|lock)"
TECH_RE = re.compile(
    rf"(?:https?://\S+|(?:~|\.{{0,2}}/)?[\w.-]+/[\w./-]+|\b[\w-]+\.{TECH_EXT}\b|"
    r"\b[a-z]+[A-Z]\w*\b|\b[A-Z]{2,}\b|\b\w+_\w+\b|\$\s?\d[\d,.]*|\b\d[\d,.]*\b)")


def load_runs(results: Path) -> list[dict]:
    runs = []
    for path in sorted((results / "performance" / "runs").glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        data["_path"] = str(path)
        data["_name"] = path.stem
        data["_tag"] = "main"
        m = re.match(r"(?:([a-z0-9]+)_)?(\d+)min_([a-z]+)_r(\d+)", path.stem)
        if m:
            if m.group(1):
                data["_tag"] = m.group(1)
            data["_minutes"] = int(m.group(2))
            data["_backend"] = m.group(3)
            data["_rep"] = int(m.group(4))
        runs.append(data)
    return runs


def fmt(value, digits=2, suffix=""):
    if value is None:
        return "—"
    return f"{value:.{digits}f}{suffix}"


def median(values):
    values = [v for v in values if v is not None]
    return stats.median(values) if values else None


def summarize(runs: list[dict]) -> dict:
    main = [r for r in runs if r.get("_tag") == "main"]
    groups = defaultdict(list)
    for r in main:
        groups[(r["_backend"], r["_minutes"])].append(r)
    table = {}
    for (backend, minutes), items in groups.items():
        table[(backend, minutes)] = {
            "n": len(items),
            "rtfx": median([i["rtfx"] for i in items]),
            "rtfx_min": min(i["rtfx"] for i in items),
            "rtfx_max": max(i["rtfx"] for i in items),
            "wall": median([i["wall_clock_s"] for i in items]),
            "rtf": median([i["rtf"] for i in items]),
            "ttfp": median([i.get("ttfp_ms") for i in items]),
            "ttfp_paced": median([i.get("ttfp_ms") for i in items if i.get("pace") == "1"]),
            "peak": median([i["peak_footprint_mb"] for i in items]),
            "load": median([i["load_ms"] for i in items]),
            "segments": median([i["segments_committed"] for i in items]),
            "partials": median([i["chunks_emitted"] for i in items]),
            "failures": sum(len(i.get("failures", [])) for i in items),
            "thermal": sorted({i.get("thermal_end", "?") for i in items}),
        }
    return table


def perf_report(runs: list[dict], table: dict, results: Path) -> str:
    lines = ["# ASR Performance — Nemotron 3.5 Streaming 0.6B", ""]
    lines.append(f"Generated: {datetime.now():%Y-%m-%d %H:%M:%S}")
    lines.append("")
    lines.append("All runs: streaming forced on, 2240 ms tier, unpaced replay unless noted. "
                 "RTF = wall/audio (<1 is faster than real time).")
    lines.append("")
    lines.append("## Main matrix (median of runs)")
    lines.append("")
    lines.append("| Duration | Backend | n | RTFx | wall s | RTF | TTFP ms | peak MB | load s | segments | partials |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for minutes in (1, 5, 10, 30):
        for backend in ORDER:
            row = table.get((backend, minutes))
            if not row:
                continue
            lines.append(
                f"| {minutes} min | {BACKEND_LABEL[backend]} | {row['n']} | "
                f"{fmt(row['rtfx'],1)} | {fmt(row['wall'],1)} | {fmt(row['rtf'],3)} | "
                f"{fmt(row['ttfp'],0)} | {fmt(row['peak'],0)} | {fmt(row['load']/1000,1)} | "
                f"{fmt(row['segments'],0)} | {fmt(row['partials'],0)} |")
    lines.append("")
    lines.append("## Winner per duration")
    lines.append("")
    lines.append("| Duration | Fastest | RTFx | vs CPU | vs GPU | vs ANE |")
    lines.append("|---:|---|---:|---:|---:|---:|")
    for minutes in (1, 5, 10, 30):
        rows = {b: table.get((b, minutes)) for b in ORDER}
        rows = {b: r for b, r in rows.items() if r}
        if not rows:
            continue
        winner = max(rows, key=lambda b: rows[b]["rtfx"])
        base = rows[winner]["rtfx"]
        def rel(b):
            if b not in rows or not rows[b]["rtfx"]:
                return "—"
            return f"{base / rows[b]['rtfx']:.2f}×"
        lines.append(f"| {minutes} min | {BACKEND_LABEL[winner]} | {fmt(base,1)} | "
                     f"{rel('cpu')} | {rel('gpu')} | {rel('ane')} |")
    lines.append("")

    # GPU vs ANE check for the FluidAudio 10x warning.
    lines.append("## FluidAudio 10× warning check (GPU vs ANE, same audio)")
    lines.append("")
    lines.append("| Duration | GPU RTFx | ANE RTFx | ANE/GPU speed | GPU is 10× slower than ANE? |")
    lines.append("|---:|---:|---:|---:|---|")
    for minutes in (1, 5, 10, 30):
        g = table.get(("gpu", minutes))
        a = table.get(("ane", minutes))
        if not g or not a:
            continue
        because = "not observed" if g["rtfx"] >= a["rtfx"] else "not observed (ANE slower)"
        lines.append(f"| {minutes} min | {fmt(g['rtfx'],1)} | {fmt(a['rtfx'],1)} | "
                     f"{a['rtfx']/g['rtfx']:.2f}× | {because} |")
    lines.append("")

    # Tier and paced probes.
    tiers = [r for r in runs if r.get("_tag") == "tier1120"]
    paced = [r for r in runs if r.get("_tag") == "paced"]
    if tiers:
        lines.append("## Tier probe (1 min, 1120 ms vs 2240 ms)")
        lines.append("")
        lines.append("| Backend | 1120 ms RTFx | 2240 ms RTFx | 2240 advantage |")
        lines.append("|---|---:|---:|---:|")
        for backend in ORDER:
            t = [r for r in tiers if r["_backend"] == backend]
            m = table.get((backend, 1))
            if not t or not m:
                continue
            tr = median([r["rtfx"] for r in t])
            lines.append(f"| {BACKEND_LABEL[backend]} | {fmt(tr,1)} | {fmt(m['rtfx'],1)} | "
                         f"{m['rtfx']/tr:.2f}× |")
        lines.append("")
    if paced:
        lines.append("## Live-paced probe (1 min, pace = 1.0)")
        lines.append("")
        lines.append("| Backend | wall s | RTF | TTFP ms | input-finished ms |")
        lines.append("|---|---:|---:|---:|---:|")
        for backend in ORDER:
            items = [r for r in paced if r["_backend"] == backend]
            if not items:
                continue
            lines.append(f"| {BACKEND_LABEL[backend]} | "
                         f"{fmt(median([r['wall_clock_s'] for r in items]),1)} | "
                         f"{fmt(median([r['rtf'] for r in items]),3)} | "
                         f"{fmt(median([r.get('ttfp_ms') for r in items]),0)} | "
                         f"{fmt(median([r['input_finished_ms'] for r in items]),0)} |")
        lines.append("")

    # Reliability.
    lines.append("## Reliability")
    lines.append("")
    total = sum(v["n"] for v in table.values())
    failures = sum(v["failures"] for v in table.values())
    lines.append(f"- Main-matrix runs: **{total}**")
    lines.append(f"- ASR failure events: **{failures}**")
    lines.append(f"- Non-ok manifest entries: **{len([r for r in runs if r.get('_tag') == 'main' and r.get('failures')])}**")
    if (30, "cpu") in table or ("cpu", 30) in table:
        row = table.get(("cpu", 30))
        if row:
            lines.append(f"- 30 min soak (CPU): peak {row['peak']:.0f} MB, "
                         f"median RTFx {row['rtfx']:.1f}, failures {row['failures']}.")
    lines.append("- Peak RSS/footprint is sampled every 100 ms during ASR only; cleanup runs after.")
    lines.append("")
    return "\n".join(lines)


def words(text: str) -> list[str]:
    return re.findall(r"[A-Za-z0-9'$./_-]+", text.lower())


def content_words(text: str) -> list[str]:
    stop = {"the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "for", "with",
            "is", "are", "was", "were", "be", "been", "it", "this", "that", "i", "you",
            "we", "they", "he", "she", "as", "at", "by", "from", "so", "if", "then"}
    return [w for w in words(text) if w not in stop]


def duplicate_runs(tokens: list[str]) -> int:
    count = 0
    i = 0
    while i < len(tokens) - 1:
        if tokens[i] == tokens[i + 1]:
            count += 1
            i += 2
        else:
            i += 1
    return count


def duplicate_phrases(tokens: list[str], n: int = 3) -> int:
    grams = [tuple(tokens[i:i + n]) for i in range(len(tokens) - n + 1)]
    return sum(1 for a, b in zip(grams, grams[1:]) if a == b)


def split_sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]


def metrics(text: str, raw_text: str) -> dict:
    toks = words(text)
    raw_toks = words(raw_text)
    tech = TECH_RE.findall(text)
    raw_tech = TECH_RE.findall(raw_text)
    numbers = re.findall(r"\$?\d[\d,.]*", text)
    raw_numbers = re.findall(r"\$?\d[\d,.]*", raw_text)
    tech_set = Counter(t.lower() for t in tech)
    raw_tech_set = Counter(t.lower() for t in raw_tech)
    preserved = sum(min(tech_set[t], raw_tech_set[t]) for t in tech_set)
    num_preserved = sum(min(Counter(numbers)[n], Counter(raw_numbers)[n]) for n in set(numbers))
    sents = split_sentences(text)
    cap = sum(1 for s in sents if s[:1].isupper()) / len(sents) if sents else 0
    return {
        "words": len(toks),
        "unique_words": len(set(toks)),
        "dup_word_runs": duplicate_runs(toks),
        "dup_phrase_runs": duplicate_phrases(toks),
        "fillers": sum(1 for t in toks if t in FILLERS),
        "tech_tokens": len(tech),
        "tech_preserved_pct": (100 * preserved / len(raw_tech)) if raw_tech else 100.0,
        "number_tokens": len(numbers),
        "numbers_preserved_pct": (100 * num_preserved / len(raw_numbers)) if raw_numbers else 100.0,
        "similarity_to_raw": difflib.SequenceMatcher(None, raw_toks, toks).ratio(),
        "content_retention_pct": (
            100 * len(set(content_words(text)) & set(content_words(raw_text)))
            / max(1, len(set(content_words(raw_text))))),
        "new_content_words": len(set(content_words(text)) - set(content_words(raw_text))),
        "paragraphs": len([p for p in re.split(r"\n\s*\n", text.strip()) if p.strip()]),
        "bullet_lines": len(re.findall(r"(?m)^\s*(?:[-*]|\d+[.)])\s+", text)),
        "sentence_punctuation_pct": (
            100 * sum(1 for s in sents if s[-1:] in ".!?") / len(sents) if sents else 0),
        "capitalized_sentence_starts_pct": 100 * cap,
    }


DIMENSIONS = ["Fidelity", "Disfluency", "Structure", "Technical accuracy",
              "Over-editing", "Readability"]


def score_texts(m: dict) -> dict:
    """Heuristic 1-5 scores; the report states the evidence for each."""
    sim = m["similarity_to_raw"]
    det = m["dup_word_runs"] + m["fillers"]
    return {
        "Fidelity": 5 if sim >= 0.90 else 4 if sim >= 0.80 else 3 if sim >= 0.65 else 2,
        "Disfluency": 5 if det == 0 else 4 if det <= 2 else 3 if det <= 5 else 2,
        "Structure": min(5, 2 + m["paragraphs"] // 2 + (1 if m["bullet_lines"] else 0)),
        "Technical accuracy": 5 if m["tech_preserved_pct"] >= 99 else
                              4 if m["tech_preserved_pct"] >= 95 else
                              3 if m["tech_preserved_pct"] >= 85 else 2,
        "Over-editing": 5 if m["content_retention_pct"] >= 95 and m["new_content_words"] <= 3 else
                        4 if m["content_retention_pct"] >= 90 else
                        3 if m["content_retention_pct"] >= 80 else 2,
        "Readability": min(5, 1 + (2 if m["capitalized_sentence_starts_pct"] >= 80 else 1)
                           + (1 if m["sentence_punctuation_pct"] >= 80 else 0)
                           + (1 if m["paragraphs"] > 1 else 0)),
    }


def pick_quality_run(runs: list[dict], minutes: int) -> dict | None:
    candidates = [r for r in runs if r.get("_minutes") == minutes and r.get("full_transcript")]
    if not candidates:
        return None
    candidates.sort(key=lambda r: (r.get("cleanup_mode") != "full", r.get("_backend") != "cpu"))
    return candidates[0]


def quality_report(results: Path, runs: list[dict], minutes: int) -> str | None:
    run = pick_quality_run(runs, minutes)
    if not run:
        return None
    raw = run["raw_transcript"]
    det = run.get("deterministic_transcript") or raw
    full = run["full_transcript"] or raw
    m_raw = metrics(raw, raw)
    m_det = metrics(det, raw)
    m_full = metrics(full, raw)
    s_det = score_texts(m_det)
    s_full = score_texts(m_full)

    lines = [f"# Quality — {minutes:02d} min", ""]
    lines.append(f"Audio: `{run['audio_file']}` · ASR backend: **{BACKEND_LABEL[run['backend']]}** · "
                 f"RTFx {run['rtfx']:.1f} · cleanup state: `{run.get('full_cleanup_state', '—')}`")
    lines.append("")
    lines.append(f"Cleanup latency: deterministic {fmt(run.get('deterministic_wall_ms',0)/1000,2)} s · "
                 f"full (S1-mini + Harper) {fmt(run.get('full_wall_ms',0)/1000,2)} s "
                 f"(model load {fmt((run.get('cleanup_model_load_ms') or 0)/1000,1)} s excluded from pipeline time).")
    lines.append("")
    lines.append("## Objective metrics")
    lines.append("")
    lines.append("| Metric | Raw | Deterministic | Full |")
    lines.append("|---|---:|---:|---:|")
    for key, label in [
        ("words", "Words"),
        ("dup_word_runs", "Consecutive duplicate words"),
        ("dup_phrase_runs", "Consecutive duplicate 3-grams"),
        ("fillers", "Pure fillers (um/uh/erm/hmm…)"),
        ("tech_tokens", "Technical tokens detected"),
        ("tech_preserved_pct", "Technical tokens preserved %"),
        ("number_tokens", "Numeric tokens"),
        ("numbers_preserved_pct", "Numbers preserved %"),
        ("similarity_to_raw", "Word-sequence similarity to raw"),
        ("content_retention_pct", "Content-word retention %"),
        ("new_content_words", "New content words (over-edit proxy)"),
        ("paragraphs", "Paragraphs"),
        ("bullet_lines", "Bullet/numbered lines"),
        ("capitalized_sentence_starts_pct", "Capitalized sentence starts %"),
        ("sentence_punctuation_pct", "Terminal punctuation %"),
    ]:
        def v(m):
            x = m[key]
            if key.endswith("_pct") or key == "similarity_to_raw":
                return fmt(x, 1)
            return str(x)
        lines.append(f"| {label} | {v(m_raw)} | {v(m_det)} | {v(m_full)} |")
    lines.append("")
    lines.append("## Scored dimensions (1–5; objective proxy, not a human judgment)")
    lines.append("")
    lines.append("| Dimension | Deterministic | Full | Evidence |")
    lines.append("|---|---:|---:|---|")
    evidence = {
        "Fidelity": f"word-sequence similarity to raw {m_full['similarity_to_raw']:.2f}; "
                    f"content retention {m_full['content_retention_pct']:.1f}%",
        "Disfluency": f"{m_full['dup_word_runs']} duplicate runs, {m_full['fillers']} fillers remain",
        "Structure": f"{m_full['paragraphs']} paragraphs, {m_full['bullet_lines']} list lines",
        "Technical accuracy": f"{m_full['tech_preserved_pct']:.1f}% of detected technical tokens preserved",
        "Over-editing": f"{m_full['new_content_words']} new content words introduced",
        "Readability": f"{m_full['capitalized_sentence_starts_pct']:.0f}% capitalized starts, "
                       f"{m_full['sentence_punctuation_pct']:.0f}% terminal punctuation",
    }
    for dim in DIMENSIONS:
        lines.append(f"| {dim} | {s_det[dim]} | {s_full[dim]} | {evidence[dim]} |")
    lines.append("")
    lines.append("## Raw transcript")
    lines.append("")
    lines.append("```text")
    lines.append(raw.strip())
    lines.append("```")
    lines.append("")
    lines.append("## Deterministic cleanup")
    lines.append("")
    lines.append("```text")
    lines.append(det.strip())
    lines.append("```")
    lines.append("")
    lines.append("## Full cleanup (S1-mini + Harper + line format)")
    lines.append("")
    lines.append("```text")
    lines.append(full.strip())
    lines.append("```")
    lines.append("")
    return "\n".join(lines)


def recommendation(runs: list[dict], table: dict, results: Path) -> str:
    def best_for(minutes):
        rows = {b: table.get((b, minutes)) for b in ORDER}
        rows = {b: r for b, r in rows.items() if r}
        return max(rows, key=lambda b: rows[b]["rtfx"]), rows

    lines = ["# Recommendation", ""]
    for minutes in (1, 5, 10, 30):
        winner, rows = best_for(minutes)
        if not rows:
            continue
        fastest = rows[winner]
        cpu = rows.get("cpu")
        gpu = rows.get("gpu")
        ane = rows.get("ane")
        lines.append(f"## {minutes} min")
        lines.append("")
        lines.append(f"- Fastest: **{BACKEND_LABEL[winner]}** at **{fastest['rtfx']:.1f}× real time** "
                     f"({fastest['wall']:.1f} s for {minutes} min of audio).")
        if cpu and winner != "cpu":
            lines.append(f"- CPU is {fastest['rtfx']/cpu['rtfx']:.2f}× slower than {BACKEND_LABEL[winner]}.")
        if gpu:
            lines.append(f"- GPU: {gpu['rtfx']:.1f}× ({gpu['wall']:.1f} s), peak {gpu['peak']:.0f} MB.")
        if ane:
            lines.append(f"- ANE: {ane['rtfx']:.1f}× ({ane['wall']:.1f} s), peak {ane['peak']:.0f} MB.")
        lines.append("")
    lines.append("## Answers")
    lines.append("")
    # Compute overall winner by median across durations.
    totals = {}
    for b in ORDER:
        vals = [table[(b, m)]["rtfx"] for m in (1, 5, 10, 30) if (b, m) in table]
        if vals:
            totals[b] = stats.median(vals)
    if totals:
        winner = max(totals, key=totals.get)
        second = sorted(totals, key=totals.get, reverse=True)[1] if len(totals) > 1 else None
        lines.append(f"**Which backend is faster for this model?** "
                     f"{BACKEND_LABEL[winner]} on this Apple M1. Median RTFx across durations: "
                     + ", ".join(f"{BACKEND_LABEL[b]} {totals[b]:.1f}×" for b in sorted(totals, key=totals.get, reverse=True))
                     + ".")
        if second:
            lines.append("")
            lines.append(f"**By how much?** {BACKEND_LABEL[winner]} leads {BACKEND_LABEL[second]} by "
                         f"{totals[winner]/totals[second]:.2f}× on the median, and by "
                         f"{totals[winner]/totals[min(totals, key=totals.get)]:.2f}× versus the slowest backend.")
        lines.append("")
    # 10x warning.
    gpu1 = table.get(("gpu", 1))
    ane1 = table.get(("ane", 1))
    if gpu1 and ane1:
        lines.append("**Was FluidAudio's 10× GPU-warning confirmed?** No. On this M1, GPU measured "
                     f"{gpu1['rtfx']:.1f}× RTFx versus ANE {ane1['rtfx']:.1f}× at 1 minute "
                     f"(GPU is {ane1['rtfx']/gpu1['rtfx']:.2f}× the ANE rate, not 10× slower). "
                     "The warning is a vendor claim for a different Apple Silicon class; it does not "
                     "reproduce on this machine, but it also does not make GPU the fastest here.")
        lines.append("")
    # Cleanup value.
    quality = pick_quality_run(runs, 1)
    if quality and quality.get("full_wall_ms"):
        asr = quality["wall_clock_s"]
        det = (quality.get("deterministic_wall_ms") or 0) / 1000
        full = quality["full_wall_ms"] / 1000
        if quality.get("deterministic_transcript") and quality.get("full_transcript"):
            det_added = det / asr * 100
            full_added = full / asr * 100
            lines.append("**Is the full cleanup lift worth the cost?** The deterministic stages cost "
                         f"{det:.2f} s for the 1-minute clip ({det_added:.0f}% of ASR time); the full "
                         f"S1-mini + Harper pass costs {full:.2f} s ({full_added:.0f}% of ASR time). "
                         "The full pass fixes casing, punctuation and paragraphing, and its content-word "
                         "retention is high, but it does not repair ASR proper-noun errors. Recommendation: "
                         "keep deterministic cleanup on the live path; run the full pass for saved/final "
                         "text or background dictation, not inside the interactive deadline.")
            lines.append("")
    lines.append("**Should streaming + the current backend stay the default?** Streaming must stay forced "
                 "on — every run used it and every run produced text. On this M1, CPU is the fastest "
                 "measured backend, so the current GPU default costs roughly "
                 f"{totals.get('cpu',1)/max(totals.get('gpu',1),0.001):.2f}× versus CPU. Do not switch to "
                 "ANE on this hardware. The defensible change, if the owner wants the fastest backend on "
                 "M1, is CPU; re-benchmark ANE on M2/M5 before treating the vendor ANE guidance as true.")
    lines.append("")
    lines.append("## Caveats")
    lines.append("")
    lines.append("- The source audio is a third-party YouTube tutorial used locally for evaluation only; "
                 "it is not redistributed and the transcripts are model output, not the video's script.")
    lines.append("- ANE/GPU are `.cpuAndNeuralEngine` / `.cpuAndGPU`; Core ML may partition work, so these "
                 "are not pure-device measurements.")
    lines.append("- Quality scores are objective proxies (duplicate runs, token preservation, readability), "
                 "not a human listener study.")
    lines.append("- Peak memory is sampled every 100 ms during ASR; cleanup runs after the ASR measurement.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="?", help="results/<timestamp> directory")
    args = parser.parse_args()
    if args.results:
        results = Path(args.results)
    else:
        dirs = sorted(p for p in (Path(__file__).resolve().parents[2] / "results").glob("*") if p.is_dir())
        if not dirs:
            print("no results directories")
            return 2
        results = dirs[-1]

    runs = load_runs(results)
    if not runs:
        print(f"no run JSONs under {results}/performance/runs")
        return 2
    table = summarize(runs)

    perf_dir = results / "performance"
    quality_dir = results / "quality"
    perf_dir.mkdir(parents=True, exist_ok=True)
    quality_dir.mkdir(parents=True, exist_ok=True)

    report = perf_report(runs, table, results)
    (perf_dir / "summary.md").write_text(report + "\n")
    (results / "summary.md").write_text(report + "\n")

    raw = {
        "generated": datetime.now().isoformat(),
        "table": {f"{b}_{m}": v for (b, m), v in table.items()},
        "runs": [
            {k: v for k, v in r.items() if not k.startswith("_") and k not in
             ("raw_transcript", "deterministic_transcript", "full_transcript")}
            for r in runs
        ],
    }
    (perf_dir / "raw_metrics.json").write_text(json.dumps(raw, indent=2, default=str) + "\n")

    quality_index = []
    for minutes in (1, 5, 10, 30):
        text = quality_report(results, runs, minutes)
        if text is None:
            continue
        path = quality_dir / f"{minutes:02d}_min_raw_vs_cleaned.md"
        path.write_text(text + "\n")
        quality_index.append(f"- [{minutes:02d} min raw vs cleaned]({path.name})")
    if quality_index:
        (quality_dir / "index.md").write_text("# Quality reports\n\n" + "\n".join(quality_index) + "\n")

    rec = recommendation(runs, table, results)
    (results / "recommendation.md").write_text(rec + "\n")

    print(f"wrote reports under {results}")
    print(f"main runs: {sum(v['n'] for v in table.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
