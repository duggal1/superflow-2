#include "harper_ffi.h"

#include <stdlib.h>

/*
 * Stub backend. It exists so the Swift package builds and tests on a machine
 * where the Rust XCFramework has not been built yet. It never reports a lint.
 */

struct HarperLinter {
    int unused;
};

HarperLinter *harper_linter_create(const char *dialect) {
    (void)dialect;
    HarperLinter *linter = (HarperLinter *)calloc(1, sizeof(HarperLinter));
    return linter;
}

void harper_linter_free(HarperLinter *linter) {
    free(linter);
}

void harper_linter_add_word(HarperLinter *linter, const char *word) {
    (void)linter;
    (void)word;
}

int harper_linter_lint(HarperLinter *linter, const char *text, int32_t byte_len,
                       HarperLintC **out_lints, int32_t *out_count) {
    (void)linter;
    (void)text;
    (void)byte_len;
    if (out_lints == NULL || out_count == NULL) {
        return -1;
    }
    *out_lints = NULL;
    *out_count = 0;
    return 0;
}

void harper_lints_free(HarperLintC *lints, int32_t count) {
    (void)lints;
    (void)count;
}

int32_t harper_linter_is_stub(void) {
    return 1;
}
