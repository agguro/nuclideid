# IAEA isotope CSV audit

The rewritten `fetch_isotopes` successfully downloaded the ground-state CSV
from `https://nds.iaea.org/relnsd/v1/data?fields=ground_states&nuclides=all`.
The response was byte-for-byte identical to the existing project `isotopes.csv`.
The CSV's `Extraction_date` field is `2023-10-18`.

## Structural and value checks

- File size: 900,613 bytes.
- Data records: 3,386; columns: 55 in every nonempty record.
- One trailing blank record (line 3388).
- No duplicate `(z, n)` keys or mismatched atomic numbers and symbols.
- Proton and neutron counts are nonnegative integers.
- Populated numeric fields parse as numbers, apart from the intentional
  half-life markers described below. Text and uncertainty fields were
  treated according to their contents rather than forced into numeric types.
- Populated abundance and decay percentages lie between 0 and 100.
- No negative values in numeric uncertainty columns.
- No literal `,0,.00` sequence or numeric values starting with a decimal point.
- Last entry: Og-294, Z=118, N=176, half-life 0.00058 seconds.

## Cases the binary converter must handle

- Mo-82 at CSV line 1041 has `half_life=?` and empty `half_life_sec`.
- 244 records have `half_life=STABLE` and empty seconds.
- 178 records have an empty `half_life`.
- In total, 423 records have empty `half_life_sec`; every populated value
  in that column is positive.
- 250 half-life uncertainties use asymmetric notation such as `+94-6`.
- Half-life qualifiers: LT=39, AP=13, GT=99, GE=15.
- Half-life units include eV, keV and MeV; use the supplied
  `half_life_sec` rather than assuming every original value is a time.
- Empty CSV fields must retain their column positions and must not silently
  become measured zeros. Scientific notation must be supported.

These checks establish structural consistency and selected value constraints,
not independent scientific validation of every measurement.

## Downloader verification

Debug and release builds passed. Controlled libcurl simulations exercised
successful publication, interrupted transfers, invalid CSV, a header without
rows, rejected redirects, invalid arguments, and a missing output directory.
Failure cases preserved the existing destination and removed temporary files.
A real IAEA HTTPS download also succeeded and was parsed with Python's CSV reader.
