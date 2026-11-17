#!/usr/bin/env bash
# Shared helpers for validate-headless checks. Source this from a check script.
# Contract for every check-NN.sh:
#   - print exactly one line:  <STATUS>\t<evidence>
#     where STATUS is PASS | FAIL | UNVERIFIED
#   - exit 0 for PASS, 1 for FAIL, 2 for UNVERIFIED
#   - never open a GUI. Native apps only via `open -g -j`.

set -uo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# checks/ -> validate-headless/ -> tools/ -> repo root
export ROOT="$(cd "$_LIB_DIR/../../.." && pwd)"
export PROOF="$ROOT/.proof/validation"

# --- verdict helpers -------------------------------------------------------
pass()       { _emit PASS "$*"; }
fail()       { _emit FAIL "$*"; }
unverified() { _emit UNVERIFIED "$*"; }

_emit() {
  local status="$1"; shift
  local evidence="$*"
  evidence="${evidence//$'\t'/ }"          # tabs are the field separator
  evidence="${evidence//$'\r'/ }"
  evidence=$(printf '%s' "$evidence" | tr '\n' ' ' | tr -s ' ')
  printf '%s\t%s\n' "$status" "$evidence"
  case "$status" in
    PASS) exit 0 ;;
    FAIL) exit 1 ;;
    *)    exit 2 ;;
  esac
}

# --- evidence helpers ------------------------------------------------------
# Run a command, echo "$ <cmd>\n<output>" truncating to a bounded string.
# Uses a 120s timeout wrapper when available so nothing hangs the harness.
run() {
  local out rc
  out="$(timeout 120 bash -c "$(printf '%q ' "$@")" 2>&1)" || rc=$?
  rc=${rc:-0}
  out="${out//$'\t'/ }"
  out=$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ' | cut -c1-240)
  printf '$ %s -> [rc=%s] %s' "$*" "$rc" "$out"
}

# --- real-exercise helpers -------------------------------------------------
# A source grep is NOT proof the real thing was exercised. These helpers let a
# check actually RUN the relevant XCTest suite and require that at least one
# test executed with zero failures. A filter that matches nothing cannot pass.
#   ex=$(test_exercise <pkg-rel-path> <swift-test-filter> <label>) \
#     && pass "..." || fail "..."
test_exercise() {
  local pkg="$1" filter="$2" label="$3"
  local log="$PROOF/logs/exercise-$label.log"
  mkdir -p "$PROOF/logs"
  timeout 220 swift test --package-path "$ROOT/$pkg" --filter "$filter" >"$log" 2>&1
  local rc=$?
  local n f
  n=$(grep -Eo 'Executed [0-9]+ test' "$log" | grep -Eo '[0-9]+' | tail -1); n=${n:-0}
  f=$(grep -Eo 'with [0-9]+ failure' "$log" | grep -Eo '[0-9]+' | tail -1); f=${f:-0}
  printf 'rc=%s executed=%s failures=%s log=exercise-%s.log' "$rc" "$n" "$f" "$label"
  [ "$rc" -eq 0 ] && [ "$n" -gt 0 ] && [ "$f" -eq 0 ]
}

# Grep-only observations are downgraded to UNVERIFIED: they cannot PASS on
# source evidence alone. The evidence string keeps the grep counts for triage.
source_only() { _emit UNVERIFIED "SOURCE-ONLY (not exercised; cannot PASS): $*"; }

# Short snippet of a command's output (no $ prefix).
snip() {
  local out
  out="$("$@" 2>&1)" || true
  out="${out//$'\t'/ }"
  printf '%s' "$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ' | cut -c1-200)"
}

# True when a regular file exists (echo yes/no).
file_yesno() { [ -f "$1" ] && echo yes || echo no; }
dir_yesno()  { [ -d "$1" ] && echo yes || echo no; }

# Count matching lines: grep_count PATTERN PATH [extra grep flags...]
grep_count() {
  local pat="$1" path="$2"; shift 2
  [ -f "$path" ] || { echo 0; return; }
  grep -E "$@" -c -- "$pat" "$path" 2>/dev/null | head -1 || echo 0
}

# Aggregate a list of "label=yes|no" tokens into a compact evidence string.
join_ev() { local IFS='; '; printf '%s' "$*"; }
