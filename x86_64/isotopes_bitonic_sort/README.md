# SQLite catalog loader (formerly GPU bitonic sorter)

The command name `isotopes_bitonic_sort` is retained for the recursive build.
Its new job is to load sorted isotope candidates from SQLite into host memory.
It does not read or generate `isotopes.bin`, modify the database, pad records,
initialize CUDA, or sort on the GPU. The old host source, Makefiles, and PTX
are backed up alongside the corresponding files. The old kernel is retired
from the build and retained for reference.

## Build and inspect

Requires GNU binutils, libc, and libsqlite3-dev (the same dependencies as the
SQLite importer). No CUDA toolkit or NVIDIA driver is required for this stage.

```sh
make -C x86_64/isotopes_bitonic_sort debug
make -C x86_64/isotopes_bitonic_sort release
make -C x86_64/isotopes_bitonic_sort MODE=debug test
./release/bin/x86_64/isotopes_bitonic_sort/isotopes_bitonic_sort
./release/bin/x86_64/isotopes_bitonic_sort/isotopes_bitonic_sort other.sqlite3 --list
```

The default path is `isotopes.sqlite3`. `--list` prints the actual loaded buffer
as tab-separated text with 17-digit floating-point formatting. `--help` prints
usage. `-o` is no longer supported because there is no output database file.
Exit status is 0 on success, 1 on error. Missing databases are never created.
A database with no measured candidates is an explicit error.

## Selection and memory layout

One read-only SQLite query provides a consistent snapshot:

```sql
SELECT z,n,a,symbol,half_life_seconds,decay_constant
FROM nuclides
WHERE status='measured'
ORDER BY decay_constant,z,n;
```

Stable, unknown, and qualified half-lives are excluded. Qualified measurements
need an explicit treatment of bounds and approximation in a future inference
policy. Ties are ordered by atomic number and neutron count. The loader checks
SQLite column types, isotope identity, symbol, positive finite seconds and k,
consistency of `k=ln(2)/seconds` (relative tolerance 1e-12), and ascending k.

Each record occupies 64 bytes, described by `x86_64/include/isotope_catalog.inc`
and the C-compatible header `x86_64/include/isotope_catalog.h`:

| Offset | Type | Value |
|---|---|---|
| 0 | uint64 | Z |
| 8 | uint64 | N |
| 16 | uint64 | A |
| 24 | char[8] | NUL-terminated symbol; remaining bytes zero |
| 32 | float64 | half-life in seconds |
| 40 | float64 | decay constant |
| 48 | float64 | same decay constant (sort key) |
| 56 | uint64 | reserved, zero |

There are no dummy records. The buffer can have spare allocation capacity,
but only `catalog.count` records and `catalog.bytes=count*64` bytes are valid.
The current real dataset loads 2,797 candidates, occupying 179,008 valid bytes.
The buffer is ordinary host memory, not pinned or GPU device memory.

## Reuse in inference

`isotope_catalog.s` is the reusable assembly implementation; it has no global
mutable state. Builds also produce `libisotope_catalog.a` and
`libisotope_catalog.so` in the stage's build directory. The standalone CLI
links the object directly and does not need a private shared-library install.

The exported SysV ABI functions are:

```c
struct isotope_catalog catalog = {0};
int result = isotope_catalog_load("isotopes.sqlite3", &catalog);
if (result == ISOTOPE_OK) {
    /* Read catalog.data[0..count), or transfer catalog.bytes to CUDA. */
    isotope_catalog_free(&catalog);
}
```

The descriptor is three 64-bit fields: data pointer, record count, valid bytes.
On a failed load it is unchanged and partial allocations are freed. Loading
into a nonempty descriptor is rejected. `isotope_catalog_free` zeroes the
descriptor and permits repeated calls. SQLite is closed before success returns,
so the caller owns the buffer's lifetime independently of the database.

A CUDA host can allocate `catalog.bytes` on the device and call
`cuMemcpyHtoD_v2(device_ptr, catalog.data, catalog.bytes)` when a kernel actually
needs the catalog. If matching remains on the CPU, no GPU catalog transfer is
necessary. SQLite is always the source of isotope reference data.

The CLI frees its buffer before exiting; it cannot hand a pointer to a separate
process. The inference executable now links this module and calls the loader
in its own process. It fits CSV measurements on the GPU and performs candidate
matching against this host-memory catalog. See the
[inference documentation](../learn_decay/README.md) for the model, tests and
limits. No isotope catalog transfer to the GPU is required for CPU matching.

Tests compare every real candidate with SQLite when `isotopes.sqlite3` exists,
and independently cover filtering, tie ordering, large decay constants, memory
layout, allocation growth, malformed databases, repeated loads/frees, and
read-only behavior. They do not claim to test a CUDA transfer or decay inference.
