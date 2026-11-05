#ifndef NUCLIDEID_ISOTOPE_CATALOG_H
#define NUCLIDEID_ISOTOPE_CATALOG_H
#include <stddef.h>
#include <stdint.h>

/* Measured candidates only. SQL sorts by (decay_constant, z, n).
 * No padding records. Symbol is NUL-terminated; reserved is zero.
 * Buffer belongs to the caller until isotope_catalog_free().
 * Ordinary host memory: copy data/bytes to CUDA device memory if needed.
 */
struct isotope_record {
    uint64_t z, n, a;
    char symbol[8];
    double half_life_seconds, decay_constant, sort_key;
    uint64_t reserved;
};
struct isotope_catalog {
    struct isotope_record *data;
    size_t count, bytes;
};
enum isotope_catalog_result {
    ISOTOPE_OK = 0, ISOTOPE_ARGUMENT = 1, ISOTOPE_SQLITE = 2,
    ISOTOPE_INVALID_ROW = 3, ISOTOPE_EMPTY = 4, ISOTOPE_MEMORY = 5
};
/* Initialize *out to {0}. On failure *out is unchanged. The input database is
 * opened read-only. Individual calls have no shared mutable state.
 */
int isotope_catalog_load(const char *path, struct isotope_catalog *out);
/* Free host storage, zero the descriptor. NULL and repeated frees are safe. */
void isotope_catalog_free(struct isotope_catalog *catalog);
const char *isotope_catalog_error(int result);
#endif
