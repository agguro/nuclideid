# SQLite isotope importer

`create_isotopes_db.s` is a standalone GNU x86-64 assembly importer. It replaces
this stage's custom `isotopes.bin` writer with `isotopes.sqlite3`.

## Dependencies and build

Debian/Ubuntu packages: `binutils`, `libc6-dev`, `libsqlite3-dev`; `sqlite3` is
useful for inspection. SQLite 3.37 or later is required for STRICT tables.
There is no CUDA or OpenSSL dependency for this stage.

```sh
sudo apt-get install libsqlite3-dev sqlite3
make -C x86_64/create_isotopes_db debug
make -C x86_64/create_isotopes_db release
make -C x86_64/create_isotopes_db MODE=debug test
```

Integration tests use Python's standard library and isolated temporary files.
If the project's `isotopes.csv` exists, tests also compare every real CSV record
against the imported SQLite values.

## Run

From the project root:

```sh
./release/bin/x86_64/create_isotopes_db/create_isotopes_db
# Or supply input and destination paths:
./release/bin/x86_64/create_isotopes_db/create_isotopes_db input.csv output.sqlite3
```

Defaults are `isotopes.csv` and `isotopes.sqlite3` in the current directory.
`--help` prints usage. Exit status is 0 on success, 1 on failure. Errors report
the CSV line number; SQLite failures additionally report SQLite's diagnostic.

The importer checks the exact IAEA 55-column header, row widths, required
identity fields, matching atomic number/symbol, ordinary numeric fields,
percentage ranges, nonnegative numeric uncertainties, half-life qualifiers,
units, and positive finite half-lives/decay constants. It preserves empty
fields, accepts scientific notation, CRLF, and a final row without a newline.
Quoted fields and doubled quotes are supported within a physical line;
multiline quoted fields are rejected. Blank lines are skipped.

The import replaces the contents of the `nuclides` table in one transaction.
A failed import rolls back, retaining the previous data. Duplicate `(z,n)`
identities are errors. An empty/header-only CSV is rejected. A failed first
import may leave an empty SQLite file. Existing incompatible schemas cause an
error and rollback rather than automatic migration. The CSV and SQLite file
must be separate files.

## Data model

The STRICT `nuclides` table contains:

| Column | Meaning |
|---|---|
| `z`, `n`, `a`, `symbol` | Identity; primary key `(z,n)`, `a=z+n` |
| `half_life_seconds` | Positive seconds for measured/qualified records; otherwise NULL |
| `decay_constant` | `ln(2)/half_life_seconds`; 0 for stable, NULL for unknown |
| `status` | `measured`, `qualified`, `stable`, or `unknown` |
| `qualifier` | Original `LT`, `GT`, `GE`, `AP`, or empty string |
| `half_life_raw`, `unit_raw`, `uncertainty_raw` | Original half-life fields |
| `source_line`, `source_csv` | Source line number and full original 55-field CSV record, excluding its line ending |

All source columns remain recoverable by parsing `source_csv` with a CSV reader.
Only the fields needed for nuclide lookup are exposed as separate SQL columns.
Raw half-life values expressed in energy units are retained; the importer uses
the IAEA's supplied seconds column for calculation. It does not independently
recalculate unit conversions or scientifically validate source measurements.

Stable is recognized from the original `half_life=STABLE` marker. Empty or `?`
half-lives are unknown. Conflicting markers and seconds values are rejected.
Missing values never silently become measured zeros. Asymmetric uncertainties
such as `+94-6` are retained as text.

```sh
sqlite3 isotopes.sqlite3 "SELECT status,count(*) FROM nuclides GROUP BY status;"
sqlite3 isotopes.sqlite3 "SELECT * FROM nuclides WHERE z=118 AND n=176;"
sqlite3 isotopes.sqlite3 "PRAGMA integrity_check;"
```

## GPU migration

Sorting has been replaced by a SQLite memory loader. The inference program
now calls that loader directly; no binary isotope database is generated.
SQLite files are queried through SQLite, not mapped as packed GPU records.

The catalog loader now selects suitable rows and builds a packed host-memory
buffer; see [its API documentation](../isotopes_bitonic_sort/README.md).
The inference executable links and calls that loader in its own process.
For an initial set of unqualified measured candidates:

```sql
SELECT z, n, a, symbol, half_life_seconds, decay_constant
FROM nuclides
WHERE status = 'measured'
ORDER BY decay_constant, z, n;
```

Qualified values represent bounds or approximate measurements and require an
explicit matching policy. Stable and unknown records should not enter a fit
that assumes positive exponential decay. Sorting 3,386 database records can be
handled by SQL; GPU work can focus on measurement inference.

Original converter files are preserved as `create_isotopes_db.s.bak` and
`Makefile.bak` beside the rewritten files.
