#!/usr/bin/env python3
"""Read-only risk scan of the v4 catalog: what can fire on ordinary speech.

Prints (never writes) the Tier A aliases whose normalized key is a plain
English word or a plain-English phrase, split by whether the replacement only
changes case or actually rewrites letters.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from wordfreq import top_n_list, zipf_frequency

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Packages/L2-Engines/catalog/vocab_v4.json"
TOKEN_RE = re.compile(r"[a-z0-9']+")

COMMON = set(top_n_list("en", 30000))


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def key(text: str) -> str:
    """Mirror LexiconNormalizer.key: drop 'dot', strip punctuation, join."""
    return "".join(t for p in text.lower().split() if p != "dot" for t in p if t.isalnum() or t == "'")


def main() -> int:
    data = json.loads(CATALOG.read_text())
    tier_a_single_common = []
    tier_a_phrase_common = []
    tier_b_single_common = []
    rewrite = []
    destructive = []
    owners = defaultdict(set)

    canon_by_key = {}
    for entry in data["entries"]:
        canon_by_key.setdefault(key(entry["canonical"]), set()).add(entry["canonical"])
        for alias in entry["aliases"]:
            owners[key(alias["t"])].add(entry["canonical"])

    for entry in data["entries"]:
        canonical = entry["canonical"]
        for alias in entry["aliases"]:
            text = alias["t"]
            parts = tokens(text)
            k = key(text)
            if not parts:
                continue
            all_common = all(p in COMMON for p in parts)
            single = len(parts) == 1 and parts[0] in COMMON
            same_letters = key(canonical) == k
            row = (text, canonical, entry["pack"], alias["tier"])
            if alias["tier"] == "A":
                if single:
                    tier_a_single_common.append(row + (not same_letters,))
                elif all_common:
                    tier_a_phrase_common.append(row + (not same_letters,))
            elif single:
                tier_b_single_common.append(row)

            if not same_letters and alias["tier"] == "A":
                rewrite.append(row + (zipf_frequency(text, "en"),))

            canon_key = key(canonical)
            if len(parts) > 1 and k.startswith(canon_key) and len(k) > len(canon_key):
                destructive.append(row + (text[len(canonical):].strip(),))

    print(f"Tier A single ordinary English word: {len(tier_a_single_common)}")
    for text, canonical, pack, tier, rewrites in sorted(
        tier_a_single_common, key=lambda r: -zipf_frequency(r[0], "en")
    )[:80]:
        print(f"  {text:28} -> {canonical:22} {pack:10} rewrite={rewrites}")
    print(f"\nTier A phrase made only of ordinary words: {len(tier_a_phrase_common)}")
    for text, canonical, pack, tier, rewrites in tier_a_phrase_common[:40]:
        print(f"  {text:34} -> {canonical:22} {pack:10} rewrite={rewrites}")
    print(f"\nTier B single ordinary word: {len(tier_b_single_common)}")
    print(f"Tier A aliases that rewrite letters (not just case): {len(rewrite)}")
    norms: dict[str, list[str]] = defaultdict(list)
    for text, canonical, pack, tier, _ in rewrite:
        norms[canonical].append(text)
    for canonical, aliases in sorted(norms.items(), key=lambda kv: -len(kv[1]))[:40]:
        print(f"  {canonical:26} <- {', '.join(aliases[:8])}{' …' if len(aliases) > 8 else ''}")
    print(f"\nDestructive alias extensions: {len(destructive)}")
    print(f"Colliding keys: {sum(1 for v in owners.values() if len(v) > 1)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
