# Formatting guard completion

Root cause: whitespace formatting bypasses the word-preservation guard and has no revert counter.

- Guard whitespace changes and record rejected whitespace formatting.
- Verify formatter and pipeline regression tests; leave performance tuning gated on real measurements.
