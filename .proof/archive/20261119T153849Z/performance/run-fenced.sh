#!/usr/bin/env bash
# Agent 6 build fence wrapper. Acquire the shared /tmp lock, release on any exit.
# Usage: .proof/performance/run-fenced.sh <logfile> <command...>
set -uo pipefail
log="$1"; shift
lock=/tmp/superflow-build-lock
acquired=0
for attempt in 1 2 3; do
  if mkdir "$lock" 2>/dev/null; then acquired=1; break; fi
  echo "FENCE BUSY (attempt $attempt/3), waiting 20s" >&2
  sleep 20
done
if [[ $acquired -ne 1 ]]; then
  echo "FENCE NOT RUN: lock held after 3 retries" | tee "$log" >&2
  exit 75
fi
cleanup() { rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
echo "FENCE ACQUIRED: $*" >&2
set +e
timeout 300 "$@" >"$log" 2>&1
rc=$?
set -e
echo "FENCE RELEASED rc=$rc log=$log" >&2
exit $rc
