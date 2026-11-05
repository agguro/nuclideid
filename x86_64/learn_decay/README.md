# Decay fitting and SQLite candidate matching

The assembly host now loads isotope reference records directly from SQLite via
`isotope_catalog_load`. There is no `isotopes.bin`, fixed record count, float32
lookup, or binary measurement map. The GPU fits measurement data; CPU matching
uses the sorted SQLite catalog. Transferring the catalog itself to the GPU is
unnecessary for this implementation.

## Build and run

Requires GNU binutils, GCC for linking libc startup, libc/libm development
files, SQLite development files, the NVIDIA CUDA
Driver library (`libcuda.so`), and CUDA `ptxas`. The default GPU target is
`sm_61`, tested on a GTX 1060. If changing `GPU_ARCH`, clean/rebuild the kernels
and host tools so the embedded CUBIN is regenerated.

```sh
make -C x86_64/learn_decay debug
make -C x86_64/learn_decay release
./release/bin/x86_64/learn_decay/learn_decay
./release/bin/x86_64/learn_decay/learn_decay measurements.csv isotopes.sqlite3 --tolerance 0.01
./release/bin/x86_64/learn_decay/learn_decay measurements.csv --cpu
```

Defaults: `decay_data.csv`, `isotopes.sqlite3`, GPU fitting, 1% relative decay
constant tolerance. `--cpu` explicitly chooses the reference backend; a CUDA
failure is an error and never silently changes backends. `--help` prints usage.
Even CPU mode currently links the CUDA Driver library, but does not initialize
the GPU.

## Measurement contract

The CSV must have the exact header `t,y` and 3..1,000,000 finite numeric rows.
Times are nonnegative and strictly increasing; intensities are positive.
Scientific notation and decimal fractions are accepted. CRLF, blank lines
following the header, and no final newline are supported. Extra columns,
quoted numeric fields, embedded NULs, and missing values are rejected. Input
files and SQLite are read-only. No binary data files are generated.

`y` may have an arbitrary positive amplitude: it need not start at 1. Multiple
measurements must cover an informative time interval; a flat signal does not
identify a positive decay rate.

## Fit model and output

The assumed model is a single exponential, `y=A*exp(-k*t)`. Instead of running
Adam independently on each point, the implementation computes a closed-form
least-squares line through **all** `log(y)` measurements. The fit minimizes
squared residuals in log space, suitable for a model of multiplicative noise.
It is not a Poisson count likelihood or an additive-noise least-squares fit.

Before GPU transfer, the host uses libm's double-precision `log` and transforms
measurements to:

```text
x = (t-t_first)/(t_last-t_first)
v = log(y)-log(y_first)
```

A two-pass centered regression avoids the large dynamic range of raw time
squares. The GPU uses one block of 256 threads, each visiting every 256th sample,
then shared-memory reductions. Threads without samples still participate in
barriers. The result contains both means and three centered second moments.
The CPU reference implements the same statistical model independently with
sequential reductions. The host computes final log residuals explicitly.

Output includes `k`, half-life in seconds, `log_amplitude` (natural log of A at
time zero), log-domain RMSE, log-domain R-squared, sample count and backend.
The CLI requires log RMSE <=0.05 and R-squared >=0.95 before candidate matching.
These are explicit engineering quality gates, not statistical confidence
levels or guarantees that a sample contains only one nuclide.

Only `status='measured'` reference records participate. The program lists every
candidate satisfying `abs(k_reference-k_fit)/k_fit <= tolerance`. Default
tolerance is 0.01; allowed range is `(0,1]`. It does not invent an exact match
outside that interval, hide equal/near-equal candidates, or assert unique
identification from a decay constant alone. Candidates remain ordered by the
catalog's `(k,z,n)` order, not by confidence or probability.

Exit status:

- 0: the fit passes quality gates and at least one candidate exists; there may
  still be multiple candidates.
- 1: invalid input, missing/incompatible SQLite database, flat/growing/invalid
  fit, allocation error, output error, or CUDA failure.
- 2: fit quality rejected or no candidate within tolerance.

The model does not account for background, mixtures, daughter ingrowth,
instrument response, or zero/negative counts. Positive mixtures may resemble a
single exponential over a limited interval; passing quality gates does not
rule that out. Reference half-life uncertainty is retained in SQLite's source
fields but is not yet propagated into the fit or matching tolerance. Stable,
unknown and qualified measurements remain outside the candidate set.

## Synthetic data

The [generator](../create_decay_data/README.md) creates checked `t,y` CSV with
17 significant digits using either the GPU or an independent libm CPU path.
For a real Co-60 regression example from the current SQLite dataset:

```sh
./release/bin/x86_64/create_decay_data/create_decay_data 4.166945489506152e-9 257 720000000 -o decay_data.csv
./release/bin/x86_64/learn_decay/learn_decay decay_data.csv isotopes.sqlite3 --tolerance 1e-8
```

The numeric constant in this example comes from this project's current IAEA
snapshot; it is an example input, not a universal measurement standard.

## Tests

```sh
make -C x86_64/learn_decay MODE=debug test
NUCLIDEID_TEST_GPU=1 make -C x86_64/learn_decay MODE=release test
```

CPU-only runs skip the hardware-specific cases. The full suite compares CPU,
GPU, and independent Python regression/exp results, including non-unit
amplitudes, noise, very small and large k, counts around 256, longer inputs,
ambiguous/out-of-range candidates, bad CSV, read-only files, and injected CUDA
and output failures. Real-catalog comparisons run when `isotopes.sqlite3` is
available. Hardware tests use the local GPU, not a stubbed successful fit.

NVIDIA Compute Sanitizer 2022.3 was also attempted, but it terminated before
instrumenting the first CUDA call in this environment. Consequently, memory
and synchronization sanitizer checks are not claimed as passed; actual GPU
execution and numeric comparisons above are the completed hardware checks.

Original host and kernel sources are preserved as `.before-decay.bak` files.
