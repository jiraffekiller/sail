#ifndef CSMC_H
#define CSMC_H
#include <stdbool.h>

/// Read a 4-byte SMC key of type `flt ` (IEEE float). Returns false if the key is
/// missing, unreadable or of a different type. Safe to call from one thread.
bool csmc_read_float(const char *key, float *out);

/// Read a one-byte unsigned SMC key (`ui8 `).
bool csmc_read_u8(const char *key, unsigned char *out);

#endif
