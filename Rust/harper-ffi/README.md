# harper-ffi

A minimal C ABI over `harper-core` (Apache-2.0). The Swift package
`Packages/L1-Adapters/GrammarHarper` consumes it as a binary target.

## Build

```sh
make harper
```

This runs `cargo build --release` and packages
`Rust/harper-ffi/HarperFFI.xcframework` with `xcodebuild -create-xcframework`.
The resulting framework is a static library for the host architecture; the
Swift package links it only when the directory exists.

Offline path: `cargo build --release --offline` works when the registry cache is
populated (it is in this workspace). The Swift package still builds and tests
without the framework by compiling the stub target in
`Packages/L1-Adapters/GrammarHarper/Sources/HarperFFIStub`; the stub reports
`harper_linter_is_stub() == 1`, so the adapter reports Harper as unavailable
instead of silently pretending to lint.

## C ABI

| Symbol | Meaning |
|---|---|
| `harper_linter_create(dialect)` | Allocate a linter (`american`, `british`, `canadian`, `australian`, `indian`). |
| `harper_linter_add_word(linter, word)` | Add a custom dictionary word. |
| `harper_linter_lint(linter, text, byte_len, &lints, &count)` | Lint a UTF-8 buffer. Returns 0, -1 (null argument) or -2 (invalid UTF-8). |
| `harper_lints_free(lints, count)` | Release the array and all strings it owns. |
| `harper_linter_free(linter)` | Release a linter. |
| `harper_linter_is_stub()` | 0 for the real backend, 1 for the Swift stub. |

`start` and `length` are **UTF-16 code units**, not bytes and not Unicode
scalars. Tests in `src/lib.rs` pin emoji (two UTF-16 units) and CJK (one unit
per scalar) behaviour.

`has_suggestion == 1` means the caller may apply `suggestion`; an empty string
is a removal. `has_suggestion == 0` means the lint is advisory only.

## Tests

```sh
cd Rust/harper-ffi && cargo test --release --offline
```
