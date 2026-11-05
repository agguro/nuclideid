# Synthetic single-exponential measurements

```sh
make -C x86_64/create_decay_data release
./release/bin/x86_64/create_decay_data/create_decay_data 0.25 257 20
./release/bin/x86_64/create_decay_data/create_decay_data 0.25 257 20 -o measurements.csv --cpu
```

Usage: `create_decay_data K NPOINTS MAX_T [-o FILE.csv] [--cpu]`.
Defaults to GPU execution and `decay_data.csv`. Output is always `t,y` CSV,
not the old binary format. The old `-csv` switch is unnecessary and rejected.

K and MAX_T must be positive finite numbers, NPOINTS an integer in 3..1,000,000,
and `0 < K*MAX_T <= 700`. Scientific notation is supported. Samples span
0..MAX_T inclusive with `y=exp(-K*t)`, no noise, unit initial amplitude, and
17 significant digits. Representability checks reject repeated timestamps
or nonpositive/nonfinite generated intensity values.

The GPU implementation uses double-precision range reduction, a degree-18
exponential polynomial on the reduced interval, and a power-of-two scale. It
replaces the old unbounded Taylor expansion and incorrect coefficient bits.
It has been checked against Python/libm exp, including total decay of 700
exponents and sample counts around block boundaries. This remains a floating
point approximation, not a correctly rounded exponential guarantee.

`--cpu` uses libm exp directly as an independent reference backend. CUDA errors
are reported and never trigger an implicit fallback. The build requires CUDA
ptxas and the driver library, even if CPU mode is selected. See the
[inference documentation](../learn_decay/README.md) for dependencies and tests.

CUDA calls, device copies, file writes, and close/rename operations are checked.
Output is written to a unique temporary file beside the destination and renamed
only after successful generation and writing; failure preserves existing data.
Temporary files are removed on handled failures. Exit status is 0 on success,
1 on failure. Inputs are validated before opening the output file.

This generator is for algorithm tests. It does not simulate background,
counting noise, mixtures, or detector physics. Independently generated Python
measurements are also used to test inference so shared generator/fitter errors
cannot alone establish correctness.
