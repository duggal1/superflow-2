#ifndef HARPER_FFI_H
#define HARPER_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Stub ABI with the same shape as Rust/harper-ffi/include/harper_ffi.h.
 *
 * This target is compiled only when Rust/harper-ffi/HarperFFI.xcframework is
 * absent (or SUPERFLOW_HARPER_FFI=0). Every lint call returns zero lints and
 * harper_linter_is_stub() returns 1, so the adapter reports Harper as
 * unavailable instead of pretending grammar checking ran.
 *
 * Offsets, when a real backend is used, are UTF-16 code units.
 */
typedef struct {
    int32_t start;
    int32_t length;
    const char *kind;
    const char *message;
    const char *suggestion;
    int32_t has_suggestion;
} HarperLintC;

typedef struct HarperLinter HarperLinter;

HarperLinter *harper_linter_create(const char *dialect);
void harper_linter_free(HarperLinter *linter);
void harper_linter_add_word(HarperLinter *linter, const char *word);
int harper_linter_lint(HarperLinter *linter, const char *text, int32_t byte_len,
                       HarperLintC **out_lints, int32_t *out_count);
void harper_lints_free(HarperLintC *lints, int32_t count);
int32_t harper_linter_is_stub(void);

#ifdef __cplusplus
}
#endif

#endif
