# Superflow: implementation plan for review

Scope: text intelligence, formatting, dictionary learning, a unified Knowledge page, and a genuine streaming-model marketplace.

Current baseline: `main` at `a73798bc905bfa1e5a39072f1f669f6d9a657025`.

No code changes will be made before you approve the plan. The eventual implementation should preserve existing work, use migrations rather than replacing stored data, and merge into `main` only after verification.

## 1. Problems confirmed in the code

| Area            | Current implementation                                                   | What needs to change                                                                           |
| --------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Model names     | Fixed vocabulary aliases and post-processing rules                       | Recognize model families, version numbers, and naming structures independently                 |
| Formatting      | S1-mini followed by `PostDedupeStage` and `FormattingStage`              | Reliable spoken lists, paragraph boundaries, and guarded formatting                            |
| Coding text     | Code Speak exists, but filename and shell-command handling is fragmented | One consistent contextual parser for filenames, extensions, paths, identifiers, and Git syntax |
| Dictionary      | SQLite stores terms, triggers, and corrections                           | Add learning from confirmed user edits, contextual matching, confidence, and feedback          |
| Shortcuts       | Separate feature, storage, and UI                                        | Combine with Dictionary under Knowledge, preserving both behaviors                             |
| Models          | One selectable speech profile: Nemotron 3.5                              | Verified streaming-model catalog, search, download, activation, and comparison                 |
| Model selection | The speech-model picker remains in Settings                              | Move selection to Models and make activation persistent                                        |
| Notifications   | Island notices and bundled sound effects already exist                   | Reuse them for actual dictionary-learning events                                               |

The current `AudioCppRecognizer.supports()` explicitly accepts only the default Nemotron profile. Adding names to `ModelProfile.all` will not make other models run. Supporting them requires changes to the runtime, model assets, session handling, and tests.

That distinction matters: a catalog is not a model engine.

One additional blocker needs to be in the implementation plan: the latest GitHub verification is failing inside GGML Metal, with `unsupported op 'MUL_MAT'` during audio.cpp streaming-model preparation. The Swift 6.4 compiler check now passes. This is a native-runtime failure, not the old compiler-version problem.

I would treat that as a release gate rather than make CI green by simply skipping the failing model test.

For additional ASR support, upstream audio.cpp documents candidates including Moonshine Streaming, Qwen3-ASR, Voxtral Realtime, VibeVoice Streaming, CrisperWhisper and others. But its documentation also distinguishes actual capture-time partial transcription from streaming the response to an already uploaded audio file. Only the former, with verified live-session behavior, should qualify for your Models page.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub+2



## 2. Phase A: text intelligence backend

### A1. Model-name and version intelligence

Objective: recognize model names naturally without maintaining a separate dictionary entry for every release.

I would build a Swift `ModelNameNormalizer` using three mechanisms:

1. Family recognition: identify provider names, model families, and known spelling variants. Cover at least 25 families and naming patterns, including GPT, ChatGPT, Claude, Opus, Sonnet, Haiku, Gemini, Gemma, Grok, Qwen, DeepSeek, Llama, Mistral, Mixtral, Phi, Nemotron, Kimi, GLM, MiniMax, Command, Granite, Jamba, Falcon, ERNIE, Nova, Sonar, and others.
2. Version grammar: parse spoken numerical sequences instead of enumerating every version. Recognize major versions, decimals, suffixes, model sizes, and variants.
3. Contextual candidate scoring: use word boundaries, phonetic similarity, neighboring technical terms, the active app, and confidence margins to decide whether a correction is justified.

The model-family registry defines naming conventions. It does not need an entry for every `5.1`, `5.5`, `5.55`, `6.1`, or future version.

Examples of intended behavior:

| Dictated speech                  | Expected formatted text |
| -------------------------------- | ----------------------- |
| claude opus five point five five | Claude Opus 5.55        |
| chat gbd                         | ChatGPT                 |
| grok four point one              | Grok 4.1                |
| entropic claude                  | Anthropic Claude        |
| open air models                  | OpenAI models           |
| open air concert                 | open-air concert        |
| gemini three point five flash    | Gemini 3.5 Flash        |

These are transcription examples, not assertions that every example is an officially released model.

The underlying logic should be a small finite-state grammar with probabilistic candidate ranking, not a huge pile of unrelated regex replacements.

A candidate correction can be expressed as:

\\[ \text{score}(c)=w_a A(c)+w_v V(c)+w_c C(c)+w_u U(c) \\]

Here \\(A\\) measures acoustic or phonetic similarity, \\(V\\) measures valid model-name and version structure, \\(C\\) measures surrounding context, and \\(U\\) measures user-specific knowledge. Weights and thresholds must be calibrated using examples, not invented as accuracy claims.

Critical rule: ordinary language wins whenever there is insufficient evidence that the speaker named a model.

Implementation targets: a new `ModelNameNormalizer` module, integration through `TextPipelineBuilder.swift`, and expanded `ModelNamingTests.swift`.

Acceptance: all supported family/version patterns have positive tests, ambiguous everyday phrases have negative tests, and protected literals survive unchanged.

### A2. Elite formatting with S1-mini

The current repository already has useful building blocks: `EnumerationDetector`, `ListShaper`, `ParagraphShaper`, `FormatGuard`, and `CleanupService`. I would improve and integrate those rather than create a competing formatter.

INPUT

"First fix the authentication bug, second run all the tests, third push the changes."

EXPECTED OUTPUT

1\. Fix the authentication bug.\
2\. Run all the tests.\
3\. Push the changes.

The architecture:

- S1-mini remains the primary editor. It decides sentence breaks, punctuation, natural paragraphs, and likely list structure.
- An enumeration detector reads the original speech. If the speaker clearly said first, second, third, those markers are structural evidence.
- A deterministic repair layer corrects malformed lists. It turns explicit enumerations into `1.`, `2.`, `3.`, preserving the exact item content.
- A formatting guard rejects damage. No missing list items, duplicated phrases, changed filenames, invented headings, or changed meaning.
- Uncertain structure remains prose. “First I went to work, and then I ate lunch” must not automatically become a numbered list.

The same system supports bullets when the utterance actually describes bullet points, including `- Item` on separate lines, without requiring users to dictate punctuation manually.

One additional requirement: when S1-mini already produces a correct list, deterministic stages should leave it alone.

Acceptance: ordered lists, unordered lists, nested spoken items, long enumerations crossing chunk boundaries, code blocks, and paragraph splitting all pass regression tests. Formatting must be idempotent.

### A3. Code intelligence

Build a `CodeLanguageNormalizer` around the existing Code Speak, Code Aware, normalization, and project-index facilities.

ILLUSTRATIVE TRANSFORMATIONS

| Spoken                     | Formatted                 |
| -------------------------- | ------------------------- |
| agents dot md              | `AGENTS.md`               |
| architecture dot md        | `architecture.md`         |
| design dot md              | `design.md`               |
| package dot json           | `package.json`            |
| source slash app dot swift | `src/App.swift`           |
| git remote v               | `git remote -v`           |
| get checkout main          | `git checkout main`       |
| get add                    | `git add`                 |
| git commit m fix bug       | `git commit -m "fix bug"` |

Use a tokenizer and a small shell/filename grammar that understands known extensions, paths, flags, quoted arguments, and Git subcommands.

Do not globally replace `get` with `git`. That would damage ordinary dictation. `get → git` should require strong command syntax or developer context.

There is also an important distinction between formatting a command and inventing a command. Saying “git add” should remain `git add`. It should not silently become `git add -A`, because that changes the operation and can stage unrelated files. Similarly, “git commit” must not invent a commit message.

For multi-command utterances, generate `&&` or `;` only when the user explicitly dictates command chaining or selects an intentional command-template shortcut.

Shortcuts get a special preflight: exact whole-utterance triggers should be detected before S1-mini can paraphrase them. This allows “design dot md” to expand into the user's saved long Markdown template without the model rewriting its contents.

Acceptance: technical strings are exact, surrounding prose is preserved, no commands execute, and ambiguous phrases remain untouched.

## 3. Phase B: dictionary architecture

This is more substantial than the formatting work.

The current `LexiconEntry` has `id`, `kind`, `triggers`, `canonical`, `enabled`, and `source`. That is enough for manual replacement, but insufficient for learning, per-app relevance, or confidence.

The target design has three separate responsibilities:

Apply

ASR hints + contextual post-correction

Learn

User edits + confirmed corrections

Store

SQLite + metadata + reversible learning

### B1. Applying the dictionary

Layer A: ASR vocabulary hints. Select a bounded top-K list based on the active app, explicit project context, user corrections, and term relevance. Pass it only to ASR engines that genuinely support contextual biasing through their native API. Do not pretend every audio.cpp model supports identical hotword inputs.

Layer B: deterministic post-correction. Extend the existing `LexiconStage` trie matcher. Keep longest-match rules, exact user corrections, protected spans, and the Tier A/Tier B contextual gates. Add a phonetic candidate index for plausible transcription variants, with strict thresholds to avoid turning normal English into product names.

Layer C: S1-mini context. Evaluate a compact dictionary hint mechanism for the existing cleanup prompt contract. This should be tested separately because the S1-mini prompt is pinned and changing it can degrade output. Deterministic post-correction remains the authority for exact spellings.

This must be incremental. There is no justification for discarding the existing v4 tech dictionary or its evaluation corpus.

### B2. Learning from user edits

I would build an `InsertionEditWatcher` in the native TextInsertion adapter and a separate `DictionaryLearningEngine`.

The sequence:

1. Superflow successfully inserts a transcript.
2. If the user enabled learning, record a short-lived anchor to the inserted text and the target editable element.
3. Observe changes through Accessibility APIs for a limited window.
4. Identify substitutions within the inserted region.
5. Reject broad rewrites, punctuation-only edits, unrelated surrounding text, and uncertain matches.
6. Generate a proposed correction with a confidence estimate.
7. Persist a confirmed correction, then notify the user.

The watcher must stop on focus changes, new sessions, secure-field detection, permission loss, or expiry. It must never become a global keystroke logger.

One technical correction to the proposed architecture: macOS Accessibility does not always expose just a requested text range. Some controls only expose the entire field value. Where bounded reads are unavailable, the watcher must either skip that control or disclose and constrain temporary full-value access. Full-field contents must never be persisted or transmitted as learning telemetry.

Learning policy I recommend:

- A user explicitly editing a dictionary entry saves immediately.
- A detected first correction creates a candidate, not an unquestionable permanent rule.
- Two independent, high-confidence repetitions can auto-promote the rule when automatic learning is enabled.
- Lower-confidence candidates require user confirmation.
- Every automatic addition offers Undo.

This avoids learning the mistake that someone intentionally rewrote an entire sentence.

### B3. SQLite schema and migration

Do not replace existing tables or lose existing dictionary entries.

Add a versioned migration extending the dictionary with fields such as `app_scope`, `heard_forms`, `phonetic_key`, `learned_from`, `confidence`, `confirmation_count`, `hit_count`, and timestamps. Keep the user's canonical spelling authoritative.

Separate observed candidates from active dictionary rules, so a rejected suggestion cannot accidentally influence future transcription.

Keep SQLite as the source of truth. I would not introduce cloud sync into this release: Superflow has no general user-account and sync infrastructure, and adding that merely to implement vocabulary learning would fundamentally change its privacy architecture.

### B4. Learning notification

Use the existing Island event and notice infrastructure rather than a new notification system.

On a successful database commit, show a compact Island notice:

> Added to Knowledge\
> `next year` → `Next.js`\
> Undo

Reuse the existing confirmation sound, optionally and with rate limiting. The state change should be real: the new correction must already exist in SQLite before the animation or sound fires.

If recording or meeting UI is active, queue the notice. Do not interrupt capture. Respect Reduce Motion, VoiceOver, the Island's one-animation-at-a-time rule, and the existing notice expiry behavior.

## 4. Phase C: merge Dictionary and Shortcuts into Knowledge

The UI changes happen after the underlying vocabulary and learning logic is verified.

Keep the existing dictionary and shortcuts data, functionality, and import/export contracts. Merge their presentation, not their meaning.

## Knowledge.

Search terms and shortcuts

All

Dictionary

Shortcuts

Learned

DICTIONARY

Next.js

next year, next jay s

SHORTCUTS

design.md

Expands to your saved Markdown template

RECENTLY LEARNED

Idempotency

Corrected from “item potency”

Structural wireframe only. Final UI must use the actual Superflow design tokens, components, and native layout.

The page should include a real search, filters, term and shortcut editing, enable/disable, import/export, a correction playground, learned suggestions, and Undo. A shortcut can contain long Markdown and remains byte-for-byte unchanged when expanded.

The sidebar should have one Knowledge route in place of Dictionary and Shortcuts. Preserve old route IDs as migration aliases where necessary, including saved navigation selections and keyboard shortcuts.

### Design implementation rules

The uploaded `DESIGN.md` is the visual authority. Before writing UI, the implementation must derive the page skeleton, hierarchy, spacing, states, and token usage from it.

In particular:

- Reuse the current `Page`, `ListControls`, `DialogHost`, input, and menu components.
- Use the specified 32-point search field, 44-point Knowledge rows, 4-point spacing grid, and existing typography.
- No gradients, strokes, nested-card layouts, decorative AI icons, or new colors.
- Only one primary action per view.
- State-driven animation only, with Reduce Motion support.
- Ensure keyboard navigation, VoiceOver labels, dark/light appearance, and confirmation/error states are complete.

The existing design document still describes separate Dictionary and Shortcuts pages. After approval, update those specific sections to the new Knowledge structure. Do not rewrite the rest of the design system.

## 5. Phase D: streaming model infrastructure and Models page

This is the final major feature phase, as requested.

### D1. Build a real streaming-model registry

First, audit the exact pinned audio.cpp revision and its compiled model families. The build script currently enables only `nemotron_asr` and `nemotron_3_diar`, while `AudioCppAsset` is hardwired to one ASR model plus diarization.

Replace the single-model assumption with a typed, verified catalog containing model identity, upstream version, runtime compatibility, streaming behavior, artifact files and checksums, license, supported languages, download size, and hardware requirements.

Candidate families to investigate include:

| Candidate                  | Reason to investigate                                 |
| -------------------------- | ----------------------------------------------------- |
| Nemotron 3.5 ASR Streaming | Current baseline                                      |
| Moonshine Streaming        | Smaller native streaming models                       |
| Qwen3-ASR 0.6B / 1.7B      | Multilingual ASR with streaming mode                  |
| Voxtral Realtime           | Designed around realtime transcription                |
| VibeVoice ASR Streaming    | Persistent streaming decoder and speaker-aware output |
| CrisperWhisper 2.0         | Streaming-capable transcription family                |
| Higgs Audio STT            | Additional native streaming candidate                 |
| Parakeet-TDT               | Streaming implementation to validate                  |
| SenseVoice                 | Streaming implementation to validate                  |
| Kroko                      | Community streaming model to validate                 |

These are candidates, not currently installed or proven compatible Superflow integrations. Some may require new build configuration, C ABI support, larger memory, or licensing review. They cannot be promised as functioning based only on upstream model lists.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub+1



The release rule is strict: only verified, live-streaming ASR models appear as selectable. A model that transcribes a complete recording and streams its response afterward does not pass.

### D2. Model download and activation

Every supported model must provide:

- Install, progress, cancel, verify, retry, remove, and activate.
- Pinned artifacts and checksum validation.
- Installation status independent from activation status.
- Lazy loading, bounded memory use, and no accidental redownload.
- Persisted selection across relaunches.
- A safe fallback to the previous working model when activation fails.

Do not swap ASR engines during active dictation or meeting capture. A changed selection takes effect for the next session after readiness checks. Meetings and recovery must use the correct model-specific interfaces.

Settings should still store the selection internally. Only the control moves to Models. Remove the redundant speech-model picker from Settings.

### D3. Search and model-page layout

The Models page should have functional local search by name, vendor, language, task, and model family, plus filters for Installed, Available, and All. Selecting a result should expose the exact model details and its installation or activation action.

The existing pipeline strip can remain, but it should display the actual active components rather than implying every catalog entry is active.

A model row should show its name, vendor, relevant language support, model size, streaming status, installation state, and one clear action.

### D4. Intelligence score and recommendation

I would not make up quality scores. Each model needs a reproducible benchmark on the same audio corpus, under the same conditions.

An initial Intelligence score can be a documented, weighted transcription-quality score based on word accuracy, technical-term recognition, numbers, and proper-name recognition. The weights are product-design choices; actual values come from benchmark results.

Report performance separately: time to first useful partial, finalization latency, realtime factor, peak memory, and long-session reliability.

Recommended should be device-specific and evidence-based. A model that is slightly more accurate but cannot transcribe continuously at usable latency on the user's Mac is not the best default.

Until measured, display Not benchmarked rather than a fictional score.

## 6. Phase E: performance and reliability

Extreme parallelism is not automatically faster.

The existing llama.cpp runtime defaults to two sessions because additional GPU workers have previously shown contention. The cleanup coordinator also separates work performed during recording from the remaining work drained afterward.

The implementation should benchmark before changing those limits.

The optimization work:

1. Profile ASR, cleanup prefill/generation, deterministic text stages, SQLite operations, and UI delivery separately.
2. Run independent CPU-bound tasks concurrently where beneficial.
3. Keep Metal-heavy model concurrency bounded and adaptive.
4. Reuse warmed models, tokenizers, tries, and compiled regexes.
5. Precompute small candidate indexes instead of scanning an entire dictionary for every word.
6. Use incremental processing without processing the same completed transcript repeatedly.
7. Protect realtime capture and journaling from backpressure.
8. Benchmark short dictations and long meetings independently.

Success means measured lower latency without worse transcription quality, higher failure rates, or unbounded memory. Worker count by itself is not a success metric.

The existing Metal CI crash is a mandatory blocker to investigate. Do not weaken production tests or remove useful native tests merely to make the badge green.

## 7. Verification gates

| Gate        | Required evidence                                                                                  |
| ----------- | -------------------------------------------------------------------------------------------------- |
| Naming      | Positive and negative corpus for 25+ model naming patterns; versions and ambiguous phrases         |
| Lists       | Numbering, bullets, multi-paragraph structure, long-input chunk seams, idempotence                 |
| Coding      | Exact filename, path, extension, identifier, shell-command and Git transformations                 |
| Dictionary  | Contextual false-positive tests; phonetic candidates; protected-text preservation                  |
| Learning    | Real AX edit detection, opt-out behavior, secure-field exclusion, Undo, SQLite restart persistence |
| Knowledge   | Existing entries and shortcuts survive migrations; search, CRUD, import/export, preview all work   |
| Models      | Every selectable model downloads, verifies, starts live streaming, and can be safely activated     |
| Performance | Repeatable, same-machine before/after latency and memory comparisons                               |
| Design      | Dark/light screenshots, keyboard/VoiceOver, motion, pixel alignment, `DESIGN.md` review            |
| Release     | Focused tests, native runtime checks, packaged app, `make verify`, and working GitHub CI           |

The acceptance suite should also run real dictation into common Mac text fields, coding editors, browser inputs, and a long-running meeting session. Synthetic tests are necessary but insufficient.

## 8. Execution order and merge policy

| Order | Work package                             | Exit condition                                              |
| ----- | ---------------------------------------- | ----------------------------------------------------------- |
| 0     | Freeze baseline and investigate CI       | Reproducible test baseline and known native-runtime failure |
| 1     | Model names and version grammar          | Naming corpus passes                                        |
| 2     | S1-mini formatting and code intelligence | Formatting and coding acceptance passes                     |
| 3     | Dictionary matcher and SQLite migrations | Existing data preserved, correction tests pass              |
| 4     | Edit learning and Island notification    | Confirmed learning works, privacy and Undo verified         |
| 5     | Unified Knowledge UI                     | Complete native design and interaction tests                |
| 6     | Streaming-model backends and catalog     | All selectable models truly supported                       |
| 7     | Models page selection, search, scoring   | Search, activation, download, and honest ratings work       |
| 8     | Cross-feature regression and performance | All release gates pass                                      |
| 9     | Merge into `main`                        | Verified final implementation, no unrelated reversions      |

Each package should have its own focused plan, tests, and reviewable diff. Before any Git write, follow `GIT-SKILLS.md`; preserve concurrent work, stage explicit paths, and inspect changes before merging.

Preservation rules: no wholesale pipeline rewrite, no reset or revert of existing work, no dropped SQLite records, no removal of working meeting features, no unrequested design overhaul, and no unsupported model offered as functional. Existing behavior should only change where a new requirement explicitly replaces it.

Current status: plan only. No files, branches, commits, or database contents were changed.
