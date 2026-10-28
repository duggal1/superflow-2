SuperFlow Text Cleanup — Elite Coding Prompt Plan

Version: 2026-10-28
Status: Implementation-ready
Goal: Maximum quality on-device cleanup for high-volume personal dictation + agentic coding, with zero cloud dependency, zero filesystem escape, and zero bloat.



0. Non-Negotiable Principles





Local only. No network calls in the critical path. Ever.



Deterministic first. Mechanical, high-precision work happens in pure code before any model sees the text.



Specialized model only. S1-mini (or a measured LoRA fine-tune of it / Qwen3-0.6B). Never a general chat model on the live path.



Strict containment. The only filesystem the pipeline may know is an explicitly injected project root. No whole-disk walks, no home-directory indexing, no “helpful” global search.



Never invent. Any stage that cannot improve the text safely must return the input unchanged + diagnostic.



Fail into the previous good state. Hard fallbacks, timeouts, and cancellation are mandatory.



Measure everything. Golden suites, property tests, latency/RSS budgets. Keep only what wins on real speech.



Ghostty-native. Output must paste cleanly into terminal, Claude Code, Codex, herdr, Neovim, shell prompts. No editor-specific assumptions.

Past lesson (do not repeat): never clone a bloated app and “make it mine”. Build only what is required, keep it lightweight, and enforce folder constraints architecturally.



1. Pipeline Stage Order (Final)

1. TextCommands          (spoken commands, short-circuit)
2. TextShortcuts         (user shortcuts, short-circuit)
3. TextDisfluency        ← NEW – aggressive exact-duplicate collapse + light filler pre-pass
4. TextNumbers           (ITN: numbers, currency, dates, times, etc.)
5. TextLexicon           (personal + tech dictionary, protected spans)
6. TextCodeAware         ← NEW – filename/extension + strict path resolution (optional)
7. TextCleanup           (S1-mini or fine-tune, control-line driven)
8. TextNumbers + TextLexicon assertion pass
9. TextGrammarGate       (Harper, heavily gated)
10. TextLineFormat + Structure  (elite deterministic formatting + list detection)

No extra model passes. No style rewriting. No unbounded buffers.



2. TextDisfluency (Highest Leverage for Your Speech)

Purpose: Remove the noise that dominates your dictation before the model ever sees it.

2.1 Exact Duplicate Collapse (mandatory, aggressive)





Tokenize on whitespace + punctuation boundaries.



Collapse any run of identical consecutive tokens (case-insensitive after simple normalization).



Examples:





the the the → the



I I I think → I think



very very good → very good (default threshold = 2)



Never touch protected spans (dictionary terms, already-formatted numbers, emails, code-like tokens, paths).



Setting: duplicateCollapseThreshold (default 2). Can be raised if emphasis must be preserved.



Property tests required:





Idempotent



Never changes text that has no consecutive duplicates



Never removes the sole occurrence of a word



Bounded output size

2.2 Filler Pre-pass (optional, measure first)





Only the highest-frequency pure fillers that measurement shows S1 sometimes leaves:





Standalone um, uh, uhm, er, ah, hmm (and short elongations)



Do not remove content-bearing words (like, you know, I mean, well, so, etc.). Leave those to S1.



If the light pre-pass does not improve golden-set metrics, delete it.

This stage is pure, sub-millisecond, and deterministic.



3. TextCodeAware (Coding / Agentic Path)

Purpose: Make spoken filenames, extensions, and project-relative paths clean and usable in Ghostty + agents.

3.1 Strict Containment Rules (architectural)





Receives an optional projectRoot: URL? injected by SessionEngine / composition root.



If projectRoot == nil → path resolution is a pure no-op. Filename/extension normalization still runs.



Never walks the filesystem at cleanup time.



Optional bounded in-memory index (built once on project open or explicit refresh, depth-limited, ignores node_modules, .git, dist, build, caches, etc.).



Path traversal (..) rejected or normalized away.



Realpath-style check against the declared root. Anything that would escape is left as plain text.

3.2 Responsibilities (keep tiny)





Filename & extension normalization





hero dot t s x / hero tsx → hero.tsx



Common extensions map (tsx, ts, js, jsx, py, rs, go, md, json, yaml, toml, css, …)



Longest match wins. Never invent new extensions.



Path fragment resolution (only when root is present)





Spoken “go to lib backend folder” / “fix prospect main engine” → clean relative or root-relative path



Prefer relative paths when intent is local.



Ambiguous or out-of-root matches → leave original text unchanged.



Light identifier polish





Spoken casing hints (camel case, kebab, snake)



Protect resulting tokens so later stages do not touch them.

3.3 Integration





Sits after Lexicon, before or immediately after Numbers.



Emits protected spans for any rewritten paths/filenames.



Control line for TextCleanup can receive a coding context flag when this stage was active or when the session is marked coding.



4. TextCleanup (S1-mini / Fine-tune)





Keep exact system prompt + three-axis control line (formality / structure / context) pinned by hash.



Temperature 0, greedy, no sampling.



Drive structure = list when clear list cues are present (spoken “first… second…”, “bullet”, “the following”, sequential parallel items).



Measured safe chunk size (Spike B). Soft target ~55-60 % of measured truncation point. Prefer VAD / sentence boundaries. Never split protected spans.



Full safety net:





TruncationDetector



Hallucination guard (output must be explainable by input + small allowed set)



Retry-by-split up to depth 3



Hard fallback to Tier-0 text



OrderedStitcher + SeamRepair



Telemetry: per-chunk latency, tokens in/out, outcome.



Interactive requests jump the queue. Hard deadlines (1.5 s interactive, 30 s background) with cancellation.

Fine-tune Path (highest leverage)





LoRA on Qwen3-0.6B base or on S1-mini weights.



Training data: your real dictations + synthetic hard cases (stutters, self-corrections, tech terms, intentional lists, currency/email edge cases).



Explicit positive examples of list → bullet when speech intends structure.



Negative examples that teach restraint (do not invent, do not rephrase beyond cleanup).



Keep the same TextCleaner port. Swap only if the fine-tune wins on your golden set (edit accuracy + restraint).



5. TextGrammarGate (Harper)





Allowlist only highest-precision categories that help dictation (spelling excluding protected terms, agreement, repeated words as backup, a/an, basic capitalization/punctuation).



Edit budget ≤ 2–3 % of words in the chunk. More → skip entire chunk.



Protected spans inviolable.



50 ms hard time cap → skip.



Golden set of 200–300 your-style sentences. Any category < 98 % precision stays disabled forever.



Idempotence required: Harper(Harper(x)) == Harper(x).



Never enable style / word-choice / readability rules.



6. TextLineFormat + Structure





Sentence boundary detector that respects abbreviations, decimals, URLs, “Next.js”, etc.



Streaming carry-over state so incremental formatting of a long session equals batch formatting (required test).



After S1, lightweight deterministic list detector:





Numbered items, parallel short clauses, spoken “bullet/item/point” signals that survived.



Convert only existing content into clean Markdown bullets or numbered lists.



Never invent items, never re-order, never rephrase.



Final polish: sentence-start capitalization, standalone “i” → “I”, residual space collapse, one space after punctuation, optional trailing period / trailing space settings.



Preserve code fences, relative paths, and inline code. Never reflow inside them.



7. Supporting Infrastructure

ProjectContext / Root Injection





Thin port. SessionEngine injects the active root (user-declared or previously approved).



Root lives only for the lifetime of the session.



Optional bounded path index is a separate, explicit concern (never a background whole-disk indexer).

Lexicon





Personal + curated tech dictionary (target ≤ 150 high-value entries).



Negative examples required.



Frequency-list collision warnings.



Aho-Corasick or trie, longest match.



Protected spans flow to Harper and TextCodeAware.

Numbers / ITN





Prefer FluidAudio NeMo-style component if clean; otherwise data-driven tables.



Cardinals, ordinals, currency (incl. future lakh/crore), percentages, years, decimals, abbreviated vs full style.



8. Explicitly Forbidden





Whole-filesystem or home-directory indexing.



Second LLM pass for “consistency” or style.



General 7B+ chat models on the live interactive path.



Fuzzy / phonetic matching in the lexicon.



Unbounded worker queues or full-transcript in-memory buffers.



Style/word-choice Harper rules.



Progressive live typing into target apps (post-v1 experiment only).



Any stage that can invent content or change meaning without an explicit, measured justification.



Cloning external apps and “making them mine”.



9. Measurement & Acceptance Gates





Golden suites for every stage, especially TextDisfluency and full pipeline on real owner dictations.



Property tests on every deterministic stage (idempotence, protected spans, empty input, bounded growth).



10-hour soak: RSS growth within budget, zero lost samples, stop-to-final < 5 s.



Side-by-side: stock S1-mini vs fine-tune + new early disfluency stage. Keep only what wins.



Interactive latency hard fallback ≤ 1.5 s.



Harper categories must maintain ≥ 98 % precision on the golden set or stay disabled.



10. Implementation Order (Brutal)





ProjectContext port + root injection (one ADR).



TextDisfluency stage + exhaustive unit/property tests.



TextCodeAware stage (filename/extension first, path resolution second) + containment tests.



Expand Lexicon with real tech terms from your workflow.



Wire control-line structure axis for list mode.



Harper tightening + golden set of your speech.



Structure-aware LineFormat pass.



Fine-tune data collection + LoRA experiment (optional but highest leverage).



Full pipeline golden + 10-hour soak.



Only then consider any further polish.



11. Success Definition

The pipeline turns your high-volume, stutter-heavy, technical speech into clean, correctly structured text that pastes directly into Ghostty / agents with minimal or zero manual correction, while remaining fully local, fully contained, and measurably reliable for 10-hour sessions.

Anything that does not move this needle is deleted.



End of plan.
This document is the single source of truth for the elite cleanup implementation. All code changes must be traceable to a section above.

You are working on the SuperFlow macOS dictation app (pure Swift, local-only, modular architecture).
The current Text Insertion backend in Packages/L1-Adapters/TextInsertion/ is already legitimate and green (59 tests, build + lint passing). It correctly replaced the old paste-and-sleep path with a proper decision tree, transient pasteboard markers, synthetic event isolation, Secure Input detection, and AX fallback.
However, it is still only “good”, not elite. Your job is to close the remaining architectural gaps without adding bloat, without introducing new dependencies, and without breaking any existing tests or the current public API surface.
Exact Problems to Fix

Fixed 500 ms restore timer is still a timer
Current behavior restores the previous pasteboard after a hard 500 ms sleep. This is a race condition waiting to happen under load or with slow target apps.
Paste-first architecture
Cmd+V is still the primary path. AX value replacement is only a fallback. Elite design makes AX the primary path for known editable controls and treats synthetic Cmd+V as the fallback.
Prepared PID TTL is too long (600 s)
10 minutes is excessive. Most insertion targets are valid for seconds, not minutes. Stale PID risk exists.
No back-pressure / coalescing under rapid dictation
Fast consecutive insertions can still race or queue poorly.
Character-count verification is brittle
Targets that auto-format, apply smart quotes, or modify text on paste can make pure character-count checks lie. AX whole-value comparison already exists but is under-used.

Strict Constraints (Do Not Violate)

Keep the existing injectable decision-tree design.
All AX objects must remain @MainActor.
Preserve the nspasteboard.org Transient / Concealed / AutoGenerated markers and changeCount guard.
Synthetic events must still be marked and dropped by HotkeyEngine.
Secure Input and secure-field blocking must stay mandatory and early.
No new third-party libraries.
No whole-filesystem or global state.
No timers longer than necessary; prefer event-driven or adaptive confirmation where possible.
Maintain or improve the current test coverage. Every behavioral change must have corresponding tests.
Keep the public surface of SystemTextInserter and TextInsertionService compatible unless a clear, documented improvement requires a small breaking change (then update all call sites and the ADR).
Latency budget for a normal insertion must stay under the existing 8 s session deadline (prefer much lower).

Required Outcomes

Restore strategy
Prefer restoring the previous pasteboard only after positive confirmation that the target has accepted the text, or after a short adaptive window that can be cancelled.
Hard 500 ms sleep must be eliminated or reduced to a last-resort fallback.

Primary vs Fallback path
For targets that AX can confidently classify as editable text controls, attempt AX value replacement (or selected-text replacement) first.
Fall back to synthetic Cmd+V only when AX is unavailable, ambiguous, or fails.
Keep the current behavior for .unknown containers (still allow paste).

Prepared target lifetime
Reduce the prepared PID TTL significantly (recommend ≤ 30–45 s, or make it configurable with a sane low default).
Add explicit invalidation when the frontmost app changes or when focus is lost.

Verification
Prefer AX whole-value (or selected-text) comparison as the primary success signal.
Character-count may remain as a secondary/fast check only.

Concurrency / rapid fire
Ensure that a new insertion request either cancels, coalesces, or cleanly serializes with any in-flight insertion. No overlapping pasteboard mutations.

Documentation
Update docs/adr/0022-text-insertion-backend.md with the new decision order and rationale.
Update PLAN.md §15 if the timing or primary path changes.


Process Rules

First read the current implementation thoroughly (TextInsertionService, SystemTextInserter, AX helpers, pasteboard types, SessionEngine integration).
Write failing tests that demonstrate the current weaknesses before changing production code.
Make the smallest correct changes that achieve the outcomes above.
After changes: all existing tests must still pass, new tests must pass, swift build and make lint must stay green.
Do not refactor unrelated code.
Do not introduce speculative features.

Definition of Done

The 500 ms hard sleep is gone or demoted to true last resort.
AX is primary for known editable controls.
Prepared target lifetime is short and safe.
Verification prefers real content comparison over naive character count.
Rapid consecutive insertions cannot corrupt the pasteboard or race.
ADR and PLAN.md reflect the new reality.
Full test suite + build + lint green.

Execute this upgrade with maximum precision and minimum surface-area change. Return a clear summary of what changed and why when finished.**S1-mini is already the right tool for the job in late 2026.** It is a purpose-built 0.6B Qwen3 fine-tune (GGUF ~462 MB Q4_K_M) whose only job is turning raw ASR into clean written English: kill fillers, resolve self-corrections to the final value the speaker landed on, restore punctuation/capitalization, and do inverse text normalization (numbers, currency, dates, emails, times). Token accuracy sits at 94.8 % on their held-out set; text-edit error rate 11.6 %. It is not a general LLM, it will not invent content, and that narrowness is exactly why it is trustworthy for a private dictation pipeline.

There is no public “S1-mini 2” or official successor as of October 2026. Superwhisper still ships the v1 artifact. A couple of community derivatives exist (Swedish bilingual, higher-bit GGUFs), and one competitor (SpeakoFlow-mini, another ~0.8B Qwen fine-tune) claims better restraint + edit metrics on their own eval set, but nothing has displaced S1-mini as the default specialized cleanup model that runs cleanly under llama.cpp on Apple Silicon.

### How to push cleanup quality to the absolute ceiling while staying inside the plan’s constraints

The plan already has the correct architecture (Tier 0 deterministic → S1-mini → Harper gate → line formatter, with strict fallbacks and pipelining). The elite gains come from tightening every interface around the model, not from swapping it for a bigger general LLM.

**1. Control line and prompt fidelity (biggest free win)**  
S1-mini is steered by a fixed system prompt + a three-axis control line (formality / structure / context). Copy the exact system prompt and control-line format from the model card into a resource file and pin it with a hash test, exactly as the plan says.  

Use the structure axis aggressively:
- Default to `paragraph` for prose.
- Switch to `list` when the utterance contains clear list cues (“first… second…”, “the following…”, “bullet…”, “number one…”, sequential items, or spoken “bullet points” / “list”).  
This is the legitimate 2026 way to get intelligent bullet conversion without turning the model into a general rewriter. The control line is what Superwhisper themselves use for Message/Mail/Notes modes.

Measure real truncation point in Spike B and set the soft target to ~55-60 % of that measured safe limit (not the old 1000-token rumor). Prefer ASR segment / VAD pause / sentence boundaries; never split protected spans or mid-word.

**2. Maximize the deterministic Tier 0 layer before the model ever sees the text**  
The plan already orders Commands → Shortcuts → Numbers → Lexicon → Cleanup → Numbers/Lexicon assertion → Grammar → LineFormat. Make every deterministic stage as complete and high-precision as possible:
- Numbers/currency: evaluate FluidAudio’s NeMo-style ITN component first; if it is clean, wrap it. Otherwise a data-driven table that handles cardinals, ordinals, currency (including lakh/crore later), percentages, years, decimals, and the abbreviated vs full style setting.
- Lexicon: personal + curated tech dictionary (≤150 entries, negative examples, frequency-list collision warning, Aho-Corasick or trie, longest match, case/spacing/hyphen/dot normalized). Pass terms to Harper as custom dictionary + protected spans.
- Spoken commands and shortcuts short-circuit early so the model never touches them.
- Property tests for every stage: idempotent, never touch protected spans, never throw, bounded growth, stable on empty input.

This is pure modern engineering: the model only sees already-normalized preferred forms, so it cannot undo them, and the second Numbers/Lexicon pass after the model catches any drift.

**3. Safety net around the model (the real reliability layer)**  
Keep (and harden) the plan’s TruncationDetector, hallucination guard (output words must be explainable by input + small allowed set), retry-by-split up to depth 3, then hard fallback to Tier 0 text, and OrderedStitcher + SeamRepair.  

Add:
- Per-chunk latency + token-in/out + outcome telemetry so you can tune the worker pool size (almost certainly 2–4 parallel contexts on Metal, not more).
- Interactive requests jump the queue; background meeting chunks stay bounded.
- Hard deadlines (1.5 s interactive, 30 s background) with cancellation.

This is how you get “never lose text, never block, stop-to-final stays flat for 10 h”.

**4. Fine-tune your own specialized cleanup model (the highest-leverage modern move)**  
Take the Qwen3-0.6B base (or the S1-mini weights themselves) and LoRA-fine-tune on your own data:
- Real dictations from the owner + synthetic hard cases (self-corrections, tech terms, spoken lists, currency edge cases, email/URL patterns).
- Explicit positive examples of list → bullet conversion when the speech clearly intends structure.
- Negative examples that teach restraint (do not invent, do not rephrase beyond cleanup).

This is exactly the technique used by SpeakoFlow-mini and the community Swedish S1 derivative. Keep the same TextCleaner port so the rest of the pipeline does not change. Ship the resulting GGUF behind the same bridge. Measure against the same golden set the plan already requires. If your fine-tune beats stock S1-mini on your speech + domain terms, swap it in; otherwise keep stock S1-mini and keep the fine-tune as an optional profile.

**5. Structured / bullet intelligence without breaking the “never invent” rule**  
- Use the control-line structure axis for list mode when cues are present.
- After the model, run a lightweight deterministic list detector (sentence-initial numbers/letters, repeated parallel structure, spoken “bullet”/“item”/“point”) that only reformats existing content into Markdown bullets or numbered lists. Never invent new items.
- Line formatter already handles paragraph breaks; extend its streaming carry-over state so incremental formatting of a long session is identical to batch formatting (required test).
- For meetings, keep speaker turns clean and never mix speakers inside one cleanup chunk.

**6. Harper stays gated exactly as written**  
Only high-precision categories (≥98 % on the golden set), edit budget ≤3 % of words, protected spans, 50 ms time cap, idempotent. If a category fails the precision bar, leave it disabled. That is the correct modern stance: grammar is a measurable gate, not a hope.

**7. Optional future-proofing that still fits the architecture**  
- Keep the TextCleaner port thin so you can drop in a better specialized 0.6–1 B model the day one appears (or your own fine-tune).
- Spike whether a slightly larger on-device model (1–2 B range, still Metal-friendly) improves quality enough to justify the latency/memory hit for interactive dictation. Most current evidence says the specialized 0.6 B wins on latency and restraint for pure cleanup.
- Do **not** fall back to a general 7–8 B chat model for the live path; the plan correctly rejects that.

### Bottom line for maximum elite quality

Stay with S1-mini (or a carefully measured fine-tune of it) as the speed layer.  
Make Tier 0 and the safety net around it as complete and ruthless as possible.  
Drive the control line hard for structure.  
Keep every stage deterministic where it can be, measurable, and fallible only into the previous good state.  

That combination—specialized small model + heavy deterministic pre/post + strict acceptance gates + pipelined bounded workers—is the actual state-of-the-art legitimate approach for private, on-device, high-reliability dictation cleanup in October 2026. Bigger general models are slower, more expensive, and more likely to invent or over-edit. The plan’s architecture already points in the right direction; the elite gains are in the measurement, the fine-tuning data, and the iron-clad fallbacks.