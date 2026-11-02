#!/usr/bin/env python3
"""Audit the Superflow post-ASR tech dictionary.

Reads the v3 {version, entries:[{canonical, aliases[]}]} file in chunks,
never loading more than CHUNK entries into the report at once, and writes:

    audit/report.md
    audit/collisions.csv
    audit/duplicate_canonicals.csv
    audit/common_word_risk.csv
    audit/destructive_aliases.csv
    audit/stats.csv

Usage:
    python3 scripts/audit_vocab.py [path-to-dictionary.json]
"""

from __future__ import annotations

import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DICT = ROOT / "Packages/L2-Engines/catalog/tech-dictionary.json"
AUDIT = ROOT / "audit"
CHUNK = 150
COMMON_WORDS = 30_000
TOKEN_RE = re.compile(r"[a-z0-9]+")


def load_wordfreq():
    try:
        from wordfreq import top_n_list
        return set(top_n_list("en", COMMON_WORDS))
    except Exception:
        pass
    # Deterministic fallback: the system word list, filtered to short entries.
    for path in (Path("/usr/share/dict/words"), Path("/usr/dict/words")):
        if path.exists():
            words = {w.strip().lower() for w in path.read_text(errors="ignore").splitlines()}
            return {w for w in words if w.isalpha() and len(w) <= 14}
    return set()


WORDS = load_wordfreq()
PRODUCT_HINTS = {
    "web": ("react", "next", "vue", "svelte", "astro", "remix", "angular", "solid", "nuxt",
            "tailwind", "vite", "webpack", "rollup", "esbuild", "turbo", "parcel", "shadcn",
            "radix", "tanstack", "zustand", "redux", "trpc", "graphql", "apollo", "prisma",
            "drizzle", "supabase", "firebase", "vercel", "netlify", "cloudflare", "html", "css",
            "javascript", "typescript", "jsx", "tsx"),
    "ai-models": ("gpt", "claude", "gemini", "llama", "qwen", "deepseek", "mistral", "grok",
                  "kimi", "glm", "muse", "nemotron", "whisper", "openai", "anthropic", "vllm",
                  "ollama", "unsloth", "gguf", "quant", "lora", "moe", "token", "embedding"),
    "infra": ("docker", "kubernetes", "k8s", "pod", "helm", "terraform", "nginx", "ingress",
              "aws", "gcp", "azure", "lambda", "serverless", "redis", "postgres", "mongodb",
              "sqlite", "kafka", "rabbitmq", "grafana", "prometheus", "linux", "ubuntu"),
    "hardware": ("nvidia", "amd", "intel", "apple", "rtx", "radeon", "dgx", "gb", "h100", "a100",
                 "m3", "m4", "mac", "cpu", "gpu", "ram", "ssd", "tensor"),
    "python": ("python", "django", "flask", "fastapi", "pandas", "numpy", "pytest", "poetry",
               "uv", "ruff", "mypy"),
    "rust": ("rust", "cargo", "tokio", "serde", "axum", "tauri", "wasm"),
    "mobile": ("ios", "swift", "swiftui", "uikit", "android", "kotlin", "flutter", "react native"),
    "command": ("git", "npm", "pnpm", "yarn", "brew", "curl", "bash", "zsh", "shell", "cli"),
}
CATEGORIES = list(PRODUCT_HINTS) + ["core"]


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def is_common_token(token: str) -> bool:
    return token in WORDS


def common_risk(text: str) -> tuple[int, str]:
    """Return (score, reason). 0 means no flag.

    A single token in the top-30k is risky. A multi-token phrase is risky only
    when every token is in the top-30k (ordinary English phrase).
    """
    parts = tokens(text)
    if not parts:
        return 0, ""
    common = [p for p in parts if is_common_token(p)]
    if len(parts) == 1 and common:
        return 2, "single common word"
    if len(parts) > 1 and len(common) == len(parts):
        return 1, "all tokens are common words"
    return 0, ""


def category(canonical: str, alias_text: str = "") -> str:
    haystack = (canonical + " " + alias_text).lower()
    for name, hints in PRODUCT_HINTS.items():
        if any(h in haystack for h in hints):
            return name
    return "core"


def alias_owner_map(entries: list[dict]) -> dict[str, set[str]]:
    owners: dict[str, set[str]] = defaultdict(set)
    for entry in entries:
        canonical = entry["canonical"]
        for alias in entry.get("aliases", []):
            owners[" ".join(tokens(alias))].add(canonical)
        owners[" ".join(tokens(canonical))].add(canonical)
    return owners


def destructive(alias: str, canonical: str, owners: dict[str, set[str]]) -> str:
    alias_tokens = tokens(alias)
    canon_tokens = tokens(canonical)
    if len(alias_tokens) > len(canon_tokens) and alias_tokens[:len(canon_tokens)] == canon_tokens:
        return "alias extends its own canonical; suffix is dropped"
    for owner_text, canonicals in owners.items():
        owner_tokens = owner_text.split()
        if not owner_tokens or owner_tokens == alias_tokens:
            continue
        if len(alias_tokens) > len(owner_tokens) and alias_tokens[:len(owner_tokens)] == owner_tokens:
            for owner in canonicals:
                if owner != canonical and " ".join(tokens(owner)) != " ".join(canon_tokens):
                    return f"alias extends '{' '.join(owner_tokens)}' ({owner}); suffix is dropped"
    return ""


def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DICT
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    AUDIT.mkdir(exist_ok=True)

    owners = alias_owner_map(entries)
    collisions = []
    dup_canon = []
    risk = []
    destructive_rows = []
    stats = Counter()
    identity = 0
    alias_total = 0
    longest = []
    canon_count = Counter(entry["canonical"].strip().lower() for entry in entries)

    for start in range(0, len(entries), CHUNK):
        chunk = entries[start:start + CHUNK]
        for entry in chunk:
            canonical = entry.get("canonical", "").strip()
            aliases = [a.strip() for a in entry.get("aliases", []) if a.strip()]
            cat = category(canonical, " ".join(aliases))
            stats[cat] += 1
            stats["aliases"] += len(aliases)
            alias_total += len(aliases)
            canon_tokens = " ".join(tokens(canonical))
            for alias in aliases:
                alias_tokens = " ".join(tokens(alias))
                if not alias_tokens:
                    continue
                if alias.lower() == canonical.lower():
                    identity += 1
                other = owners.get(alias_tokens, set()) - {canonical}
                if other:
                    collisions.append([alias, canonical, "; ".join(sorted(other))])
                score, reason = common_risk(alias)
                if score:
                    risk.append([alias, canonical, score, reason, cat])
                reason = destructive(alias, canonical, owners)
                if reason:
                    destructive_rows.append([alias, canonical, reason])
                if len(alias_tokens.split()) >= 4:
                    longest.append((len(alias_tokens.split()), alias, canonical))

    for canonical, count in sorted(canon_count.items()):
        if count > 1:
            dup_canon.append([canonical, count])

    # Canonical-only common-word risk is useful even when aliases are clean.
    for entry in entries:
        canonical = entry["canonical"].strip()
        score, reason = common_risk(canonical)
        if score:
            risk.append([canonical, canonical, score, reason + " (canonical)", category(canonical)])

    collisions.sort(key=lambda r: (r[0].lower(), r[1]))
    risk.sort(key=lambda r: (-int(r[2]), r[0].lower()))
    destructive_rows.sort(key=lambda r: (r[0].lower(), r[1]))
    longest.sort(reverse=True)

    write_csv(AUDIT / "collisions.csv", ["alias", "canonical", "other_canonicals"], collisions)
    write_csv(AUDIT / "duplicate_canonicals.csv", ["canonical", "count"], dup_canon)
    write_csv(AUDIT / "common_word_risk.csv", ["alias", "canonical", "score", "reason", "pack"], risk)
    write_csv(AUDIT / "destructive_aliases.csv", ["alias", "canonical", "reason"], destructive_rows)
    write_csv(AUDIT / "stats.csv", ["metric", "value"],
              [["entries", len(entries)], ["aliases", alias_total],
               ["identity_alias_percent", f"{(100 * identity / alias_total) if alias_total else 0:.1f}"],
               *[[f"pack:{k}", v] for k, v in sorted(stats.items()) if k != "aliases"]])

    lines = [
        "# Tech dictionary audit",
        "",
        f"Source: `{path.relative_to(ROOT)}` — {len(entries)} entries, {alias_total} aliases.",
        f"Common-word list: {len(WORDS)} tokens (wordfreq top {COMMON_WORDS})" if WORDS else
        "Common-word list: unavailable; common-word checks are disabled.",
        "",
        "## Summary",
        "",
        f"- Alias collisions: **{len(collisions)}**",
        f"- Duplicate canonical forms: **{len(dup_canon)}**",
        f"- Common-word risk rows: **{len(risk)}**",
        f"- Destructive aliases: **{len(destructive_rows)}**",
        f"- Identity aliases: **{identity}/{alias_total}** ({100 * identity / alias_total:.1f}%)",
        "",
    ]
    if collisions:
        lines += ["## Alias collisions (top 25)", "", "| alias | canonical | other owners |", "| --- | --- | --- |"]
        lines += [f"| `{a}` | {c} | {o} |" for a, c, o in collisions[:25]]
        lines += ["", f"Full list: `audit/collisions.csv` ({len(collisions)} rows).", ""]
    if dup_canon:
        lines += ["## Duplicate canonicals", "", "| canonical | count |", "| --- | --- |"]
        lines += [f"| {c} | {n} |" for c, n in dup_canon]
        lines += [""]
    if risk:
        lines += ["## Common-word risk (top 30)", "", "| alias | canonical | score | reason | pack |",
                  "| --- | --- | --- | --- | --- |"]
        lines += [f"| `{a}` | {c} | {s} | {r} | {p} |" for a, c, s, r, p in risk[:30]]
        lines += ["", f"Full list: `audit/common_word_risk.csv` ({len(risk)} rows).", ""]
    if destructive_rows:
        lines += ["## Destructive aliases (top 30)", "", "| alias | canonical | reason |", "| --- | --- | --- |"]
        lines += [f"| `{a}` | {c} | {r} |" for a, c, r in destructive_rows[:30]]
        lines += ["", f"Full list: `audit/destructive_aliases.csv` ({len(destructive_rows)} rows).", ""]
    if longest:
        lines += ["## Longest aliases (top 15)", "", "| words | alias | canonical |", "| --- | --- | --- |"]
        lines += [f"| {n} | `{a}` | {c} |" for n, a, c in longest[:15]]
        lines += [""]
    lines += ["## Entries per pack", "", "| pack | entries |", "| --- | --- |"]
    lines += [f"| {k} | {v} |" for k, v in sorted(stats.items()) if k != "aliases"]

    (AUDIT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote audit/report.md and 5 CSVs ({len(entries)} entries, {alias_total} aliases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
