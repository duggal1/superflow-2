#!/usr/bin/env bash
# R4: one token set (Tokens.swift) before any view; no magic numbers elsewhere.
# PASS requires the token set AND a clean run of the real lint-forbidden rule.
source "$(dirname "$0")/_lib.sh"
tokens=$(find "$ROOT/Packages" "$ROOT/App" -name 'Tokens.swift' 2>/dev/null | grep -v '/.build/' | head -5)
if [ -z "$tokens" ]; then
  fail "no Tokens.swift found in Packages/ or App/"
fi
tfirst=$(printf '%s' "$tokens" | head -1)

lintlog="$PROOF/logs/check-04-lint.log"; mkdir -p "$PROOF/logs"
timeout 200 tools/lint-forbidden >"$lintlog" 2>&1; lr=$?
fontviol=$(grep -cE '\.font\(\.system\(size:' "$lintlog" 2>/dev/null | tr -d ' ')

if [ "$lr" -eq 0 ]; then
  pass "token set=${tfirst#$ROOT/}; EXERCISED tools/lint-forbidden -> rc=0 (no forbidden raw-control/font patterns); magic-number enforcement is the same lint rule"
else
  fail "token set=${tfirst#$ROOT/}; EXERCISED tools/lint-forbidden -> rc=$lr (raw .font(.system(size:) findings=$fontviol). See $lintlog"
fi
