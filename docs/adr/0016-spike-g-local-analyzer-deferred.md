# ADR 0016: Spike G — optional local analyzer deferred

Status: Deferred

## Context

Addendum A allows a spike for an optional `MeetingAnalyzer` backed by a larger
local model. It must be off by default, must never sit in the recording path, and
would need an ADR before any code ships. Built-in summaries remain a v1 non-goal;
S1-mini is a 0.6B cleanup model and must not be asked to summarize.

## Decision

Skip Spike G in v1.

- No `MeetingAnalyzer` port, no analyzer package and no model download.
- No summary box, chat panel or generated chapter title.
- Chapter titles stay extractive: top TF-IDF keyphrases against the user's own
  history (ADR 0019).
- If this is revisited, it starts as a throwaway spike with a new ADR covering
  model choice, memory ceiling, thermal behaviour, hallucination measurement and
  the guarantee that a failure returns the plain transcript.

## Alternatives considered

1. Build the port now with a fake and leave the adapter unwritten. Rejected: an
   unused port plus a fake plus a contract suite is cost with no evidence, and it
   invites accidental use in the recording path.
2. Use S1-mini for summaries. Rejected: wrong task for a 0.6B cleanup model and
   explicitly outside its remit.

## Consequences and limits

- Meeting output is deterministic structure plus user-authored agent prompts.
- The addendum's definition of done does not require G.

## Evidence

- Addendum A §27 and §36
- `PLAN.md` §1 non-goals and §10 model description
