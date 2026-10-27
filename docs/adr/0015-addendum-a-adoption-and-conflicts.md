# ADR 0015: Adopt Addendum A and record its conflicts

Status: Accepted

## Context

Addendum A extends `PLAN.md` with meeting structure, export, learning, Code Speak
and the Agent Bridge. It states that it wins over the master plan where the two
disagree, and that every conflict must be recorded here. The repository already
contains parts of the old plan that the addendum reshapes:

- `MeetingEngine` contains `MeetingExport.swift` (`schemaVersion: 1`), so export
  currently lives inside the capture engine.
- There is no `MeetingStructure`, `MeetingExport`, `LearningEngine`,
  `TextCodeSpeak`, `ContextProfiles` or `AgentBridge` package.
- `Ports` has no `MeetingDetector`, `CalendarProvider`, `MeetingRepository`,
  `CorrectionRepository`, `ExportSink` or `ProfileProvider`.
- `DESIGN.md` says "SF Symbols only". The addendum (§37) says Hugeicons "per
  section 18" of `PLAN.md`, which also says Hugeicons only. The repo currently
  uses Hugeicons in the sidebar and SF Symbols in system menus.

No product code is written by this ADR. It exists so the Phase 0b gate is
auditable and so the package split is fixed before adapters are added.

## Decision

### 1. Precedence

1. Addendum A (sections 26–38) wins over `PLAN.md`.
2. `DESIGN.md` remains the visual source of truth for layout, colour, type,
   spacing, motion and native controls.
3. Where Addendum A and `DESIGN.md` disagree, stop and ask the owner. Do not
   mass-migrate icons or controls on the strength of one clause.

The Hugeicons/SF Symbols conflict is therefore an owner question, not a licence
to rewrite the UI. Until it is answered, new work uses the existing icon wrapper
and does not introduce a second icon set.

### 2. Phase order

Implement in the order in section 36 of the addendum:

- Phase 0b: spikes G–J and their ADRs (this ADR set; G is deferred).
- Phase 3b: `TextPipeline` explain mode, `TextCodeSpeak`, `ContextProfiles`.
- Phase 4b: `LearningEngine` backend with the replay gate.
- Phase 6b: learning UX, provenance, re-run.
- Phase 7a: meeting capture hardening.
- Phase 7b: `MeetingStructure`, `MeetingExport`, modes and markers.
- Phase 7c: review UX, detection, calendar seeding, voice memory.
- Phase 7d: Agent Bridge.

Phase 0b is not complete until the runtime parts of spikes H, I and J have
evidence. API existence alone is not quality or device evidence.

### 3. Module boundaries to land before Phase 7b

- Extract export from `SuperflowMeetingEngine` into a new L2 `MeetingExport`
  package. `MeetingEngine` capture code must not import it.
- Add `MeetingStructure` as a separate L2 package. Capture code must not import
  it either.
- Add an explicit `check-deps` rule: `SessionEngine` and the meeting capture
  modules never depend on `MeetingStructure`, `MeetingExport`,
  `LearningEngine` or `AgentBridge`.
- `MeetingDocument` stays a derived, rebuildable value. SQLite segments,
  markers and speakers remain the source of truth.
- Ports and their fakes/contract suites are added together, per ADR 0010.

The current `MeetingEngine.MeetingExport` is a known deviation. It may stay
until Phase 7b, but no new capture code may call it.

### 4. Non-negotiables adopted now

- Raw ASR text, per-stage text and the audio journal are immutable. User edits
  go to `edited_text` plus `edit_revision` with provenance.
- Every new text transformation is deterministic, idempotent and property
  tested. Learning never rewrites raw text in place.
- A failed structure, export, learning or profile step returns the plain
  transcript plus a diagnostic. It never throws into the UI.
- No transcript text in logs. Agent Bridge, voiceprints and auto-activation of
  learned rules are off by default.
- The built-in AI summary remains a non-goal. "No model generates transcript
  content" means no new content and no summaries; the existing S1-mini cleanup
  stage is still allowed to clean wording.
- Meeting journals are retained for 7 days by default, replacing the master
  plan's delete-after-commit default. This is an owner question.
- Every feature ships with keyboard path, empty state, error state and undo.

### 5. Schema direction

New tables, per section 34: `markers`, `participants`, `gaps`,
`meeting_derived`, `speaker_voiceprints` (opt-in), `correction_events`,
`rule_candidates`, `rule_applications`, `rulesets`, `profiles`,
`export_presets`, plus `segments.edited_text` and `segments.edit_revision`.
Every migration is tested forward from fixtures with a backup first. The export
JSON schema moves to version 2; version 1 output stays readable.

## Alternatives considered

1. Implement the addendum directly in `MeetingEngine` and split later. Rejected:
   it would put structure and export on the recording path and make the
   isolation rule untestable.
2. Treat `DESIGN.md` as overriding the addendum on icons. Rejected as a silent
   decision: the documents genuinely conflict and the owner must choose.
3. Start with Phase 3b while Phase 0b evidence is incomplete. Rejected: the
   addendum makes the ADRs a hard gate.

## Consequences and limits

- Phase 7b grows by one package extraction and one dependency-check rule.
- The current export schema and API will move; callers must be updated in the
  same change.
- Runtime evidence for detection, calendar, MCP and voiceprints is still
  missing. See ADRs 0016–0019.

## Evidence

- `Packages/L2-Engines/MeetingEngine/Sources/SuperflowMeetingEngine/MeetingExport.swift`
- `Packages/L0-Core/Ports/Sources/SuperflowPorts/`
- `docs/STATUS.md`, `TODO.md`, `DESIGN.md` §7 and §18
- Addendum A §26–§38
