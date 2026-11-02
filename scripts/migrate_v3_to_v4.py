#!/usr/bin/env python3
"""Migrate the v3 tech dictionary to the high-precision v4 schema.

Deterministic: reads the v3 file, never mutates it, and writes:

    Packages/L2-Engines/catalog/vocab_v4.json
    audit/deleted.csv
    audit/moved_to_tierB.csv
    audit/merged.csv
    audit/collisions_resolved.csv

Policy: a false positive is worse than a miss. Ordinary English and generic
CS concepts are removed; ambiguous aliases are moved to Tier B (context-gated);
destructive aliases are removed; every alias has exactly one owner.
"""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Packages/L2-Engines/catalog/tech-dictionary.json"
OUTPUT = ROOT / "Packages/L2-Engines/catalog/vocab_v4.json"
AUDIT = ROOT / "audit"

TOKEN_RE = re.compile(r"[a-z0-9]+")


def norm(text: str) -> str:
    return " ".join(TOKEN_RE.findall(text.lower()))


def slug(text: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return value or "entry"


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


# ---------------------------------------------------------------------------
# Step 1a: ordinary English and generic CS concepts. STT already spells these.
# ---------------------------------------------------------------------------

GENERIC = {
    "Caching", "Memoization", "Debounce", "Throttle", "Promise", "Async Await", "Callback",
    "Closure", "Hoisting", "Destructuring", "Spread Operator", "Optional Chaining",
    "Nullish Coalescing", "Generics", "Interface", "Type Alias", "Union Type",
    "Intersection Type", "Type Guard", "Type Inference", "Generative AI",
    "Machine Learning", "Deep Learning", "Neural Network", "Transformer", "Attention",
    "Fine-tuning", "Quantization", "Inference", "Prompt Engineering", "Context Window",
    "Tokenization", "Tokenizer", "Embedding", "Vector Database", "Container",
    "Kubernetes Pod", "Kubernetes Deployment", "Kubernetes Service", "Ingress",
    "Access Token", "Refresh Token", "Bearer Token", "JWT Token", "Secret", "API Key",
    "Environment Variable", "Rate Limiting", "Load Balancer", "Reverse Proxy",
    "Middleware", "Controller", "Repository", "Service Layer", "Dependency",
    "Dependency Injection", "Dependency Graph", "Package", "Library", "Framework",
    "Compiler", "Bundler", "Transpiler", "Linter", "Formatter", "Hot Module Replacement",
    "Tree Shaking", "Code Splitting", "Lazy Loading", "Dynamic Import", "Server Component",
    "Client Component", "Server Action", "API Route", "Route Handler", "Hydration",
    "Hydration Mismatch", "Virtual DOM", "Shadow DOM", "Web Components",
    "Custom Element", "Accessibility", "Open Graph", "Meta Tags", "Canonical URL",
    "Sitemap", "HTML Tag", "Markdown Heading", "Markdown Link", "Markdown Code Fence",
    "Backtick", "CamelCase", "PascalCase", "snake_case", "kebab-case",
    "SCREAMING_SNAKE_CASE", "port", "port 3000", "port 5173", "port 1420",
    "Git branch", "Git commit", "Git merge", "Git rebase", "Git stash", "Pull Request",
    "Code Review", "Issue", "Branch Protection", "Database Migration", "Database Schema",
    "Primary Key", "Foreign Key", "Index", "Transaction", "Connection Pool", "Query",
    "Mutation", "CRUD", "Microservices", "Serverless", "Monorepo", "SOLID", "DRY",
    "KISS", "YAGNI", "TDD", "BDD", "MVC", "MVVM", "Memo", "Context API",
    "git push", "git pull", "git clone", "git fetch", "git checkout", "git switch",
    "git log", "git diff", "git status", "git reset", "git cherry-pick",
    "React Hooks", "React Server Components", "TypeScript Compiler",
    "Git branch", "Git commit", "Git merge", "Git rebase", "Git stash",
}

HTML_TAGS = {
    "div", "span", "section", "article", "header", "footer", "main", "nav", "button",
    "input", "textarea", "form", "label", "select", "option", "table", "thead", "tbody",
    "tfoot", "tr", "td", "th", "ul", "ol", "li", "pre", "code", "blockquote",
}

JUNK = {"getUserById", "fileName", "SuperflowPanel", "rounded-2xl", "/"}

# Step 1b: wrong-direction expansions are handled by the acronym heuristic.

# Step 1c: aliases that add a generic suffix and drop it on replacement.
SUFFIXES = {
    "framework", "app", "project", "library", "server", "model", "ai", "file", "config",
    "web", "desktop", "coding", "react", "rust", "cli", "api",
}
MODEL_SUFFIXES = {
    "r1", "v2", "v3", "v4", "v5", "pro", "max", "mini", "flash", "lite", "turbo",
    "coder", "chat", "instruct", "base", "code", "opus", "sonnet", "haiku", "fable",
    "mythos", "sol", "terra", "luna",
}

# Step 1e / Step 3: ambiguous aliases. Kept as Tier B, never always-on.
AMBIGUOUS = {
    "next year", "next years", "next year's", "nexts year", "nexts years", "cloud",
    "quick", "quick js", "view", "queen", "quinn", "cotton", "jason", "jot", "oath",
    "tokyo", "tory", "tari", "sequel", "lambda function", "lambda", "spring", "drizzle",
    "rizzle", "dive", "hpm", "dot c", "ho no", "boon", "the zod", "render", "express",
    "node", "go", "swift", "ruby", "java", "rust", "arch", "fish", "warp", "cursor",
    "neon", "chroma", "helm", "bun", "remix", "astro", "apollo", "elastic", "dynamo",
    "mongo", "motion", "framer", "solid", "rails", "windows", "tech stock",
    "text track", "text tack", "tech track", "story desktop app", "story rust app",
    "app router", "textract",
}

DANGEROUS_ALIASES = AMBIGUOUS

AMBIGUOUS_CANONICALS = {norm(x) for x in AMBIGUOUS} | {
    "git", "bash", "fish", "motion", "framer motion", "solid", "rails", "windows",
}

# Product tokens make an alias distinctive even when every word is frequent.
PRODUCT_TOKENS = {
    "github", "gitlab", "cypress", "playwright", "vite", "vitest", "jest", "webpack",
    "turbo", "turbopack", "rollup", "esbuild", "babel", "eslint", "prettier", "postcss",
    "sass", "scss", "tanstack", "redux", "zustand", "mobx", "jotai", "recoil", "shadcn",
    "radix", "storybook", "figma", "framer", "three", "d3", "webgl", "webgpu", "wasm",
    "webassembly", "expo", "electron", "trpc", "graphql", "apollo", "websocket",
    "webrtc", "grpc", "openapi", "swagger", "json", "yaml", "toml", "xml", "html",
    "css", "sql", "postgresql", "mysql", "sqlite", "mongodb", "redis", "dynamodb",
    "supabase", "firebase", "planetscale", "neon", "turso", "prisma", "sqlalchemy",
    "sequelize", "mongoose", "aws", "gcp", "azure", "cloudflare", "vercel", "netlify",
    "railway", "render", "heroku", "kubernetes", "docker", "dockerfile", "terraform",
    "ansible", "helm", "apache", "pnpm", "pip", "poetry", "python", "django", "flask",
    "fastapi", "pandas", "numpy", "scipy", "scikit", "jupyter", "tensorflow", "rust",
    "cargo", "tokio", "axum", "actix", "serde", "golang", "ruby", "php", "laravel",
    "java", "spring", "kotlin", "swift", "swiftui", "rabbitmq", "kafka", "elasticsearch",
    "opensearch", "prometheus", "grafana", "datadog", "postman", "insomnia", "stripe",
    "paypal", "twilio", "openai", "anthropic", "chatgpt", "gpt", "ollama", "hugging",
    "langchain", "langgraph", "langsmith", "whisper", "parakeet", "nemotron", "connectx",
    "asus", "dgx", "rtx", "radeon", "blackwell", "gb300", "deepseek", "llm", "stt",
    "tts", "asr", "rag", "pinecone", "weaviate", "chroma", "jwt", "oauth", "oidc",
    "http", "https", "ssh", "dns", "cdn", "tcp", "udp", "ipv4", "ipv6", "localhost",
    "vscode", "xcode", "jetbrains", "intellij", "ghostty", "iterm", "zsh", "macos",
    "linux", "ubuntu", "arch", "homebrew", "monorepo", "turborepo", "pwa", "ssr",
    "ssg", "isr", "csr", "spa", "mvc", "mvvm", "tdd", "bdd", "solid", "dry", "kiss",
    "yagni", "regex", "uuid", "url", "uri", "crud", "webhooks", "microservices",
    "serverless", "cors", "csrf", "xss", "mcp", "ide", "repl", "jsonl", "markdown",
    "mdx", "zod", "websockets", "oculink", "gmktec", "evo", "strix", "qwen", "llama",
    "cuda", "rocm", "vulkan", "windows", "bun", "npm", "yarn", "cargo",
}

COMMAND_VERBS = {
    "install", "run", "dev", "push", "pull", "clone", "fetch", "checkout", "switch",
    "log", "diff", "status", "reset", "cherry", "pick", "build", "test", "add", "commit",
}

# Explicit collision owners. Everything else is resolved by deterministic priority.
COLLISION_OWNERS = {
    "nest js": "NestJS",
    "nestjs": "NestJS",
    "nest j s": "NestJS",
    "wasm": "WASM",
    "w a s m": "WASM",
    "web assembly": "WebAssembly",
    "sass css": "SCSS",
    "json web token": "JWT",
    "bearer token": "Bearer Token",
    "markdown file": "Markdown",
    "motion for react": "Motion",
    "motion react": "Framer Motion",
    "motion library": "Motion",
    "docker container": "Docker",
    "throttling": "Rate Limiting",
    "typescript jsx": "TSX",
    "go": "Go",
    "golang": "Go",
    "go lang": "Go",
    "go language": "Go",
    "go-lang": "Go",
    "websocket": "WebSocket",
    "websockets": "WebSocket",
    "web socket": "WebSocket",
    "pull request": "Pull Request",
    "pull req": "Pull Request",
    "code review": "Code Review",
    "code-review": "Code Review",
    "textract": "tech stack",
    "tech stack": "tech stack",
}

# Explicit merge groups: (members, target canonical).
MERGE_GROUPS = [
    ({"go", "golang"}, "Go"),
    ({"websocket", "websockets"}, "WebSocket"),
    ({"motion", "motion previously framer motion"}, "Motion"),
    ({"deepseek v4 flash"}, "DeepSeek-V4-Flash"),
    ({"moe"}, "MoE"),
    ({"gb300"}, "GB300"),
    ({"dgx station"}, "DGX Station"),
    ({"rtx 5080"}, "RTX 5080"),
    ({"rtx pro 6000"}, "RTX PRO 6000"),
    ({"radeon 8060s"}, "Radeon 8060S"),
    ({"pull request"}, "Pull Request"),
    ({"code review"}, "Code Review"),
]

# Step 2: genuine acoustic/ASR confusions that stay Tier A.
TIER_A_HINTS = {
    "gpu", "cpu", "nvidia", "amd", "intel", "rtx", "radeon", "dgx", "cuda", "rocm",
    "gguf", "vllm", "llama", "qwen", "deepseek", "gpt", "claude", "gemini", "grok",
    "kimi", "glm", "muse", "nemotron", "whisper", "parakeet", "tanstack", "shadcn",
    "zustand", "sveltekit", "kubernetes", "tailwind", "vitest", "supabase", "vercel",
    "ollama", "langchain", "langgraph", "unsloth", "nvfp4", "fp4", "q4", "q8", "lora",
    "trpc", "grpc", "protobuf", "esbuild", "swc", "pnpm", "postgresql", "mongodb",
    "cors", "csrf", "xss", "oauth", "oidc", "jwt", "webhooks", "websocket", "regex",
}

# Tier B aliases are gated by a small high-signal co-word set in the pipeline.
# Broad pack vocabulary (library, package, server, ...) is deliberately absent:
# it makes ordinary sentences such as "next year at the library" fire.

CATEGORY_HINTS = {
    "web": ("react", "next", "vue", "svelte", "astro", "remix", "angular", "solid", "nuxt",
            "tailwind", "vite", "webpack", "rollup", "esbuild", "turbo", "parcel", "shadcn",
            "radix", "tanstack", "zustand", "redux", "trpc", "graphql", "apollo", "prisma",
            "drizzle", "supabase", "firebase", "vercel", "netlify", "cloudflare", "html",
            "css", "javascript", "typescript", "jsx", "tsx", "wasm", "webassembly"),
    "ai-models": ("gpt", "claude", "gemini", "llama", "qwen", "deepseek", "mistral", "grok",
                  "kimi", "glm", "muse", "nemotron", "whisper", "openai", "anthropic", "vllm",
                  "ollama", "unsloth", "gguf", "quant", "lora", "moe", "token", "embedding"),
    "infra": ("docker", "kubernetes", "k8s", "pod", "helm", "terraform", "nginx", "ingress",
              "aws", "gcp", "azure", "lambda", "serverless", "redis", "postgres", "mongodb",
              "sqlite", "kafka", "rabbitmq", "grafana", "prometheus", "linux", "ubuntu"),
    "hardware": ("nvidia", "amd", "intel", "apple", "rtx", "radeon", "dgx", "gb", "h100", "a100",
                 "m3", "m4", "mac", "cpu", "gpu", "ram", "ssd", "tensor", "pcie", "hbm"),
    "python": ("python", "django", "flask", "fastapi", "pandas", "numpy", "pytest", "poetry",
               "uv", "ruff", "mypy"),
    "rust": ("rust", "cargo", "tokio", "serde", "axum", "tauri", "wasm"),
    "mobile": ("ios", "swift", "swiftui", "uikit", "android", "kotlin", "flutter",
               "react native"),
    "command": ("git", "npm", "pnpm", "yarn", "brew", "curl", "bash", "zsh", "shell", "cli"),
}


def pack_for(canonical: str, aliases: list[str]) -> str:
    haystack = (canonical + " " + " ".join(aliases)).lower()
    for name, hints in CATEGORY_HINTS.items():
        if any(h in haystack for h in hints):
            return name
    return "core"


def kind_for(canonical: str, pack: str) -> str:
    lowered = canonical.lower()
    if pack == "ai-models":
        if any(w in lowered for w in ("gpt", "claude", "gemini", "llama", "qwen", "deepseek",
                                      "mistral", "grok", "kimi", "glm", "muse", "nemotron",
                                      "whisper", "parakeet", "codestral")):
            return "model"
    if pack == "hardware":
        return "hardware"
    if any(w in lowered for w in ("javascript", "typescript", "python", "rust", "go", "golang",
                                  "java", "kotlin", "swift", "ruby", "php", "c++", "c#")):
        return "lang"
    if any(w in lowered for w in ("api", "sdk", "cli", "json", "yaml", "toml", "xml", "html",
                                  "css", "sql", "http", "https", "ssh", "dns", "tcp", "udp",
                                  "jwt", "oauth", "oidc", "cors", "csrf", "xss", "mcp", "ide",
                                  "llm", "stt", "tts", "asr", "rag", "orm", "uuid", "url",
                                  "uri", "crud", "pwa", "ssr", "ssg", "isr", "csr", "spa")):
        return "acronym"
    if any(w in lowered for w in ("git", "npm", "pnpm", "install", "run dev", "push", "pull")):
        return "command"
    if any(w in lowered for w in ("aws", "gcp", "azure", "vercel", "netlify", "railway",
                                  "render", "heroku", "cloudflare", "supabase", "firebase",
                                  "stripe", "paypal", "twilio", "sentry")):
        return "service"
    if any(w in lowered for w in ("react", "next", "vue", "svelte", "astro", "remix", "solid",
                                  "angular", "nuxt", "qwik", "gatsby", "vite", "webpack",
                                  "tailwind", "express", "fastify", "nestjs", "hono", "deno",
                                  "bun", "django", "flask", "fastapi", "spring", "laravel",
                                  "rails", "tauri", "electron", "expo", "playwright", "cypress",
                                  "jest", "vitest", "storybook")):
        return "framework"
    return "tool"


def is_acronym(canonical: str) -> bool:
    letters = [c for c in canonical if c.isalpha()]
    return 2 <= len(letters) <= 6 and canonical.upper() == canonical


def is_spelled(alias: str) -> bool:
    parts = [p for p in tokens(alias) if p != "dot"]
    return bool(parts) and all(len(p) == 1 for p in parts)


def wrong_direction(alias: str, canonical: str) -> bool:
    if not is_acronym(canonical) or is_spelled(alias):
        return False
    parts = tokens(alias)
    return len(parts) >= 3 and norm(alias) != norm(canonical)


def destructive(alias: str, canonical: str) -> bool:
    alias_parts = tokens(alias)
    canon_parts = tokens(canonical)
    if len(alias_parts) <= len(canon_parts):
        return False
    if alias_parts[:len(canon_parts)] != canon_parts:
        return False
    extras = alias_parts[len(canon_parts):]
    return any(extra in SUFFIXES or extra in MODEL_SUFFIXES or extra.isdigit() for extra in extras)


def common_risk(alias: str, common_words: set[str]) -> int:
    parts = tokens(alias)
    if not parts:
        return 0
    common = [p for p in parts if p in common_words]
    if len(parts) == 1 and common:
        return 2
    if len(parts) > 1 and len(common) == len(parts):
        return 1
    return 0


def distinctive(alias: str, canonical: str) -> bool:
    """True when an alias is a product/command/model form, not ordinary prose."""
    parts = tokens(alias)
    if any(p.isdigit() for p in parts):
        return True
    if is_spelled(alias):
        return True
    if any(p in PRODUCT_TOKENS for p in parts):
        return True
    if canonical.upper() == canonical and len(tokens(canonical)) <= 2:
        return True
    if any(c.isupper() for c in canonical[1:]) and norm(canonical) not in AMBIGUOUS_CANONICALS:
        return True
    if parts and parts[0] in COMMAND_VERBS and any(p in PRODUCT_TOKENS for p in parts):
        return True
    return False


def load_common_words() -> set[str]:
    try:
        from wordfreq import top_n_list
        return set(top_n_list("en", 30_000))
    except Exception:
        return set()


def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def main() -> int:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    common = load_common_words()
    AUDIT.mkdir(exist_ok=True)

    raw_entries = data["entries"]
    deleted: list[tuple[str, str, str]] = []
    merged: list[tuple[str, str, str]] = []

    # --- Merge duplicate canonicals before anything else. -------------------
    by_norm: dict[str, dict] = {}
    for entry in raw_entries:
        key = norm(entry["canonical"])
        if key in by_norm:
            by_norm[key]["aliases"].extend(entry.get("aliases", []))
            merged.append((entry["canonical"], by_norm[key]["canonical"],
                           "duplicate canonical form"))
        else:
            by_norm[key] = {"canonical": entry["canonical"],
                            "aliases": list(entry.get("aliases", []))}

    # Common nouns are lowercase; "tech stack" is a phrase, not a product name.
    for entry in by_norm.values():
        if entry["canonical"] == "Tech stack":
            entry["canonical"] = "tech stack"

    # Explicit groups whose names are not textually identical.
    target_by_norm: dict[str, str] = {}
    for members, target in MERGE_GROUPS:
        existing = [by_norm.pop(m, None) for m in members]
        existing = [e for e in existing if e]
        if not existing:
            continue
        if not any(norm(e["canonical"]) == norm(target) for e in existing):
            target_entry = {"canonical": target, "aliases": []}
        else:
            target_entry = next(e for e in existing if norm(e["canonical"]) == norm(target))
            existing = [e for e in existing if e is not target_entry]
        for entry in existing:
            target_entry["aliases"].extend(entry["aliases"])
            merged.append((entry["canonical"], target, "explicit merge group"))
        by_norm[norm(target)] = target_entry
        target_by_norm[norm(target)] = target

    # --- Delete generic, HTML and junk entries. ------------------------------
    kept: list[dict] = []
    generic_norm = {norm(x) for x in GENERIC}
    html_norm = {norm(x) for x in HTML_TAGS}
    junk_norm = {norm(x) for x in JUNK}
    for key, entry in by_norm.items():
        canonical = entry["canonical"]
        if key in generic_norm:
            deleted.append((canonical, "", "ordinary English / generic CS concept"))
        elif key in html_norm:
            deleted.append((canonical, "", "bare HTML tag"))
        elif key in junk_norm or canonical.startswith("."):
            deleted.append((canonical, "", "junk, extension or personal entry"))
        else:
            kept.append(entry)

    # --- Clean aliases, assign tiers, resolve collisions. --------------------
    moved_b: list[tuple[str, str, str]] = []
    for entry in kept:
        canonical = entry["canonical"]
        if canonical == "tech stack" and "textract" not in entry["aliases"]:
            entry["aliases"].append("textract")
        clean: list[tuple[str, str]] = []
        seen: set[str] = set()
        for alias in entry["aliases"]:
            alias = alias.strip()
            key = norm(alias)
            if not key or key in seen:
                continue
            if wrong_direction(alias, canonical):
                deleted.append((canonical, alias, "wrong-direction acronym expansion"))
                continue
            if destructive(alias, canonical):
                deleted.append((canonical, alias, "destructive suffix alias"))
                continue
            if key in DANGEROUS_ALIASES or (common_risk(alias, common) and
                                           not distinctive(alias, canonical)):
                clean.append((alias, "B"))
                moved_b.append((alias, canonical, "ambiguous or common-word alias"))
                seen.add(key)
                continue
            clean.append((alias, "A"))
            seen.add(key)
        # The canonical itself is always an explicit alias so the engine can
        # gate it without an implicit canonical rule.
        canon_key = norm(canonical)
        if canon_key and canon_key not in seen:
            tier = "B" if (canon_key in DANGEROUS_ALIASES or
                           (common_risk(canonical, common) and
                            not distinctive(canonical, canonical))) else "A"
            clean.append((canonical, tier))
            if tier == "B":
                moved_b.append((canonical, canonical, "ambiguous or common-word canonical"))
        if not clean:
            deleted.append((canonical, "", "no aliases survived cleanup"))
            continue
        entry["clean_aliases"] = clean

    # Resolve every alias key to one owner.
    owners: dict[str, list[dict]] = defaultdict(list)
    for entry in kept:
        if "clean_aliases" not in entry:
            continue
        for alias, tier in entry["clean_aliases"]:
            owners[norm(alias)].append(entry)

    collisions: list[tuple[str, str, str]] = []
    for key, candidates in owners.items():
        if len({id(c) for c in candidates}) <= 1:
            continue
        explicit = COLLISION_OWNERS.get(key)
        owner = None
        if explicit:
            owner = next((c for c in candidates if c["canonical"] == explicit), None)
        if owner is None:
            owner = next((c for c in candidates if norm(c["canonical"]) == key), None)
        if owner is None:
            owner = sorted(candidates, key=lambda c: (
                0 if any(t == "A" for a, t in c["clean_aliases"] if norm(a) == key) else 1,
                -len(c["clean_aliases"]), c["canonical"].lower()))[0]
        for candidate in candidates:
            if candidate is owner:
                continue
            candidate["clean_aliases"] = [
                (a, t) for a, t in candidate["clean_aliases"] if norm(a) != key
            ]
            collisions.append((key, candidate["canonical"], owner["canonical"]))

    # Drop entries that lost every alias during collision resolution.
    final: list[dict] = []
    for entry in kept:
        aliases = entry.get("clean_aliases")
        if not aliases:
            deleted.append((entry["canonical"], "", "lost every alias in collision resolution"))
            continue
        canonical = entry["canonical"]
        pack = pack_for(canonical, [a for a, _ in aliases])
        alias_rows = []
        for alias, tier in sorted(aliases, key=lambda x: (x[1], x[0].lower())):
            requires = []
            neg = []
            if tier == "B" and norm(alias) in {"textract", "text track", "text tack",
                                               "tech track", "tech stock"}:
                requires = ["tech", "stack", "frontend", "backend"]
                neg = ["aws", "ocr", "document", "pdf"]
            alias_rows.append({"t": alias, "tier": tier,
                               **({"requires": requires} if requires else {}),
                               **({"neg": neg} if neg else {})})
        final.append({
            "id": slug(canonical),
            "canonical": canonical,
            "kind": kind_for(canonical, pack),
            "pack": pack,
            "case": "canonical" if any(c.isupper() for c in canonical[1:]) else "lower",
            "aliases": alias_rows,
            "enabled_default": any(row["tier"] == "A" for row in alias_rows),
        })

    # --- Add missing current Claude models. ---------------------------------
    def claude_aliases(name: str, version: str) -> list[dict]:
        lower = name.lower()
        spoken = version.replace(".", " point ")
        base = [
            f"claude {lower} {version}", f"claude {lower} {spoken}",
            f"{lower} {version}", f"{lower} {spoken}",
            f"claude {version} {lower}", f"claude {spoken} {lower}",
        ]
        return [{"t": a, "tier": "A"} for a in dict.fromkeys(base)]

    missing = [
        ("Claude Opus 5.5", "5.5"), ("Claude Sonnet 5.5", "5.5"),
        ("Claude Haiku 5.5", "5.5"), ("Claude Fable 5.1", "5.1"),
        ("Claude Mythos 5.1", "5.1"),
    ]
    existing_ids = {entry["id"] for entry in final}
    for canonical, version in missing:
        slug_id = slug(canonical)
        if slug_id in existing_ids:
            continue
        name = canonical.replace("Claude ", "").rsplit(" ", 1)[0]
        final.append({
            "id": slug_id, "canonical": canonical, "kind": "model", "pack": "ai-models",
            "case": "canonical", "aliases": claude_aliases(name, version),
            "enabled_default": True,
        })

    if "claude-code" not in existing_ids:
        final.append({
            "id": "claude-code", "canonical": "Claude Code", "kind": "tool",
            "pack": "ai-models", "case": "canonical",
            "aliases": [{"t": a, "tier": "A"} for a in [
                "claude code", "clod code",
            ]], "enabled_default": True,
        })

    final.sort(key=lambda e: (e["pack"], e["canonical"].lower()))
    OUTPUT.write_text(json.dumps({"version": 4, "entries": final}, indent=2) + "\n",
                      encoding="utf-8")

    write_csv(AUDIT / "deleted.csv", ["canonical", "alias", "reason"], deleted)
    write_csv(AUDIT / "moved_to_tierB.csv", ["alias", "canonical", "reason"], moved_b)
    write_csv(AUDIT / "merged.csv", ["from", "into", "reason"], merged)
    write_csv(AUDIT / "collisions_resolved.csv", ["alias", "dropped_from", "owner"], collisions)

    alias_count = sum(len(e["aliases"]) for e in final)
    tier_a = sum(1 for e in final for a in e["aliases"] if a["tier"] == "A")
    tier_b = alias_count - tier_a
    print(f"v4: {len(final)} entries, {alias_count} aliases "
          f"({tier_a} Tier A, {tier_b} Tier B)")
    print(f"deleted {len(deleted)} entries/aliases, moved {len(moved_b)} to Tier B, "
          f"merged {len(merged)}, resolved {len(collisions)} collisions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
