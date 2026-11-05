# nuclideid — isotope data ingestion and decay inference prototype

The host tools use GNU x86-64 assembly (AT&T syntax). Isotope reference data is
now stored in SQLite and selected into memory; the older decay-generation and
inference components use NVIDIA PTX and are still being reviewed.

## Current data pipeline

```text
IAEA HTTPS API
    -> fetch_isotopes
    -> isotopes.csv
    -> create_isotopes_db
    -> isotopes.sqlite3
    -> isotope_catalog_load (SQL selection and ordering)
    -> sorted records in host memory
```

The active ingestion/catalog path does not generate an isotope `.bin` file.
SQLite is the authoritative isotope database. A GPU consumer can copy the
memory buffer directly to device memory when needed.

| Component | Current behavior |
|---|---|
| `fetch_isotopes` | Verified HTTPS via libcurl; validates the response and replaces the CSV after success |
| `create_isotopes_db` | Validates the IAEA CSV and imports into SQLite in one transaction |
| `isotopes_bitonic_sort` | Historical name for the new read-only SQLite catalog inspector and reusable memory loader |
| `create_decay_data` | Older GPU prototype that generates synthetic measurements; not yet reviewed |
| `learn_decay` | Older inference prototype; still requires migration from its obsolete isotope binary layout and numerical review |

**The complete identification pipeline is not yet validated.** The current
`learn_decay` cannot consume the new catalog until it links the loader and
uses its record layout and dynamic count. Running the catalog inspector alone
does not pass memory to a different executable.

## Build the reviewed stages

On Debian/Ubuntu, development dependencies include GNU binutils, libc,
`libcurl4-openssl-dev`, and `libsqlite3-dev` (SQLite 3.37 or newer). Python 3 with
SQLite support runs the integration tests. The `sqlite3` CLI is optional.

```sh
make -C x86_64/fetch_isotopes MODE=release release
make -C x86_64/create_isotopes_db release
make -C x86_64/isotopes_bitonic_sort release

./release/bin/x86_64/fetch_isotopes/fetch_isotopes
./release/bin/x86_64/create_isotopes_db/create_isotopes_db
./release/bin/x86_64/isotopes_bitonic_sort/isotopes_bitonic_sort
```

These stages run without CUDA. The root recursive build also includes the
older GPU measurement generator, which still requires the CUDA toolchain.
The bitonic-sort kernel has been retired from the build.

```sh
make -C x86_64/create_isotopes_db MODE=release test
make -C x86_64/isotopes_bitonic_sort MODE=release test
```

See the [SQLite importer documentation](x86_64/create_isotopes_db/README.md),
[catalog API and memory layout](x86_64/isotopes_bitonic_sort/README.md), and
[CSV audit](docs/isotope-csv-audit.md). Original files are retained as backups;
`README.md.before-sqlite-catalog.bak` preserves the documentation preceding
this catalog migration.

License: Apache-2.0; see [LICENSE](LICENSE).
