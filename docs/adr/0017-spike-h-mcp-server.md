# ADR 0017: Spike H — MCP protocol version, transport and server shape

Status: Accepted; runtime client verification pending

## Context

Addendum A §33 requires a read-only stdio MCP server (`Superflowctl mcp`) with
three tools, no network sockets, an explicit enable toggle and a per-meeting or
per-folder sharing flag. Spike H must read the current specification and record
the protocol version and transport before any code.

The protocol changed materially after the widely deployed 2025 revisions.

## Verified facts

Checked against `modelcontextprotocol.io` on 2026-10-27:

- The current specification version is **2026-07-28** (`schema/2026-07-28`).
- The modern protocol is **stateless**: each request is self-contained and
  carries its protocol version and capabilities in
  `_meta.io.modelcontextprotocol/*`. There is no connection-scoped session and
  no required `initialize` handshake.
- Standard transports are **stdio** and **Streamable HTTP**. Stdio is
  newline-delimited JSON-RPC over the subprocess's `stdin`/`stdout`; messages
  must be UTF-8 and must not contain embedded newlines. The server must write
  nothing to `stdout` except valid MCP messages; logging goes to `stderr`.
- In the modern era the server does not initiate JSON-RPC requests. Server-to-
  client interaction uses `InputRequiredResult` replies.
- Cancellation on stdio is `notifications/cancelled`.
- Shutdown is the client closing the server's `stdin`; the server should exit on
  EOF and may close its output stream to initiate shutdown.
- Backward compatibility with initialization-based revisions is explicit.
  A client probes with `server/discover`; a legacy server answers with an
  unrelated error or not at all, and the client then falls back to `initialize`.
  The fallback must not be keyed to one error code.

## Decision

1. Implement **stdio only**. No TCP, no HTTP, no Unix socket, no listening port.
   The server is launched by the agent and dies with it.
2. Server supports both eras:
   - Modern 2026-07-28 requests with per-request metadata, including
     `server/discover` and `supportedVersions`.
   - Legacy `initialize`-based clients via the documented fallback, because the
     installed base of coding agents will lag the spec.
   In the modern era the server validates the version carried in each request;
   legacy sessions pin the version from `initialize`.
3. Tools only. No resources, prompts, subscriptions, sampling or elicitation.
   - `list_meetings`
   - `get_meeting` (id, format, budget)
   - `search_transcripts`
   Every tool is read-only and has a closed input schema. There is no mutation,
   no arbitrary path read and no SQL exposure.
4. Database access goes through `MeetingRepository`, opened with SQLite
   read-only. The MCP process never writes, migrates or vacuums the database.
   Search uses the existing FTS5 index over edited-else-clean text.
5. Gating is enforced outside the protocol:
   - Global enable toggle, default off.
   - Per-meeting or per-folder `sharedWithAgents` flag, default off.
   - A meeting that is not shared is invisible to `list_meetings`, `get_meeting`
     and `search_transcripts`.
   - Settings shows an audit log of accessed meeting IDs only, never content.
6. Output is deterministic and reuses `MeetingExport`. Budget enforcement uses
   the same conservative estimator as the UI. No `now` timestamp is inserted.
7. `stdout` is reserved for MCP. Diagnostics go to `stderr` without transcript
   text, meeting titles or participant names.

## Alternatives considered

1. Streamable HTTP on localhost. Rejected: the addendum requires no network
   sockets and stdio is sufficient for local agents.
2. Modern-only server. Rejected: current agents mostly speak older revisions;
   a modern-only server would appear broken.
3. Let the CLI query SQLite directly. Rejected: the addendum requires the
   repository port, and raw SQL in two places will drift.

## Consequences and limits

- Two protocol eras are a real maintenance cost and need tests for both.
- The read-only connection must coexist with the app's WAL writer; concurrent
  reads and `-wal`/`-shm` handling need a spike assertion.
- The audit log is a new table or append-only file; decide when the feature is
  built, not now.

## Unverified / next evidence

- [ ] Which of Claude Code, Cursor, Codex and other target agents support
      2026-07-28, and which still require `initialize`.
- [ ] Exact `tools/list` and `tools/call` result shapes in the 2026-07-28
      schema (read `schema.md` before writing handlers).
- [ ] Whether the selected clients probe `server/discover` or go straight to
      `initialize`.
- [ ] Read-only SQLite against a live WAL database under concurrent app writes.
- [ ] A real agent reading a shared meeting through the server.

## Evidence

- https://modelcontextprotocol.io/specification/latest (2026-07-28)
- https://modelcontextprotocol.io/specification/2026-07-28/basic/transports.md
- https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio.md
- Addendum A §33 and §34
