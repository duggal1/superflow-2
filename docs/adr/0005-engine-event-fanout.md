# ADR 0005: Fan out engine events at the app boundary

**Status:** Accepted

## Decision

The app consumes each engine's `AsyncStream` once and republishes values through `EngineEventRelay` to independent menu, Island, and feature subscribers.

## Context

Session and meeting state is displayed in multiple UI surfaces. Reading the same engine stream from each surface would make consumers compete for events instead of receiving a broadcast.

## Consequences

The L5 coordinator owns the source stream and subscriber lifetime. Each UI surface receives a separately buffered stream and can start observing without depending on another surface's iterator.
