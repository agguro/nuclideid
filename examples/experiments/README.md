# Step-by-step experiment guide

These files let you try the program without obtaining a radioactive source or
operating a detector. Five CSVs are synthetic teaching data; the separate
Silver-111 files are real measurements downloaded from a published dataset.
All seven cases have been run on both CPU and GTX 1060 GPU. The synthetic
cases use the committed SQLite catalog's reference constants, so they check
known behavior, not independent nuclear measurements.

## 1. Build

Open a terminal in the project directory:

```sh
cd /home/agguro/projects/nuclideid
make release
```

If you cloned elsewhere, use that directory. The committed `isotopes.sqlite3`
is already supplied. These experiments do not require downloading or replacing
the database. Build dependencies and GPU requirements are in the root README.

## 2. Try perfect synthetic data

```sh
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/co60_clean.csv isotopes.sqlite3 --cpu
```

Expected: a half-life of approximately 166,344,192 seconds, fitted k about
4.1669454895e-9, and Co-60 as a candidate. The data covers three Co-60 half-lives
(about 15.8 years) using synthetic timestamps; it does not represent a quick
laboratory measurement. `y` starts at 1000 and decreases to 125.

`--cpu` deliberately selects the CPU reference backend. Omit it to use the GPU.

## 3. Add measurement-like noise

```sh
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/f18_noisy.csv isotopes.sqlite3 --cpu
```

Expected with the current catalog: half-life about 6600.73 seconds (110.01
minutes), close to the generating F-18 reference of 6586.2 seconds. It reports
three candidates at the default 1% tolerance, including F-18. This illustrates
why matching one decay rate does not always establish one isotope identity.
Noise is reproducible: multiplicative log-normal noise, sigma(log y)=0.01,
random seed 31415. This is not a physical detector/counting-noise simulation.

Try a narrower tolerance and observe how the candidate set changes:

```sh
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/f18_noisy.csv isotopes.sqlite3 --cpu --tolerance 0.001
```

Here 0.001 means **0.1%**, not 0.001%. The generating isotope may disappear
because the fitted rate itself has measurement-like noise. Choosing a smaller
tolerance does not automatically produce a more correct identification.

## 4. Use real internet measurements

```sh
./release/bin/x86_64/learn_decay/learn_decay datasets/ag111/derived/or20.csv isotopes.sqlite3 --cpu
./release/bin/x86_64/learn_decay/learn_decay datasets/ag111/derived/or50.csv isotopes.sqlite3 --cpu
```

Expected half-lives: approximately 7.43342 and 7.42645 days, respectively.
The output expresses half-life in seconds; divide by 86400 to obtain days.
Both list Ag-111 as their sole candidate at the default tolerance. The original
archive, provenance, source discrepancies and instrument-correction limits
are retained in [the dataset documentation](../../datasets/ag111/README.md).
These results do not reproduce the research workbook's corrected precision.

## 5. Explore the current model's limits

```sh
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/f18_background.csv isotopes.sqlite3 --cpu
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/f18_n13_mixture.csv isotopes.sqlite3 --cpu
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/invalid_zero.csv isotopes.sqlite3 --cpu
```

Expected outcomes:

| File | What it contains | Expected result |
|---|---|---|
| `f18_background.csv` | F-18 exponential plus constant background 200 | Fit-quality rejection, exit 2 |
| `f18_n13_mixture.csv` | F-18 and N-13 with initial intensities 400 and 600 | Fit-quality rejection, exit 2 |
| `invalid_zero.csv` | One zero-intensity observation | Input rejection, exit 1 |

These are intentionally failing experiments. Rejection means the case behaved
as expected. It does not establish that all backgrounds or mixtures are
recognized: some can resemble a single exponential over a limited interval.
The model has no explicit background or mixture fitting yet.

## 6. Compare GPU execution

Repeat any successful command above without `--cpu`, for example:

```sh
./release/bin/x86_64/learn_decay/learn_decay examples/experiments/co60_clean.csv isotopes.sqlite3
```

The final field of the fit line says `backend=GPU` instead of `CPU reference`.
The numerical results should agree up to floating-point rounding. GPU access
must work in your shell; the program never silently falls back to CPU.

## 7. Run the entire experiment set automatically

```sh
python3 examples/experiments/run.py
python3 examples/experiments/run.py --gpu
```

Each command verifies all five synthetic examples and both real Silver-111
series. Every case should say `expected outcome confirmed`, including the
intentional failures. Captured outputs are saved as `cpu-results.json` and
`gpu-results.json`. These scripts leave the database and original measurements
unchanged and do not send data to a remote service.

To recreate the synthetic CSVs exactly from the current SQLite references:

```sh
python3 examples/experiments/generate.py
```

This overwrites the five named teaching files and `scenarios.json`. If you want
to edit a dataset, first copy it to a different filename. Each CSV is plain text
with header `t,y`: time is in seconds, intensity is in arbitrary units. The
fitter requires at least three observations, strictly increasing nonnegative
times, and positive finite intensities. Full model details are in
[the inference README](../../x86_64/learn_decay/README.md).
