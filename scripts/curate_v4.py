#!/usr/bin/env python3
"""Curate the v4 tech dictionary for day-to-day precision.

Deterministic and idempotent: the rules run to a fixed point, so a second run
produces byte-identical output. Reads and rewrites
``Packages/L2-Engines/catalog/vocab_v4.json`` and records every decision in
``audit/curation.csv``.

Requires ``wordfreq`` (``pip install wordfreq``) for the English word list.
Policy: a false positive is worse than a miss, so ordinary speech is never
rewritten. The engine normalizes case, spacing, hyphens, dots and the spoken
word "dot", which means one alias can collide with a plain English phrase.

Rules, in order:

1. Acronym canonicals are never spelled out in plain English
   ("language model" -> LLM corrupts prose).
2. Destructive suffixes are dropped when the head already matches on its own
   ("aws lambda function" -> "AWS Lambda function", not "AWS Lambda").
3. Ordinary English moves to Tier B (context-gated) with the co-words that
   make it technical, including aliases that share a normalization key and
   aliases whose first word is gated ("spring framework").
4. Aliases that ordinary speech can form from two adjacent words are removed
   ("red is" reaches the key of "redis").
5. Formatting entries: spoken file names and casing-critical identifiers.
"""

from __future__ import annotations

import csv
import difflib
import json
import re
import sys
from pathlib import Path

try:
    from wordfreq import top_n_list, zipf_frequency
except ImportError:  # pragma: no cover - build-time only
    raise SystemExit("Install wordfreq before curating: pip install wordfreq")

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Packages/L2-Engines/catalog/vocab_v4.json"
AUDIT = ROOT / "audit"

COMMON = set(top_n_list("en", 30000))
TOKEN_RE = re.compile(r"[a-z0-9']+")
NUMBER_WORDS = {
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
    "nine", "ten", "eleven", "twelve", "sixteen", "thirty", "hundred",
}
FUNCTION_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "do", "for", "from",
    "he", "her", "his", "i", "if", "in", "is", "it", "me", "my", "no", "not",
    "of", "on", "or", "our", "she", "so", "that", "the", "them", "then", "they",
    "this", "to", "up", "us", "was", "we", "were", "with", "you", "your",
}

# High-signal developer co-words, mirrored from TechDictionaryGate.
DEV_WORDS = {"js", "ts", "react", "api", "sdk", "npm", "pnpm", "deploy", "docker",
             "git", "repo", "component", "model", "edit", "build", "config"}

# Ordinary English words that happen to name a product. The value is the set of
# co-words that make the spoken word technical.
AMBIGUOUS: dict[str, list[str]] = {
    "yarn": ["install", "add", "workspace", "lockfile", "dependency", "dependencies"],
    "cargo": ["install", "toml", "rust", "crate", "crates", "publish", "run"],
    "poetry": ["install", "pyproject", "python", "lock", "dependencies"],
    "flask": ["python", "route", "routes", "app", "endpoint", "wsgi", "jinja"],
    "pandas": ["python", "dataframe", "import", "csv", "series"],
    "jest": ["test", "tests", "testing", "mock", "snapshot", "runner"],
    "playwright": ["test", "tests", "testing", "e2e", "browser", "chromium"],
    "cypress": ["test", "tests", "testing", "e2e", "browser"],
    "postman": ["api", "collection", "request", "endpoint", "graphql"],
    "swagger": ["api", "openapi", "spec", "endpoint", "docs"],
    "recoil": ["react", "state", "atom", "atoms", "selector", "selectors"],
    "stripe": ["payments", "payment", "billing", "checkout", "webhook", "subscription"],
    "aria": ["html", "accessibility", "attribute", "role", "screenreader"],
    "electron": ["desktop", "app", "main", "renderer", "packager"],
    "expo": ["react", "native", "ios", "android", "mobile"],
    "spa": ["react", "vue", "angular", "router", "frontend"],
    "rag": ["llm", "retrieval", "vector", "embedding", "chunk", "chunks"],
    "moe": ["experts", "mixture", "llm", "router"],
    "ram": ["gb", "memory", "bytes", "gigabytes", "mb", "vram"],
    "whisper": ["openai", "model", "speech", "asr", "transcription"],
    "insomnia": ["api", "request", "rest", "graphql", "collection"],
    "railway": ["deploy", "hosting", "database", "postgres"],
    "jax": ["python", "numpy", "training", "tensor", "flax"],
    "prettier": ["config", "format", "formatting", "eslint", "plugin"],
    "sass": ["css", "scss", "styles", "stylesheets", "compiler"],
    "llama": ["model", "models", "cpp", "meta", "quantized", "inference"],
    "azure": ["microsoft", "cloud", "devops", "blob", "functions", "subscription"],
    "vue": ["js", "framework", "component", "components"],
    "blackwell": ["nvidia", "gpu", "architecture", "chip", "cuda"],
    "apache": ["server", "kafka", "http", "license", "webserver"],
    "prometheus": ["metrics", "grafana", "alerting", "scrape"],
    "django": ["python", "orm", "app", "models", "admin"],
    "kafka": ["topic", "topics", "broker", "stream", "streams", "partition"],
    "babel": ["compiler", "plugin", "preset", "transpile"],
    "pip": ["install", "python", "requirements", "wheel"],
    "macos": ["apple", "app", "swift", "xcode"],
    "linux": ["kernel", "server", "ubuntu", "distro"],
    "ubuntu": ["server", "linux", "apt", "install"],
    "nginx": ["server", "proxy", "config", "upstream"],
    "windows": ["microsoft", "os", "server", "app", "install", "wsl"],
    "cursor": ["editor", "code", "ide", "app", "agent"],
    "view": ["component", "render", "template", "vue"],
    "cloud": ["aws", "gcp", "azure", "deploy", "bucket", "function"],
    "swift": ["concurrency", "ios", "package", "xcode", "actor", "async"],
}

# Gated words whose phrases stay gated ("spring framework", "node server").
EXTRA_REQUIRES: dict[str, list[str]] = {
    "next year": ["app", "router", "pages", "vercel", "react"],
    "next years": ["app", "router", "pages", "vercel", "react"],
    "cloud": AMBIGUOUS["cloud"],
    "view": AMBIGUOUS["view"],
    "spring": ["boot", "java", "bean", "framework"],
    "sequel": ["database", "sql", "query", "insert"],
    "lambda": ["aws", "function", "serverless", "handler"],
    "rust": ["cargo", "compiler", "crate", "borrow"],
    "swift": AMBIGUOUS["swift"],
    "ruby": ["rails", "gem", "gems"],
    "java": ["jdk", "jvm", "spring", "maven"],
    "node": ["npm", "server", "runtime", "package", "modules"],
    "express": ["server", "route", "middleware", "node"],
    "render": ["deploy", "hosting", "component", "service"],
    "motion": ["framer", "animation", "spring", "component"],
    "bun": ["install", "runtime", "package", "js"],
    "go": ["golang", "module", "goroutine", "package"],
    "jason": ["parse", "stringify", "config", "object", "response", "schema", "payload"],
}

GATED_HEADS = set(AMBIGUOUS) | set(EXTRA_REQUIRES)

# Spelled-out forms that legitimately expand to an acronym.
SPELLED_OK = {"int eight", "integer eight", "u d q", "qd eight"}

# Plain-English expansions of a product name that are always wrong.
EXPANSION_DELETE = {
    "amazon cloud", "azure cloud", "google cloud", "microsoft azure",
    "visual studio", "command line", "language model", "speech recognition",
    "speech synthesis", "internet protocol", "secure shell", "secure http",
    "http secure", "url address", "web url", "system memory", "video ram",
    "database query", "graph query", "rest service", "container registry",
    "error boundaries", "search optimization", "plain javascript",
    "pure javascript", "java scripted", "java scripts", "transformers python",
    "transformer library", "transformer package", "transformers package",
    "sequel file", "sequel language", "tail winds", "tail winds css",
    "tail wind", "tail wind s", "tailwind class", "tailwind classes",
    "tail wins", "tech stock", "tech track", "technology stack", "text stack",
    "text tack", "text track", "git repository", "microsoft windows",
    "python language", "python programming", "java language", "java programming",
    "rust language", "rust programming", "swift language", "swift programming",
    "ruby language", "ruby programming", "php language", "typescript language",
    "javascript language", "joins hang",
}

# Aliases that must never exist. Each differs from its owner's canonical name;
# the canonical itself is restored by the identity rule.
NEVER = {
    "quick", "quick js", "view", "queen", "quinn", "cotton", "jot", "oath",
    "tokyo", "tory", "tari", "sequel", "spring", "drizzle", "rizzle", "dive",
    "hpm", "ho no", "boon", "the zod", "deep sea", "post grass",
    "lambda function", "story desktop app", "story rust app", "nest gs",
    "next year j s", "moose park", "solid", "go", "rust", "swift", "ruby",
    "java", "node", "express", "render", "motion", "framer", "bun", "remix",
    "astro", "apollo", "elastic", "dynamo", "mongo", "neon", "chroma", "helm",
    "warp", "cursor", "fish", "arch", "rails", "windows",
}

# Words a person means to keep when they say them after a product name:
# "the aws lambda function" is "AWS Lambda function", not "AWS Lambda".
DROPPABLE_SUFFIX = {
    "framework", "app", "apps", "application", "project", "library", "server",
    "model", "models", "ai", "file", "files", "config", "configuration", "web",
    "desktop", "coding", "llm", "llms", "coder", "runtime", "service", "client",
    "api", "sdk", "repo", "repository", "function", "functions", "serverless",
    "package", "manager", "language", "programming", "cli", "command", "deep",
    "test", "tests", "testing", "rest", "format", "formatting", "component",
    "components", "state", "styles",
}

# Suffixes that carry their own identity: "llama cpp" is not "llama".
KEEP_SUFFIX = {"cpp", "c++", "plus", "plusplus", "js", "ts", "css", "sass"}

# Spoken file names and casing-critical identifiers.
FORMAT_ENTRIES: list[tuple[str, str, str, list[str]]] = [
    ("agents-md", "AGENTS.md", "core", ["agents md", "agent md", "agents dot md",
                                        "agents markdown", "agent instructions md"]),
    ("readme-md", "README.md", "core", ["read me md", "readme md", "read me dot md",
                                        "readme markdown"]),
    ("product-md", "PRODUCT.md", "core", ["product md", "product dot md"]),
    ("design-md", "DESIGN.md", "core", ["design md", "design dot md"]),
    ("rules-md", "RULES.md", "core", ["rules md", "rules dot md"]),
    ("plan-md", "PLAN.md", "core", ["plan md", "plan dot md"]),
    ("issue-md", "issue.md", "core", ["issue md", "issue dot md"]),
    ("claude-md", "CLAUDE.md", "core", ["claude md", "claude dot md"]),
    ("git-skills-md", "GIT-SKILLS.md", "core", ["git skills md", "git skills dot md"]),
    ("makefile", "Makefile", "command", ["make file", "make dot file"]),
    ("gitignore", ".gitignore", "command", ["git ignore", "git ignore file"]),
    ("bashrc", ".bashrc", "command", ["bash rc", "bash arc"]),
    ("zshrc", ".zshrc", "command", ["zsh rc", "z shell rc"]),
    ("requirements-txt", "requirements.txt", "python",
     ["requirements txt", "requirements text", "requirements dot txt"]),
    ("pyproject-toml", "pyproject.toml", "python",
     ["py project toml", "py project dot toml"]),
    ("docker-compose", "docker-compose.yml", "infra",
     ["docker compose file", "docker compose yml", "docker compose dot yml"]),
    ("cargo-lock", "Cargo.lock", "rust", ["cargo lock", "cargo dot lock"]),
    ("go-mod", "go.mod", "core", ["go mod", "go dot mod", "go module file"]),
    ("next-config", "next.config.js", "web", ["next config js", "next dot config js"]),
    ("vite-config", "vite.config.ts", "web", ["vite config ts", "vite dot config ts"]),
    ("eslintrc", ".eslintrc", "web", ["es lint rc", "eslint rc"]),
    ("prettierrc", ".prettierrc", "web", ["prettier rc", "prettier config file"]),
    ("npmrc", ".npmrc", "command", ["npm rc", "npm config file"]),
    ("editorconfig", ".editorconfig", "core", ["editor config", "editor config file"]),
    ("swift-package", "Package.swift", "mobile",
     ["package swift", "swift package manifest", "package dot swift"]),
    ("json-schema", "JSON Schema", "web", ["json schema", "j son schema"]),
    ("cicd", "CI/CD", "core", ["c i c d", "ci cd pipeline", "cicd pipeline"]),
]

# Versioned model names: the suffix is the model, so it must survive.
VARIANT_ENTRIES: list[tuple[str, str, str, list[str]]] = [
    ("deepseek-r1", "DeepSeek R1", "ai-models",
     ["deep seek r1", "deep seek r one", "deepseek r1", "deepseek r one",
      "deep seek are one", "deep sick r1"]),
    ("deepseek-v3", "DeepSeek V3", "ai-models",
     ["deep seek v3", "deep seek v three", "deepseek v3", "deepseek v three"]),
    ("mistral-7b", "Mistral 7B", "ai-models",
     ["mistral 7b", "mistral seven b", "mistrel 7b"]),
    ("qwen3-235b", "Qwen3 235B", "ai-models",
     ["qwen3 235b", "qwen 3 235b", "qwen three 235 b", "qwen 3 235 b"]),
    ("get-hub", "GitHub", "command", ["get hub"]),
]


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def key(text: str) -> str:
    """Mirror LexiconNormalizer.key: drop the spoken word "dot", join letters."""
    return "".join(
        c for part in text.lower().split() if part != "dot"
        for c in part if c.isalnum() or c == "'"
    )


def is_acronym(canonical: str) -> bool:
    letters = [c for c in canonical if c.isalpha()]
    return (2 <= len(letters) <= 7 and all(c.isupper() for c in letters)
            and " " not in canonical.strip() and not any(c.islower() for c in canonical))


def is_spelled(parts: list[str]) -> bool:
    """Spelled letters or version tokens: "a w s", "c plus plus"."""
    return all(len(p) <= 1 or p in NUMBER_WORDS or p.isdigit() or p == "point"
               for p in parts)


def has_version(parts: list[str]) -> bool:
    """A version or number token: "glm five", "gpt 5.6", "claude sonnet 4.5"."""
    return any(p.isdigit() or p in NUMBER_WORDS or p == "point" for p in parts)


def phonetic(alias_key: str, canonical: str) -> bool:
    """True when the alias is a plausible mishearing of the canonical.

    "jay son" is how JSON sounds; "language model" is a different term that
    happens to expand to LLM.
    """
    ratio = difflib.SequenceMatcher(None, alias_key, key(canonical)).ratio()
    return ratio >= 0.55


def droppable(parts: list[str], entry: dict) -> bool:
    """True when a shorter alias covers this one and the rest is filler.

    Only whole filler words are droppable. A version ("hekau 4.5") or a real
    word the speaker meant ("c plus plus") stays part of the match.
    """
    if any(p.isdigit() or p in NUMBER_WORDS or p == "point" for p in parts):
        if any(c.isdigit() for c in entry["canonical"]):
            return False
    for other in entry["aliases"]:
        other_parts = tokens(other["t"])
        if not (0 < len(other_parts) < len(parts)
                and parts[:len(other_parts)] == other_parts):
            continue
        suffix = parts[len(other_parts):]
        if not suffix or not all(p in DROPPABLE_SUFFIX and p not in KEEP_SUFFIX
                                for p in suffix):
            continue
        if other["tier"] == "A":
            return True
        # A gated head keeps the phrase when dropping the suffix would also
        # drop the only dev signal that lets the head fire.
        if (set(other.get("requires") or []) | DEV_WORDS).intersection(suffix):
            return True
    return False


def cross_token_risk(alias_key: str) -> bool:
    """True when ordinary speech can form this key from two adjacent words.

    The engine concatenates tokens, so "red is" reaches the key of "redis".
    A common word followed by a function word is the dangerous shape.
    """
    for cut in range(2, len(alias_key) - 1):
        head, tail = alias_key[:cut], alias_key[cut:]
        if (tail in FUNCTION_WORDS and head in COMMON
                and zipf_frequency(head, "en") >= 4.2
                and zipf_frequency(tail, "en") >= 4.5):
            return True
    return False


def transform(entries: list[dict]) -> tuple[list[dict], list[tuple[str, str, str, str]]]:
    """Apply the alias rules once. Returns the entries and the decisions."""
    decisions: list[tuple[str, str, str, str]] = []
    for entry in entries:
        canonical = entry["canonical"]
        canon_key = key(canonical)
        kept: list[dict] = []
        for alias in entry["aliases"]:
            text = alias["t"]
            parts = tokens(text)
            k = key(text)
            lowered = text.lower().strip()
            if not parts:
                decisions.append((text, canonical, "delete", "empty alias"))
                continue
            if lowered in NEVER and k != canon_key:
                decisions.append((text, canonical, "delete", "ordinary English phrase"))
                continue
            if lowered in EXPANSION_DELETE:
                decisions.append((text, canonical, "delete", "plain-English expansion"))
                continue
            if (is_acronym(canonical) and len(parts) > 1 and lowered not in SPELLED_OK
                    and not is_spelled(parts) and not has_version(parts)
                    and not phonetic(k, canonical)):
                decisions.append((text, canonical, "delete", "acronym as a phrase"))
                continue
            if len(parts) > 1 and k != canon_key and droppable(parts, entry):
                decisions.append((text, canonical, "delete", "destructive suffix"))
                continue
            if alias["tier"] == "A" and len(parts) == 1 and parts[0] in AMBIGUOUS:
                alias["tier"] = "B"
                alias["requires"] = AMBIGUOUS[parts[0]]
                decisions.append((text, canonical, "tier-b", "ordinary English word"))
                kept.append(alias)
                continue
            if alias["tier"] == "A" and cross_token_risk(k):
                decisions.append((text, canonical, "delete", "forms from adjacent words"))
                continue
            head_word = parts[0] if parts else ""
            if (alias["tier"] == "A" and len(parts) > 1 and head_word in GATED_HEADS
                    and head_word != canon_key and not has_version(parts)
                    and all(c.isalpha() or c.isspace() for c in canonical)):
                alias["tier"] = "B"
                alias.setdefault("requires", [])
                decisions.append((text, canonical, "tier-b", "gated head word"))
            if alias["tier"] == "B" and lowered in EXTRA_REQUIRES:
                alias["requires"] = sorted(set(alias.get("requires", []))
                                           | set(EXTRA_REQUIRES[lowered]))
            kept.append(alias)

        # Aliases that normalize to the same key share one tier. The engine
        # cannot tell "a r i a" from "aria", so both must gate.
        kept.sort(key=lambda a: (is_spelled(tokens(a["t"])), len(tokens(a["t"])), a["t"]))
        by_keyed: dict[str, list[dict]] = {}
        for alias in kept:
            by_keyed.setdefault(key(alias["t"]), []).append(alias)
        for group in by_keyed.values():
            gated_word = any(
                len(tokens(a["t"])) == 1 and tokens(a["t"])[0] in AMBIGUOUS
                and a["tier"] == "B" for a in group)
            if not gated_word:
                continue
            for alias in group:
                if alias["tier"] == "A":
                    alias["tier"] = "B"
                    decisions.append((alias["t"], canonical, "tier-b", "shares a gated key"))
                if not alias.get("requires"):
                    alias["requires"] = next(
                        (a["requires"] for a in group if a.get("requires")), [])
        entry["aliases"] = kept

    # Every entry must match its own canonical spelling. An ordinary English
    # canonical stays gated so "the windows" is not rewritten.
    for entry in entries:
        canon_key = key(entry["canonical"])
        if not canon_key or any(key(a["t"]) == canon_key for a in entry["aliases"]):
            continue
        if canon_key in AMBIGUOUS:
            entry["aliases"].append({"t": entry["canonical"].lower(), "tier": "B",
                                     "requires": AMBIGUOUS[canon_key]})
            decisions.append((entry["canonical"].lower(), entry["canonical"],
                              "tier-b", "identity alias"))
        else:
            entry["aliases"].append({"t": entry["canonical"].lower(), "tier": "A"})
    return entries, decisions


def add_entries(entries: list[dict]) -> int:
    existing_ids = {e["id"] for e in entries}
    existing_keys = {key(e["canonical"]) for e in entries}
    added = 0
    for entry_id, canonical, pack, aliases in FORMAT_ENTRIES + VARIANT_ENTRIES:
        if entry_id in existing_ids or key(canonical) in existing_keys:
            continue
        tier = "B" if "make file" in aliases else "A"
        entries.append({
            "id": entry_id, "canonical": canonical, "kind": "term", "pack": pack,
            "case": "canonical",
            "aliases": [{"t": a, "tier": tier} for a in aliases],
            "enabled_default": True,
        })
        existing_ids.add(entry_id)
        existing_keys.add(key(canonical))
        added += 1
    return added


def main() -> int:
    data = json.loads(CATALOG.read_text())
    entries = data["entries"]
    added = add_entries(entries)

    decisions: list[tuple[str, str, str, str]] = []
    for _ in range(6):
        before = json.dumps(entries, sort_keys=True)
        entries, step = transform(entries)
        decisions.extend(step)
        if json.dumps(entries, sort_keys=True) == before:
            break

    entries.sort(key=lambda e: (e["canonical"].lower(), e["id"]))
    data["entries"] = entries
    CATALOG.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

    AUDIT.mkdir(exist_ok=True)
    with (AUDIT / "curation.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["alias", "canonical", "action", "reason"])
        for row in sorted(set(decisions)):
            writer.writerow(row)

    aliases = sum(len(e["aliases"]) for e in entries)
    tier_a = sum(1 for e in entries for a in e["aliases"] if a["tier"] == "A")
    removed = sum(1 for d in set(decisions) if d[2] == "delete")
    demoted = sum(1 for d in set(decisions) if d[2] == "tier-b")
    print(f"entries={len(entries)} aliases={aliases} tierA={tier_a} tierB={aliases - tier_a}")
    print(f"removed={removed} demoted={demoted} added={added}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
