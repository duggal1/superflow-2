# ADR 0003: Replace text pipelines through engine updates

**Status:** Accepted

## Decision

The app rebuilds `TextPipeline` when settings, dictionary entries, or shortcuts change, then updates both engines with the new pipeline and settings. Work already processing keeps its captured pipeline; later committed segments use the replacement.

## Context

The text pipeline is assembled from persisted settings and library entries. Rebuilding at the L5 boundary keeps storage and adapter details out of the engines while avoiding partial updates to a live pipeline.

## Consequences

Dictionary, shortcut, settings, and onboarding callbacks all use the same refresh path. The pipeline contents remain a snapshot for each in-flight segment.
