# Decay stage validation

Validation performed on 2026-11-05 against the local IAEA SQLite snapshot.
The reference CSV's extraction date is 2023-10-18.

## Completed checks

- Root `make release` succeeds, including both GPU kernels and host programs.
- SQLite importer: 16 integration tests pass.
- SQLite catalog: 15 integration tests pass.
- Decay generation/inference: 27 tests pass with hardware tests enabled in
  both debug and release builds, on NVIDIA GeForce GTX 1060 6GB (compute 6.1).
- All nine `.before-decay.bak` backups match their original Git HEAD files.
- Whitespace checks pass. No generated database, measurements, object files,
  or CUBINs are intended as source changes.

The 27 decay tests include independent Python regression and exponential
oracles; CPU/GPU agreement; k from 1e-25 to 8e21; amplitudes from 1e-100 to
1e100; noise; sample counts below, equal to, and above 256 and a 65,537-point
fit; total decay of 700 exponents; shifted time origin; real SQLite nuclides;
malformed input; stable/growing/poor fits; ambiguous and absent candidates;
read-only source files; injected CUDA initialization and device-copy failures;
and injected file-write failure with preservation of existing measurements.
The generator and fitting test cases also use independent Python-created
measurements so a shared synthetic-data bug is not the only correctness test.

A real SQLite Co-60 test using 257 synthetic measurements recovered
`k=4.166945489506152e-9` and `T_half=166344192` seconds and reported Co-60 as a
candidate at relative tolerance 1e-8. This validates the example's computation
and catalog lookup, not an experimental identification of a physical sample.

## Limits of validation

Compute Sanitizer 2022.3 could not instrument the program in this environment:
it reported termination before the first instrumented CUDA API call. No
sanitizer memory/synchronization success is claimed. The kernels did execute
on actual hardware and pass independent numerical and failure-path checks.

The fit assumes positive single-exponential data and log-space least squares.
It does not handle background, mixtures, zero counts, daughter ingrowth, or
Poisson likelihood, and does not propagate nuclear half-life uncertainties.
Candidates within an explicit k tolerance are not a unique physical isotope
identification. Log RMSE/R-squared thresholds are engineering gates, not
confidence intervals. See the host-stage README files for the exact contracts.

## Real-data follow-up: retained Silver-111 dataset

The original Zenodo archive (DOI 10.5281/zenodo.18310004, CC BY 4.0) is now
retained with its metadata and checksums under `datasets/ag111/`. All 1,082
published peak-list reports were processed without fit-based exclusions.
OR20 (792 points) and OR50 (290 points) were tested separately using live-time
normalized peak rates at acquisition midpoints. CPU, GPU and independent
Python fits agree. Half-lives were 7.4334184840 and 7.4264501115 days; each
series returns Ag-111 as the sole default-tolerance candidate in this catalog.

These approximations do not reproduce the workbook's corrected precision:
they differ from its final 7.423603370544002-day result by 0.0098151 and
0.0028467 days. The workbook quotes uncertainty 0.0011158983577652663 days.
The source audit additionally records 39 differing OR50 peak areas between
workbook and reports plus one abbreviated OR20 filename. Original files are
unchanged; baseline fits consistently use the text reports. Full outputs,
provenance, preparation scripts and regression checks are retained. See
[detailed results and reproduction](../datasets/ag111/README.md).
