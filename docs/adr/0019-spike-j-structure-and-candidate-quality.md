# ADR 0019: Spike J — structure and candidate quality, and the missing corpus

Status: Accepted; quality evidence blocked

## Context

Addendum A §28.3 requires deterministic chaptering (hard boundaries at markers
and silences over 90 s, then TextTiling, minimum chapter 3 minutes, equal-slice
fallback) and table-driven candidate detection with a hard quality bar: any rule
under 80 percent precision ships disabled. Spike J must test both on real
meeting transcripts before the structure engine is trusted.

## What exists

- `Tests/Golden/Tests/GoldenTests/Fixtures/meeting-export/cases.json` contains
  one hand-written 45-minute, two-speaker, three-turn document used for export
  goldens.
- `Tests/Fixtures` contains only a README; there is no real meeting audio with
  aligned transcripts, no diarized ground truth and no candidate labels.
- There are unit tests for turn assembly and export, but they use constructed
  turns, not recorded conversation.

Therefore the two measurements Spike J needs — chapter boundary agreement and
candidate-rule precision — cannot be produced from this repository. Any number
invented now would be a guess, which rule 2 forbids.

## Decision

1. Build `MeetingStructure` as a deterministic engine with conservative
   defaults, but do not claim chapter or candidate quality until measured.
2. Candidate rules live in JSON with an explicit `enabledByDefault` flag and a
   measured `precision` field. Every rule ships disabled. A rule is enabled only
   after a corpus run shows at least 80 percent precision and the result is
   recorded in the fixture set.
3. Chaptering order is fixed:
   - hard boundary at every marker;
   - hard boundary at silences over 90 s;
   - TextTiling inside each region;
   - minimum chapter 3 minutes;
   - equal time slices when no signal exists.
   Titles are extractive top TF-IDF keyphrases against the user's own history.
   Never a generated sentence, never a model call.
4. If structure fails, times out or produces invalid chapters, the transcript is
   returned unchanged with a diagnostic. The UI shows the plain view.
5. Derived data is cached in `meeting_derived` keyed by session id,
   `derivationVersion` and `edit_revision`. A rebuild never mutates raw text.
6. Candidate detection reports spans linked to a source turn. The UI label is
   "Detected". There is no confidence theatre and no summary box.
7. Talking statistics are integers only: talk time per speaker, longest
   monologue, question count, interruption count. No scores, no rankings.

## Corpus plan (required to exit the spike)

- Collect a small, consented set of real meetings that cover: two-person call,
  four-person call, overlap, echo, a long monologue, decisions and action items.
- Keep audio and transcripts out of git. Store them in a local, git-ignored
  fixture directory or an encrypted local volume. Only derived, non-identifying
  annotations may become repo fixtures.
- Label chapter boundaries and action/decision/question spans by hand.
- Measure per rule: true positives, false positives, unexplained fires. Record
  the table in the Phase 7b exit evidence.
- Repeat on a 3-hour generated meeting for the rebuild budget, not for quality.

Until this exists, Phase 7b may ship the engine and the UI, but candidate rules
stay off and chapters are labelled as heuristic.

## Alternatives considered

1. Tune TextTiling on the single export fixture. Rejected: three turns is not a
   meeting and would overfit.
2. Enable rules that "look safe" without measurement. Rejected by the 80 percent
   rule and by the addendum's precision requirement.
3. Generate synthetic meetings with a model and label them. Rejected: synthetic
   dialogue does not reproduce ASR errors, backchannels or overlap, so precision
   would be meaningless.

## Consequences and limits

- The structure engine can be implemented and property tested now; its quality
  claims wait for the corpus.
- The UI must work with zero enabled candidate rules.
- Reviewers must not treat chapter titles as facts; they are keyphrases.

## Unverified / next evidence

- [ ] TextTiling parameters for conversational speech (block size, smoothing).
- [ ] Boundary agreement against hand labels.
- [ ] Candidate-rule precision per rule, per mode.
- [ ] Backchannel folding threshold and turn-cap behaviour on real overlap.
- [ ] 3-hour rebuild under 2 s and first paint under 300 ms.
- [ ] A real 60-minute Meet call and a real Zoom call.

## Evidence

- Addendum A §28.3, §35, §36 (Phase 7b)
- `Tests/Golden/Tests/GoldenTests/Fixtures/meeting-export/cases.json`
- `Tests/Fixtures/README.md`
