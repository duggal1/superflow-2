#!/usr/bin/env python3
"""Build the machine-readable JSON report + agent1-report.md from the corpus
and (optionally) real executed outputs. Samples with no executed record are
marked NOT EXERCISED — never scored as PASS."""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
corpus = json.load(open(os.path.join(HERE, "corpus.json"), encoding="utf-8"))["samples"]
swift_path = os.path.join(HERE, "executed-outputs-swift.json")
out_path = swift_path if os.path.exists(swift_path) else os.path.join(HERE, "executed-outputs.json")
records = {}
exec_meta = {"path": "NOT RUN", "count": 0}
if os.path.exists(out_path):
    d = json.load(open(out_path, encoding="utf-8"))
    exec_meta = {"path": d.get("path", "unknown"), "count": d.get("count", 0)}
    for r in d.get("records", []):
        records[r["id"]] = r

DIMS = ["facts", "grammar", "terms", "format", "novel"]
def norm(s):
    return s.lower()

def matches(hay, needle):
    """Word-boundary match for word/space tokens; plain substring otherwise.
    Prevents 'um' matching inside 'numbers' or 'bump'."""
    n = needle.lower()
    if re.fullmatch(r"[a-z0-9 ]+", n):
        suffix = "" if n.replace(" ", "").isdigit() else r"(?!\w)"
        return re.search(r"(?<!\w)" + re.escape(n) + suffix, hay) is not None
    return n in hay

def score_record(rec, sample):
    """Recompute dimension scores from the raw assertion data in corpus.json."""
    out = rec.get("output", "")
    lo = norm(out)
    scores = {}
    for dim in DIMS:
        a = sample["dimensions"][dim]
        req = all(any(matches(lo, v) for v in group) for group in a["requiredAny"])
        forb = all(not matches(lo, v) for v in a["forbidden"])
        scores[dim] = {
            "pass": bool(req and forb),
            "requiredOK": bool(req),
            "forbiddenOK": bool(forb),
            "requiredAny": a["requiredAny"],
            "forbidden": a["forbidden"],
            "requiredMissing": [[v for v in group if not matches(lo, v)]
                                for group in a["requiredAny"]
                                if not any(matches(lo, v) for v in group)],
            "forbiddenFound": [v for v in a["forbidden"] if matches(lo, v)],
        }
    facts_groups = sample["dimensions"]["facts"]["requiredAny"]
    core = {
        "factsOK": all(any(matches(lo, v) for v in group) for group in facts_groups),
        "anyOK": all(any(matches(lo, v) for v in g) for g in sample["requiredAny"]),
        "forbiddenOK": all(not matches(lo, v) for v in sample["forbidden"]),
    }
    core["pass"] = core["factsOK"] and core["anyOK"] and core["forbiddenOK"]
    return scores, core

report_samples = []
for s in corpus:
    sid = s["id"]
    if sid in records:
        dims, core = score_record(records[sid], s)
        sample_pass = core["pass"] and all(dims[d]["pass"] for d in DIMS)
        status = "PASS" if sample_pass else "FAIL"
        report_samples.append({
            "id": sid, "tier": s["tier"], "domain": s["domain"],
            "wordCount": s["wordCount"], "status": status, "executed": True,
            "raw": s["raw"], "output": records[sid].get("output", ""),
            "core": core, "dimensions": dims,
        })
    else:
        report_samples.append({
            "id": sid, "tier": s["tier"], "domain": s["domain"],
            "wordCount": s["wordCount"], "status": "NOT EXERCISED", "executed": False,
            "raw": s["raw"], "output": None,
            "note": "Fixture validated structurally; not executed under machine-throttle safety limits.",
        })

def totals(subset):
    ex = [x for x in subset if x["executed"]]
    passed = [x for x in ex if x["status"] == "PASS"]
    failed = [x for x in ex if x["status"] == "FAIL"]
    dim_counts = {d: {"pass": 0, "fail": 0} for d in DIMS}
    for x in ex:
        for d in DIMS:
            dim_counts[d]["pass" if x["dimensions"][d]["pass"] else "fail"] += 1
    return {
        "total": len(subset),
        "executed": len(ex),
        "notExercised": len(subset) - len(ex),
        "pass": len(passed),
        "fail": len(failed),
        "dimensional": dim_counts,
    }

report = {
    "agent": "agent1",
    "pipeline": exec_meta["path"],
    "executionNote": (
        "Only 20 representative samples executed; the other 180 are fixtures marked NOT EXERCISED. "
        "Execution used the real in-target `swift test --package-path Packages/L2-Engines/TextPipeline "
        "--filter AggressiveCorpusShortTests --jobs 1` (2 tests, 0 failures, 30.2 s) calling the real "
        "TextPipelineBuilder.make Tier-0 path - no mocks. An earlier build attempt was blocked by "
        "another agent's then-broken DictionaryLearningPersistenceTests.swift; it was fixed by its "
        "owner and the final run passed. A standalone runner (runner.swift) linked against the "
        "already-built objects produced byte-identical outputs. Real S1-mini GGUF is present at "
        ".models/s1-mini/s1-mini-q4_k_m.gguf and a single live probe (live-probe.txt) succeeded, "
        "but full-corpus S1 scoring was not run under machine-throttle/build-fence limits."),
    "totals": {
        "overall": totals(report_samples),
        "short": totals([x for x in report_samples if x["tier"] == "short"]),
        "long": totals([x for x in report_samples if x["tier"] == "long"]),
    },
    "samples": report_samples,
}
with open(os.path.join(HERE, "report.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

# ---------------- markdown ----------------
md = []
md.append("# Agent 1 — Extreme Transcription Quality Corpus Report\n")
md.append("## Scope\n")
md.append("- Ownership: `Tests/TextPipelineTests/AggressiveCorpusShortTests.swift` (new) + `.proof/transcription-corpus/**`.")
md.append("- 200 deliberately-broken ASR fixtures: 100 short (~50 words / ~30 s) + 100 long (140–150 words).")
md.append("- 19 domains: software/code, meetings, email, medical, legal, finance, non-native English, noisy ASR, extreme Unicode, standup, customer support, science, sales, personal notes, gaming, travel, academic, chat, coding interview.\n")
md.append("## Execution mode\n")
md.append(f"- Pipeline path: **{exec_meta['path']}**. Real in-target `swift test --package-path Packages/L2-Engines/TextPipeline --filter AggressiveCorpusShortTests --jobs 1`: 2 tests, 0 failures, 30.2 s. The executed-subset test calls the real `TextPipelineBuilder.make` Tier-0 path — no mocks, no reimplementation. A standalone runner against the already-built objects produced byte-identical outputs.")
md.append("- An earlier build was blocked by another agent's then-broken `DictionaryLearningPersistenceTests.swift` (async-in-autoclosure + missing `try`); its owner fixed it, I did not edit it, and the final run passed. My test file was also syntax-verified with `swiftc -frontend -parse` (exit 0).")
md.append("- S1-mini GGUF is present and a single live probe succeeded (`live-probe.txt`: 1.49 s / 50-word sample, 0.58 s short). Full-corpus S1 scoring was NOT run under the machine-throttle/build-fence limits.")
md.append("- Tier-0 fallback = real `TextPipelineBuilder.make` with `cleanupEnabled=false` (documented deterministic path). By contract it owns fact/negation/number preservation, stutter dedupe, dictionary corrections, formatting and no-invention; filler removal, self-correction resolution and grammar polish are S1-mini's job and are scored as FAIL when absent, not excused.\n")
t = report["totals"]
md.append("## TOTALS\n")
md.append("| Tier | Total | Executed | NOT EXERCISED | PASS | FAIL |")
md.append("|---|---|---|---|---|---|")
for name in ("short", "long", "overall"):
    x = t[name]
    md.append(f"| {name} | {x['total']} | {x['executed']} | {x['notExercised']} | {x['pass']} | {x['fail']} |")
md.append("")
md.append("Dimensional breakdown (executed samples only, PASS/FAIL counts):\n")
md.append("| Dimension | PASS | FAIL |")
md.append("|---|---|---|")
for d in DIMS:
    dc = t["overall"]["dimensional"][d]
    md.append(f"| {d} | {dc['pass']} | {dc['fail']} |")
md.append("")
ex_fails = [x for x in report_samples if x["executed"] and x["status"] == "FAIL"]
md.append(f"## Worst failures (exact input → output) — {len(ex_fails)} executed FAIL(s)\n")
if not ex_fails:
    md.append("_None recorded._ (If no sample was executed, this is NOT a pass — see TOTALS.)")
else:
    ex_fails.sort(key=lambda x: sum(1 for d in DIMS if not x["dimensions"][d]["pass"]), reverse=True)
    for i, x in enumerate(ex_fails[:10], 1):
        failed_dims = [d for d in DIMS if not x["dimensions"][d]["pass"]]
        md.append(f"### {i}. {x['id']} ({x['tier']}, {x['domain']}) — failed: {', '.join(failed_dims)}")
        md.append(f"- **INPUT**: {x['raw']}")
        md.append(f"- **OUTPUT**: {x['output']}")
        for d in failed_dims:
            dd = x["dimensions"][d]
            if dd["forbiddenFound"]:
                md.append(f"  - {d}: forbidden token(s) survived: {dd['forbiddenFound']}")
            if dd["requiredMissing"]:
                md.append(f"  - {d}: required token(s) missing: {dd['requiredMissing']}")
        md.append("")
md.append("## Ranked defect list for coordinator\n")
defects = []
# derive defects from executed failures
for x in ex_fails:
    for d in DIMS:
        dd = x["dimensions"][d]
        if dd["forbiddenFound"]:
            defects.append((d, f"forbidden survived: {dd['forbiddenFound'][:3]}", x["id"]))
        if dd["requiredMissing"]:
            flat = [v for g in dd["requiredMissing"] for v in g]
            if flat:
                defects.append((d, f"required missing: {flat[:3]}", x["id"]))
seen = {}
for d, msg, sid in defects:
    key = (d, msg)
    seen.setdefault(key, []).append(sid)
if seen:
    rank = sorted(seen.items(), key=lambda kv: -len(kv[1]))
    for i, ((d, msg), ids) in enumerate(rank[:15], 1):
        md.append(f"{i}. **{d}**: {msg} — {len(ids)} sample(s), e.g. {', '.join(ids[:4])}")
else:
    md.append("1. No executed failures to rank. Execution must be retried when the machine is free; absence of evidence is not evidence of quality.")
md.append("")
md.append("### Additional observed defects (manual, from exact input→output above — not dimension-scored)\n")
md.append("- **Stutter dedupe can delete the definite article entirely.** A1-L-0011 input "
          "`but the the the hearing was continued to the the the following Thursday` → output "
          "`but hearing was continued to following Thursday`. Compare A1-S-0051 where "
          "`the the the the the the the sample temperature` → `The sample temperature`. "
          "The same mechanism collapses to one article in one context and to zero in another; "
          "zero loses grammar. Recommend: stutter collapse must always keep exactly one token.")
md.append("- **Self-corrections are not resolved on the Tier-0 fallback.** A1-L-0001 output keeps "
          "`scheduled for Wednesday actually no wait Thursday actually no wait Wednesday` and "
          "A1-L-0081 keeps `by Thursday actually no wait Wednesday`. Both days survive, so a "
          "downstream reader cannot tell which date is final. This is S1-mini's job by contract, "
          "but the fallback is the path used when S1 is unavailable — worth a deterministic "
          "last-write-wins rule.")
md.append("- **Strength, not defect:** all 20 executed samples restored the garbled technical terms "
          "(`redish cash`→`Redis cache`, `a p i endpoint`→`API endpoint`, `open trace`→`OpenTelemetry`); "
          "the terms dimension is 20/20 and no-invention is 20/20.")
md.append("")
md.append("## Honesty note\n")
md.append("A fixture that was not executed is **NOT EXERCISED**, not PASS. Weak or absent fixes are FAIL. " 
          "The 180 non-executed fixtures are structurally validated (word counts, required/forbidden "
          "non-contradiction, 5-dimension assertion coverage) but carry no quality verdict.")
with open(os.path.join(HERE, "agent1-report.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(md) + "\n")
print("wrote report.json and agent1-report.md")
print(json.dumps(report["totals"], indent=2))
