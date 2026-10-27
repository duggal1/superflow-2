# TextNumbers: table-driven Swift vs. FluidAudio/NeMo text processing

Date: 2026-10-26
Status: accepted

## Question

PLAN section 9 asks us to evaluate FluidAudio's text-processing component (a Rust
port of NVIDIA NeMo text processing) before writing our own number formatter.

## What exists

- `FluidAudio.TextNormalizer` (`Sources/FluidAudio/ITN/TextNormalizer.swift`)
  wraps the `CNemoTextProcessing` binary target and offers
  `normalize(_:)` plus sentence-mode normalization. It handles cardinals,
  currency, dates and punctuation spoken forms.
- `FluidAudio.NemoTextNormalizer` is the written-to-spoken direction used by the
  TTS frontends. It is the wrong direction for dictation.
- The binary target is `text-processing-rs` v0.3.1, a ~59.5 MB static archive per
  macOS slice (`libtext_processing_rs.a`, arm64+x86_64) inside a 197 MB
  XCFramework.

## Why it does not bind cleanly

1. **Layer violation.** `FluidAudio` is an L1 adapter. `TextNumbers` is an L2
   engine and may depend on L0 only. Importing FluidAudio from the stage (or
   adding an L1 dependency to the L2 manifest) breaks `tools/check-deps` and the
   PLAN's module catalog. Routing it through a port would make every Tier 0
   number call asynchronous and adapter-owned, which contradicts the
   deterministic-under-5 ms Tier 0 contract.
2. **Protected spans.** The stage must never touch URLs, emails, code-like
   tokens, dictionary terms or shortcut expansions. The NeMo API normalizes a
   whole string and has no span-aware entry point, so we would have to mask and
   restore spans around it. That is more code than the formatter.
3. **Settings.** PLAN section 9 requires `LargeNumberStyle` (abbreviated `k/M/B`
   by default, full `$200,000` on request), the zero-through-nine prose rule,
   INR lakh/crore grouping, and a per-stage data table. The NeMo engine exposes
   none of these as options; its output is fixed.
4. **Link risk.** Harper is also a Rust static library. The two archives share
   327 global symbols (compiler-rt helpers and `___rust_*` intrinsics), so
   linking both into the app creates duplicate-symbol risk for no functional
   gain. The Harper gate is a Tier 2 feature; number formatting is Tier 0.
5. **Startup and memory.** Tier 0 must stay free of model/binary warm-up. The
   table implementation has no load step and no resident allocation.

## Decision

Keep the table-driven Swift implementation in `SuperflowTextNumbers`:

- `NumberTables.swift` owns the data: units, teens, tens, scales
  (thousand/million/billion/lakh/crore), currency specs with symbol and
  grouping, measures, months, ordinal contexts and identifier keywords.
- `NumberParser.swift` parses spoken number phrases, years and ordinals.
- `NumbersStage.swift` walks tokenizer tokens over the original line, so
  whitespace outside a rewritten span is preserved and protected spans are
  never edited.

Adding a currency is a table edit (`CurrencySpec`), not a parser change.

## Revisit when

- FluidAudio exposes a span-aware, synchronous ITN API with configurable number
  style and Indian grouping, and
- the NeMo archive can be linked without colliding with Harper's Rust runtime,
  or the app moves Harper out of process.

Until then the table implementation is the smaller, deterministic, testable
choice and satisfies the Tier 0 budget.
