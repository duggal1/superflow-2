#!/usr/bin/env bash
# R20: no regression — build, lint, focused tests green (except documented stale test).
# Delegates to integrity-tests.sh, the explicit real-exercise + test-integrity gate:
# frozen tests restored byte-for-byte, no deleted/weakened test vs HEAD, lint clean,
# release build, six focused XCTest suites. Run `checks/integrity-tests.sh` standalone.
exec bash "$(dirname "$0")/integrity-tests.sh"
