# Latest-plan validation

Root cause: the Textract Tier B branch bypasses all developer-context gates; disabled personal entries also count as pins.

1. Add gate regressions for prose, developer apps/co-words, AWS/project exclusions, and disabled pins.
2. Remove the bypass and restrict pins to enabled entries in TechDictionaryGate.swift.
3. Run TextPipeline, formatting/cleanup, and LlamaCleaner tests; inspect catalog and plan integration.
4. Record verified implementation and missing acceptance evidence in work/plan/audit/latest-plan-validation.md.
5. Record the confirmed gate issue in issue.md and commit explicit owned paths.

No prompt/glossary injection, ASR defaults, speculative cleanup, or unmeasured speed claims.

## Verified source and test findings (2026-11-02)
- Production order: cleanup → dedupe → format → enabled commands/shortcuts/spoken code/numbers/code-speak/personal lexicon/code-aware/lineformat → techDictionary. Harper/disfluency/FinalPolish are not scheduled. Numbers and lexicon run AFTER S1-mini.
- Formatting includes enumeration routing to `lists`, list normalization, paragraph shaping, whitespace cleanup, optional default-off spoken quotes and quote-count rejection. Case-preservation regression failed before the guard fix.
- Chunk target is 250 tokens, workers default 3, hard cap 600; actual helper capacity limits concurrency. More workers do not accelerate one short chunk. No short-take speedup is demonstrated.
- Runtime uses greedy-only sampling, special-token parsing, bounded prefill batches, completion truncation metadata; prompt hash tests pass. It clears KV memory each request, so prefix reuse is NOT implemented.
- Catalog: v3 687 entries/3405 aliases → v4 452 entries/2252 aliases (1922 A, 330 B), zero exact lowercase-alias collisions. Claude Code and requested 5.5/5.1 names exist (Fable/Mythos carry the Claude prefix).
- Migration repeated in temporary outputs is deterministic within this environment and leaves source unchanged, BUT does not match bundled v4. `load_common_words()` silently returns an empty set without wordfreq, changing tiers; do not regenerate the shipped catalog without fixing this.
- Corpus: 312 everyday negatives and 329 developer positives. Tests now require resources, minimum sizes and well-formed positive rows. Textract positive explicitly supplies `build` context; negative context is Pages. Focused gate tests separately exercise VS Code.

## Acceptance gaps — NOT complete
- Production TextContext constructors do not supply activeAppBundleID; app gating exists only when callers supply it. Dev-app gating also causes two existing mixed-language positive examples to over-replace; those expectations require policy resolution before enabling it in production.
- Native replacement is the existing character trie, not token Aho-Corasick. User and bundled stages remain separate (possible cascading); enabled_default is ignored by catalog conversion. <2 ms, hot reload, undo, per-alias reports and pack settings are unverified/incomplete.
- No implemented ASR biasing/glossary retrieval, opt-in project harvesting or correction learning was established. Glossary prompt injection conflicts with the pinned S1 prompt; it was not added.
- Cleanup still uses fixed deadlines, one attempt and raw fallback. Throughput-derived deadline policy, split retry, full-session segment carry/cache and the configurable meaning-gate levels are not established by current source.
- Exact-build llama-server parity, cached-prefix parity, 10 owner-approved raw/corrected/reference fixtures, V0–V12/F0–F4 matrices, blind competitor ratings, ASR contention and packaged stop-to-visible latency remain UNVERIFIED. No 9/10 or speed claim.
- Existing speculation is default off; no contention evidence justifies enabling it. Hotkey/cold-start packaged acceptance from v2 was not repeated in this cleanup/dictionary review.

## This change
- Fixed Textract bypass and disabled pins; strengthened formatting guard to reject casing changes.
- Kept prompt, model, GPU default, optional quote default and speculation unchanged.

## Passing verification
- TextPipeline: 41 tests; LlamaCleaner: 21 tests; affected formatting/guard classes: 22 tests. Dictionary corpus passes 312 negatives and 329 positives.
- `make lint` and `git diff --check` pass. No packaged build, parity run, real-audio benchmark or blind quality rating was performed.
