# Real Silver-111 measurements: retained source and validation

This directory retains the original research download and the preparation,
audit, and CPU/GPU results used to test `learn_decay` on real measurements.
The archive is intentionally included despite the repository's general ZIP
ignore rule. The derived CSV files are also explicitly included.

## Source and attribution

- Dataset: **Dataset for: A new low uncertainty measurement of the 111Ag half-life**.
- Depositor: Giancarlo D'Agostino, with Matthieu Guyon, Andrea Gandini,
  Giorgio Grosso, and Marco Di Luzio credited for the associated study.
- Dataset DOI: [10.5281/zenodo.18310004](https://doi.org/10.5281/zenodo.18310004).
- Associated article DOI: [10.1016/j.apradiso.2026.112786](https://doi.org/10.1016/j.apradiso.2026.112786).
- [Original file](https://zenodo.org/records/18310004/files/111Ag_half_life.zip).
- Downloaded and tested on 2026-11-05; Zenodo record version 1, published 2026-07-03.
- Dataset license: **CC BY 4.0**, as recorded in `zenodo-record.json`.
  The research data retains that license; the project's Apache license does
  not replace it. The source archive is unmodified. Derived data and analysis
  are identified below as project-generated adaptations.

`111Ag_half_life.zip` is 11,317,060 bytes. Its MD5 matches Zenodo:

```text
MD5:    760fa6811cc571f2b568089a0139b17a
SHA256: b8752cd29dd48e6401bd0f53c753f18810d105c37d5c3fd7b7fc468eb90533e7
```

The archive contains gamma spectra, 1,082 HyperLab peak-list reports, and an
Excel analysis workbook. No macros, formulas, or original analysis programs
were executed. We read report text and cached workbook values only.

## Primary measurement preparation

`prepare.py` uses Python's standard library and verifies both archive hashes.
For every peak-list report it selects the unique peak within 1 keV of
342.1 keV and validates the numeric fields, measurement times, and durations.
All 1,082 reports are retained, without outlier removal or selection based on
fit quality: OR20 has 792 measurements, OR50 has 290. They are fit separately
because detector efficiencies/amplitudes differ.

For each detector:

```text
t = acquisition midpoint - first acquisition midpoint, in seconds
y = HyperLab fitted net photopeak area / detector live time, in counts/second
```

Start times are the instrument's local timestamps; no timezone is specified
by these reports. Elapsed times use those timestamps consistently. Midpoints
use the recorded true acquisition duration. Counts alone are unsuitable:
acquisition durations vary considerably, often keeping total counts near a
target value even while the source decays.

No published fitted half-life or instrument pile-up parameter enters this
primary preparation. No pile-up, detector drift, exact finite-window decay,
or further gamma-peak-fitting correction is applied. The photopeak areas
already reflect the researchers' spectral peak fitting; these are not a new
analysis of the archived raw spectrum channels. Midpoint/live-time rates are
a documented approximation, especially when dead time changes within a run.
The retained audit CSV includes durations, uncertainties and source members.

Project-generated files:

- `derived/or20.csv`, `derived/or50.csv`: two-column fitter inputs, 17-digit precision.
- `derived/measurements.csv`: all source values and provenance used in preparation.
- `derived/preparation.json`: checksums, ranges, counts, method and independent Python fits.
- `workbook-reference.json`: cached workbook results and a complete discrepancy audit.
- `results/`: verbatim CPU/GPU outputs and a machine-readable comparison report.

## Actual results

The release assembly executable was run against the real SQLite isotope
catalog on the CPU and NVIDIA GeForce GTX 1060 6GB GPU. Neither program nor
catalog was modified to accommodate the dataset. Both runs used the default
1% decay-constant tolerance and default fit quality gates.

| Series | Measurements | Span (days) | Fitted half-life (days) | Log RMSE | R-squared |
|---|---:|---:|---:|---:|---:|
| OR20 | 792 | 31.43109 | 7.4334184840 | 0.00121471 | 0.99999697 |
| OR50 | 290 | 34.60920 | 7.4264501115 | 0.00143699 | 0.99999647 |

CPU and GPU fits agree with an independent Python regression to the tolerances
in `validate.py`. Both list **Ag-111 as the sole candidate in the current
measured-ground-state catalog**. Relative k errors against the SQLite
reference (half-life 7.45 days) are 0.2226% and 0.3161%. The database checksum is
unchanged after testing. This is a successful basic real-data regression and
candidate lookup, not proof of general or unique physical identification.

### Precision and source discrepancies

The workbook's final corrected estimate, cached at `Uncertainty!C33`, is
7.423603370544002 days; `Uncertainty!D33` gives standard uncertainty
0.0011158983577652663 days. Our primary OR20/OR50 fits differ from that estimate
by 0.0098151/0.0028467 days, about 8.80/2.55 of that quoted uncertainty. Those
ratios are descriptive, not statistical comparison tests: our method has a
different model and has not estimated its own full instrument uncertainty.
**We have not reproduced the researchers' corrected precision.** Their
workbook includes pile-up and other correction/uncertainty terms not present
in our basic fit, and a different regression model.

An additional source audit found:

- Every workbook measurement maps to a report. Start times, live times, and
  true durations match for all 1,082 measurements.
- One OR20 filename is abbreviated in workbook row 736:
  `...Td15_00.Spc` versus report `...Td15_0000`. A unique match by area,
  durations and timestamp resolves the mapping; both names are recorded.
- **39 OR50 peak areas differ** between the workbook and their named text
  reports, covering the `s3_Td15` and `s4_Td10` series. Maximum relative
  discrepancy is approximately 0.165%. The cause is unverified. We neither
  overwrite the archived reports nor silently replace their values with
  workbook values. The primary fit uses the text reports throughout.

Full per-record differences and all reference cell addresses/values are
retained in `workbook-reference.json`.

## Reproduce

From the repository root, after creating `isotopes.sqlite3`:

```sh
make -C x86_64/learn_decay release
python3 datasets/ag111/prepare.py
python3 datasets/ag111/validate.py
# With access to the NVIDIA GPU:
python3 datasets/ag111/validate.py --gpu
python3 tests/test_ag111_dataset.py
```

`validate.py` writes the requested backend results to `results/report.json`;
a CPU-only rerun replaces that report with a CPU-only report. The original
archive and individual result text files are retained.

The optional workbook audit requires `xlrd==2.0.2` (see
`requirements-workbook.txt`). It is not required for primary extraction or
inference. In this session the reader was installed only under `/tmp`:

```sh
python3 -m pip install --target /tmp/nuclideid-ag111-deps -r datasets/ag111/requirements-workbook.txt
PYTHONPATH=/tmp/nuclideid-ag111-deps python3 datasets/ag111/inspect_workbook.py
```

The workbook reference JSON is already retained, so ordinary reproduction
needs no Excel software or third-party Python packages. Integration regression
tests execute the CPU fitter; `NUCLIDEID_TEST_GPU=1` additionally runs GPU cases.
No GitHub push is performed by the preparation or test scripts.
