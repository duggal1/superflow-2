# Superflow agent guide

Ship the requested behavior completely. Preserve correctness, privacy, accessibility, architecture, and visual quality. Save usage through focused context and verification, never by weakening acceptance criteria.

<!-- INIT-RULES:START — do not remove this marker. Managed by `init rules`. -->
Read [GIT-SKILLS.md](GIT-SKILLS.md) before Git writes. Read [RULES.md](RULES.md) for substantial engineering work. Small, low-risk edits use inspect → edit → verify.

This guide overrides blanket full-repository reading and repeated-check mandates in referenced documents. Load task-relevant context; preserve required release gates. Git conflicts resolve in favor of GIT-SKILLS.md: stage explicit paths; do not pull or stage everything.
<!-- INIT-RULES:END -->

## Product and architecture

Superflow is a native, local macOS 15+ dictation and meeting app for Apple silicon. Swift 6 strict concurrency, SwiftUI, AppKit host integration, SQLite WAL. No shipped web frontend, Python, cloud inference, accounts, or telemetry. Network use is limited to model downloads and optional update checks. Never log transcript text or audio.

| Location | Ownership and allowed dependencies |
| --- | --- |
| `Packages/L0-Core` | Kernel types, Ports protocols, TestKit fakes; core dependencies only |
| `Packages/L1-Adapters` | Audio, ASR, LLM, storage, insertion, permissions; depend on L0 |
| `Packages/L2-Engines` | Session, meeting, recovery, gestures, text stages; depend on L0 and L2 |
| `Packages/L3-Features` | Views and view models; depend on L0, L2, and L4 |
| `Packages/L4-UI` | DesignSystem, Icons, UIComponents; depend on L0 and L4 |
| `App/SuperflowApp` | Composition root and coordinator; wires concrete adapters into engines |
| `App/InferenceHelper` | XPC service owning llama.cpp inference; ASR currently remains in the app |

Flow: gesture → audio capture and durable journal → streaming ASR → deterministic text stages → local cleanup and grammar acceptance gate → insertion and SQLite persistence. Cleanup runs during long recordings. Failures return the last safe text; they must not lose or silently truncate content. Keep queues bounded, cancellation explicit, and lifecycle operations idempotent. Audio callbacks must not allocate, lock, log, or invoke Swift concurrency.

Use constructor injection, typed contracts, declarative views, and focused files. No force casts, unjustified unchecked concurrency, unrelated refactors, or stubs. Validate boundaries. Follow [dependency enforcement](tools/check-deps).

## Models and runtime facts

- ASR default: Nemotron 3.5 ASR Streaming 0.6B via FluidAudio/Core ML. Runtime: Latin, 2240 ms, CPU+GPU. Profile metadata contains older tier values; inspect the catalog and loader before changes.
- Cleanup: S1-mini by Superwhisper, Q4_K_M GGUF through llama.cpp in the XPC helper. Preserve the pinned prompt, deterministic settings, attribution, deadlines, and fallback behavior.
- VAD: Silero through FluidAudio. Speaker separation uses the FluidAudio diarization adapter. Grammar uses Harper through the Rust C ABI.
- The user controls the Codex model/reasoning settings. Do not change them or launch additional agents without authorization.

Sources: [profiles](Packages/L0-Core/Kernel/Sources/SuperflowKernel/Models.swift), [ASR catalog](Packages/L1-Adapters/ASRFluidAudio/Sources/SuperflowASRFluidAudio/FluidAudioCatalog.swift), [compute policy](Packages/L1-Adapters/ASRFluidAudio/Sources/SuperflowASRFluidAudio/FluidAudioEngineFactory.swift), [model manifest](Packages/L1-Adapters/ModelStore/Sources/SuperflowModelStore/Resources/model-manifest.json), [XPC decision](docs/adr/0007-xpc-inference-helper.md). Registry entries are not proof that a model is installed or verified.

## Design rules

Read [DESIGN.md](DESIGN.md) §0–§5 and the affected component section; Island work reads §8.18. Check stale examples against current tokens/APIs. Report material conflicts.

- Calm, restrained, neutral surfaces. Blue 600 is the semantic accent. Separate content through spacing and surface contrast, without decorative borders, shadows, gradients, or glow.
- Use `Tok`, `Ramp`, `AppType`, spacing and radius tokens. Align to the 4 pt layout grid and device pixels through `Pixel`. SF Pro UI roles are 12/13/15/28 pt; dynamic numbers use tabular digits and stable widths.
- Use shared controls from UIComponents and SF Symbols from Icons. Features do not introduce raw interactive controls, arbitrary fonts, cursor management, or new visual systems.
- Native blur/glass belongs to navigation and designated floating chrome. The Island is opaque black, attached to the screen edge, with no shadow. Only its designated text-fade masks use gradients.
- Motion communicates state, without bounce or decorative loops. Honor Reduce Motion, keyboard focus, VoiceOver, contrast, light/dark appearance, and minimum window size. Preserve documented functional animation exceptions.
- Change design only when requested. Inspect actual native UI for visual changes; compilation alone cannot prove layout or focus works.

## Read only what the task needs

| Question | Reference |
| --- | --- |
| Product scope and implementation phases | [PLAN.md](PLAN.md), relevant numbered section; historical proposals need verification |
| Current runtime evidence and unresolved work | [docs/STATUS.md](docs/STATUS.md), relevant [ADR](docs/adr/) |
| Visual specification | [DESIGN.md](DESIGN.md); [DESIGN-RULES.MD](DESIGN-RULES.MD) and [rebuild guide](DESIGN-REBUILD-GUIDE.MD) are subordinate historical references |
| Engineering workflow | [RULES.md](RULES.md), task-relevant sections |
| Active task plans and previous findings | [work/plan](work/plan/), relevant task under [agents](agents/) |
| Packaging, permissions, recovery | [architecture](docs/architecture/), relevant [runbook](docs/runbooks/) |
| Commands and module overview | [Makefile](Makefile), [README.md](README.md) |

Local skills are optional unless their invocation rules require them. Resolve these under `~/.agents/skills/` and read only the matching SKILL.md: `engineeringkit-skill-router/SKILL.md` for UI/backend routing, `principle-fix-root-causes/SKILL.md` for debugging, `principle-prove-it-works/SKILL.md` for direct verification, `benchmark-checklist/SKILL.md` for measured performance, and `technical-writing/SKILL.md` for documentation. Existing project rules outrank generic skill aesthetics. Never preload the catalog.

## Work and verification

1. Inspect Git state and the target implementation. Trace affected callers, contracts, and tests. Use `rg` and bounded reads. Expand on evidence; do not reread unchanged context.
2. Make the smallest complete change. For substantial work, keep one concise plan and record useful decisions/results as RULES.md requires. Skip optional artifacts unless required or needed to resolve uncertainty.
3. Run affected package tests with `swift test --package-path <package>`. Add behavioral regression coverage for meaningful failures. Check connected packages when contracts change. For UI, inspect relevant native states; for pipelines, run affected goldens/integration tests; for performance, measure the real workload.
4. Run required gates after stabilization. Repeat passing checks only when changes invalidate them. Documentation edits need reference/consistency/diff checks, not application builds. `make verify` remains the full phase/release gate; `make lint` checks architecture and forbidden patterns. Never bypass a failing hook or weaken a check.
5. Review the actual diff. Fix task-related failures; report unrelated ones without modifying another worker's changes. Stop when behavior and applicable checks pass.
6. Commit and push each coherent change directly to main, using explicit owned paths and a specific 6–12-word message. Never mix another worker's edits into the commit. Stop on a rejected push; never force, pull, merge, reset, or rewrite without the permission required by GIT-SKILLS.md. Leave unrelated dirty files alone.

Report the result, checks, limitations, and commit status briefly. Never claim unrun checks, unmeasured behavior, or a clean shared tree without evidence.
