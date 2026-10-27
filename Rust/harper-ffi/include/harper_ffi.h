#ifndef HARPER_FFI_H
#define HARPER_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Offset contract: `start` and `length` are UTF-16 code units, matching
 * NSRange / String.utf16 on the Swift side. `byte_len` passed to
 * harper_linter_lint is the length of the UTF-8 buffer in bytes.
 *
 * Ownership: the array returned by harper_linter_lint owns every non-null
 * string it contains. Release the array with harper_lints_free(lints, count).
 */
typedef struct {
    int32_t start;
    int32_t length;
    const char *kind;
    const char *message;
    const char *suggestion;
    /* 1 when a suggestion exists (an empty string means "remove the span"). */
    int32_t has_suggestion;
} HarperLintC;

typedef struct HarperLinter HarperLinter;

HarperLinter *harper_linter_create(const char *dialect);
void harper_linter_free(HarperLinter *linter);
void harper_linter_add_word(HarperLinter *linter, const char *word);

/*
 * Returns 0 on success, -1 for a null argument, -2 for invalid UTF-8.
 * On success *out_lints and *out_count are always written.
 */
int harper_linter_lint(HarperLinter *linter, const char *text, int32_t byte_len,
                       HarperLintC **out_lints, int32_t *out_count);
void harper_lints_free(HarperLintC *lints, int32_t count);

/* 0 for the real Harper backend, 1 for the Swift-side stub target. */
int32_t harper_linter_is_stub(void);

#ifdef __cplusplus
}
#endif

#endif
