# ADR 0020: Code Speak grammar and context profiles

Status: Accepted

## Context

Addendum A Phase 3b adds spoken-to-code rewriting (`TextCodeSpeak`) and
`ContextProfiles` to the text stack. Both run on the typing path, so they must be
deterministic, idempotent and unable to block or damage a dictation. The
repository had neither package; `TextPipeline` only ended its deterministic tier
with numbers, lexicon, cleanup and line format.

Before this change the cleanup stage also hardcoded `context: "general"`, so a
profile could not influence the cleaner even if one existed.

## Decision

### 1. Code Speak is opt-in and local

- `AppSettings.codeSpeakEnabled` defaults to `false`. `TextPipelineBuilder`
  inserts `CodeSpeakStage` after `numbers` and before `lexicon` only when it is
  on. Existing installs decode the missing key as `false`.
- A stage never throws. Ambiguous input is returned unchanged.

### 2. Grammar and guards

Rules are bounded to one line and one clause:

| Rule | Recognised speech | Output |
| --- | --- | --- |
| identifiers | `camel/snake/kebab/pascal/constant case …` | `userProfileId`, `user_profile_id`, … |
| paths | `src slash components slash button dot swift` | `src/components/button.swift` |
| flags | `dash dash verbose`, `dash v`, `double dash dry` | `--verbose`, `-v`, `--dry` |
| brackets | `open paren … close paren` (also brackets, braces, angle) | `(…)`, `[…]`, `{…}`, `<…>` |
| operators | `triple equals`, `double colon`, `fat arrow` | `===`, `::`, `=>` |
| arrow | `arrow` next to a code-shaped token or path | `->` |
| backticks | `backtick … backtick` | `` `…` `` |
| code block | `code block` / `end code block` on their own lines | fenced block |

Precision guards, in order:

1. Protected spans (URLs, emails, camelCase, digits, backticks) are skipped.
2. Identifier commands consume at most 8 words and stop at `.,;:!?`. A target
   containing an article, pronoun, auxiliary or conjunction is left alone, so
   "snake case for this" is prose.
3. A single-word identifier must be code-shaped or in a small allowlist of
   common code nouns; "camel case study" is not rewritten.
4. Path pieces reject stopwords. A path needs a slash, two dots, or a known
   file extension, so "a dot b" stays prose.
5. Bracket commands only convert when the matching close command is on the same
   line. "open parenthesis in the document" is prose.
6. `arrow` requires an adjacent code-shaped token or a nearby path separator.
7. A stage that produces nothing adds no diagnostic and no edit.

### 3. Protected output

Every code-shaped literal the stage emits is added to `Protected.literals`, so
cleanup, the grammar gate, later numbers/lexicon passes and line format cannot
rewrite it. A code block is protected as one multi-line literal. Single
lowercase words are not protected because they are indistinguishable from prose.

### 4. Explain mode

`CodeSpeakStage` conforms to `ExplainingTextStage` and reports the exact rule id
(`identifier.camel`, `path`, `flag.long`, `symbol.closeParen`, `backtick`,
`codeBlock.marker`, …). Input spans exclude preserved trailing punctuation;
output spans cover only the replacement body. The recording path never asks for
this explanation.

### 5. Context profiles are pure data

`ContextProfile` carries styling, structure, cleanup context and
`codeSpeakEnabled`. `ContextProfileResolver` is a pure function of an explicit
profile id, bundle id and host:

1. explicit profile id (unknown ids fall through, never fail);
2. exact bundle id, or prefix when the rule ends in `.`;
3. host domain or subdomain, with scheme, path, port and `www.` stripped;
4. Writing as the fallback.

Custom profile lists keep the first entry for a duplicate id; a rule that points
at a missing profile is skipped. Applying a profile copies `AppSettings` and
changes only the four profile-controlled fields.

`AppSettings.cleanupContext` now exists (default `"general"`) and
`CleanupService` passes it to `CleanOptions`, replacing the hardcoded value.

## Alternatives considered

1. Let the cleanup model infer code intent. Rejected: non-deterministic and it
   puts code formatting on the model path.
2. Convert any command word anywhere. Rejected after the ordinary-English
   corpus tests: "the camel case study" and "open parenthesis in the document"
   were rewritten.
3. Require explicit mode switching for every Code Speak phrase. Rejected for
   now: the addendum keeps the typing path hands-free, and the opt-in setting
   already scopes the risk.
4. Put profile resolution in `Ports`. Rejected for this phase: no adapter or
   second implementation exists yet. The resolver is an L2 value type; a port
   can be extracted when detection is wired in Phase 7c.

## Consequences and limits

- Code Speak vocabulary is a first cut and ships off by default. Enabling it
  needs real dictation precision evidence; the trigger list is an owner
  question in `docs/open-questions.md`.
- Bundle and host mappings are a maintained list, not detection. Adding an app
  means adding a `BundleRule`/`HostRule`; unknown apps resolve to Writing.
- `cleanupContext` changes the cleaner prompt for all callers once a profile is
  applied. The default keeps existing behaviour byte-identical.
- Symbols require typing the closing command. A user who dictates only
  "open brace" gets prose, by design.

## Evidence

- `Packages/L2-Engines/TextCodeSpeak/` — 13 tests (goldens, idempotence,
  protected spans, ordinary-English corpus, bounded growth, explain spans).
- `Packages/L2-Engines/ContextProfiles/` — 14 tests (precedence, prefix/host
  boundaries, fallback, duplicate ids, missing profiles, settings application).
- `Packages/L2-Engines/TextPipeline/Tests/TextPipelineTests/PipelineTests.swift`
  — stage order and opt-in wiring.
- `make verify` passed on 2026-10-27 after the change.
