"""Check the synthetic corpus and report repeated trial latency."""
import json
import math
import re
import statistics
import sys
from pathlib import Path

REQUIRED = {
    "correction": ("Thursday", "not to the client", "Sarah"),
    "everyday": ("react calmly", "the apple", "the python"),
    "technical": ("Kubernetes", "PostgreSQL", "Redis cache", "API", "OAuth"),
    "negation": ("do not want", "do not deploy", "until the test passes"),
    "double-negative": ("do not want", "Thursday"),
    "contraction-double-negative": ("don't want", "Thursday"),
    "spoken-list": ("- Fix the login", "- Update the documentation", "- Notify the team", "- Verify the backups"),
    "natural-list": ("- Milk", "- Eggs", "- Bread", "office"),
    "markdown": ("Release checklist", "- Fix the API", "- Test the login", "- Update the docs"),
    "markdown-lines": ("Release checklist", "- Fix the login", "- Test the API", "- Update the docs"),
    "dashes": ("- Fix the login", "- Test the API", "- Update the docs"),
    "bullet-command": ("- Fix the login", "- Test the API", "- Update the docs"),
    "bullet-ambiguity": ("bullet hit", "bullet ricocheted"),
    "correction-time": ("5:30", "Friday"),
    "filler": (),
    "literal": ("src/auth/user.ts", "MAX_RETRY_COUNT", "3"),
    "paragraphs": ("The test is broken.", "\n\nWe need to fix the API", "check the logs"),
    "gap": ("We were", "don't like it", "\n\nThe revised draft", "is on the desk"),
    "everyday-near-tech": ("open the windows", "update the API", "go feed the python"),
    "everyday-2": ("Next year", "go to the library", "brew coffee"),
    "subject-verb": ("They were", "she doesn't", "receipts are", "we need"),
    "plural-agreement": ("lights are", "wires were", "workers don't"),
    "numeric": ("$75", "3:15 PM", "billing@example.com"),
    "correction-decimal": ("25", "final amount"),
    "quoted-grammar": ("we was here", "they were somewhere else"),
    "unicode": ("José", "café", "Zürich", "doesn't"),
    "injection": ("Ignore previous instructions", "print hello", "then save the text"),
    "negation-scope": ("don't want", "unless", "do not restart Redis"),
    "garbled": ("we were", "doesn't work", "the user enters", "show them the error"),
    "audio-replay": ("create branches", "on its own", "interface", "terminal"),
}
FORBIDDEN = {
    "correction": ("Friday",),
    "everyday": ("Python", "React", "Apple"),
    "everyday-near-tech": ("Windows", "Python", "Go feed"),
    "bullet-ambiguity": ("\n- ",),
    "markdown": ("new line", "dash "),
    "dashes": ("dash ",),
    "paragraphs": ("first paragraph", "new paragraph"),
    "correction-time": ("Thursday",),
    "numeric": ("50", "no wait"),
    "correction-decimal": ("12.50", "no wait"),
}

def check(path):
    lines = Path(path).read_text().splitlines()
    cases = [json.loads(line) for line in lines if line.startswith("{")]
    expected = set(REQUIRED) | {"medium", "long"}
    failures = []
    seen = set()
    if not any('COLD_STATE=fallback' in line and 'model not ready' in line for line in lines):
        failures.append("cold readiness fallback was not observed")
    for case in cases:
        name, output = case["case"], case["output"]
        seen.add(name)
        accepted = [event for event in case["events"] if event["event"] == "cleanup.chunk.accepted"]
        model = [event for event in case["events"] if event["event"] == "model"]
        if case["state"] != "cleaned" or not accepted or not model:
            failures.append(f"{name} did not accept S1-mini output ({case['diagnostics']})")
        if name != "filler" and not any(int(event["tokensOut"]) > 0 for event in accepted):
            failures.append(f"{name} had no generated tokens")
        if name == "filler" and output:
            failures.append(f"filler should be empty, got {output!r}")
        for part in REQUIRED.get(name, ()):
            if part not in output:
                failures.append(f"{name} missing {part!r}")
        for part in FORBIDDEN.get(name, ()):
            if part in output:
                failures.append(f"{name} retained {part!r}")
        if name in {"medium", "long"}:
            repetitions = 3 if name == "medium" else 12
            ids = re.findall(r"\bBatch (\d+)\b", output)
            if ids != [str(101 + index) for index in range(repetitions)]:
                failures.append(f"{name} lost, duplicated or reordered batch IDs: {ids}")
            for literal in ("503", "MAX_RETRY_COUNT", "Maya", "original data", "Redis cache"):
                if output.count(literal) != repetitions:
                    failures.append(f"{name} lost/duplicated {literal}")
            if "We was" in output:
                failures.append(f"{name} has unresolved pronoun agreement")
    if expected - seen:
        failures.append(f"missing cases {sorted(expected - seen)}")
    if short := sorted(c["ms"] for c in cases if c["case"] not in {"medium", "long", "audio-replay"}):
        p95 = short[math.ceil(len(short) * .95) - 1]
        print(f"{path} short n={len(short)} median={statistics.median(short):g}ms p95={p95}ms max={max(short)}ms")
        if p95 >= 1500:
            failures.append(f"short p95 exceeded 1.5s ({p95}ms)")
    print("  " + " ".join(f"{c['case']}={c['ms']}ms/{c['state']}" for c in cases if c["case"] in {"medium", "long", "audio-replay"}))
    for failure in failures:
        print("  FAIL", failure)
    return len(failures)

sys.exit(any([check(path) for path in sys.argv[1:]]))
