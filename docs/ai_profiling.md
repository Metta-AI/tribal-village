# AI Profiling and Evolution Toggle

Date: 2026-01-19 (updated 2026-02-06)
Owner: AI / Systems
Status: Active

## Evolution Toggle (Compile-Time)
The scripted AI has an evolution layer that is disabled by default.
The toggle lives in `src/scripted/ai_defaults.nim`:

- `EvolutionEnabled = defined(enableEvolution)`

To enable evolution:
```
nim r -d:release -d:enableEvolution --path:src tribal_village.nim
```

When disabled, only the core roles (Gatherer, Builder, Fighter) are assigned.
When enabled, the role catalog loads history and samples non-core roles.

## Headless AI Profiling
Use `scripts/profile_ai.nim` to measure population growth and altar heart counts
without the renderer:

```
nim r -d:release --path:src scripts/profile_ai.nim
TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_ai.nim
TV_PROFILE_REPORT_EVERY=500 TV_PROFILE_SEED=42 nim r -d:release --path:src scripts/profile_ai.nim
```

Environment variables:
- `TV_PROFILE_STEPS` (default 3000)
- `TV_PROFILE_REPORT_EVERY` (0 disables periodic logging)
- `TV_PROFILE_SEED` (default 42)

The script reports baseline house counts, max house counts, and max altar hearts per team.

## Environment Profiling (nimprof)
For low-level performance profiling, use `scripts/profile_env.nim`:

```
nim r --nimcache:./nimcache --profiler:on --stackTrace:on scripts/profile_env.nim
```

This runs a headless environment loop with randomized actions and is suitable for
`nimprof` analysis.

## Benchmarking (Performance Regression Detection)

Use `scripts/benchmark_steps.nim` (or `make benchmark`) to measure steps/second
and detect performance regressions against a stored baseline:

```bash
# Quick benchmark (saves baseline to baselines/benchmark.json)
make benchmark

# Compare against existing baseline in CI
TV_PERF_BASELINE=baselines/benchmark.json TV_PERF_FAIL_ON_REGRESSION=1 \
  nim c -r -d:perfRegression -d:release --path:src scripts/benchmark_steps.nim
```

Environment variables:
- `TV_PERF_STEPS` (default 1000) - measured steps
- `TV_PERF_SEED` (default 42) - random seed for reproducibility
- `TV_PERF_WARMUP` (default 100) - warmup steps before measurement
- `TV_PERF_BASELINE` - path to baseline JSON for comparison
- `TV_PERF_SAVE_BASELINE` - path to save new baseline
- `TV_PERF_THRESHOLD` (default 10) - regression threshold percentage
- `TV_PERF_FAIL_ON_REGRESSION` - set to "1" for CI gate mode

Output includes wall-clock time, per-step latency statistics (mean, P50, P95, P99,
min, max), steps/second throughput, and per-subsystem breakdown.

## Compile-Time Instrumentation Flags

All flags are zero-cost when disabled. See `docs/recently-merged-features.md` for
full environment variable reference for each flag.

| Flag | Purpose | Key File |
|------|---------|----------|
| `-d:stepTiming` | Per-subsystem step timing (11 subsystems) | `src/agent_control.nim` |
| `-d:perfRegression` | Sliding-window regression detection | `src/perf_regression.nim` |
| `-d:actionFreqCounter` | Action distribution by unit type | `src/action_freq_counter.nim` |
| `-d:renderTiming` | Per-frame render timing | `src/renderer.nim` |
| `-d:spatialAutoTune` | Density-based spatial cell adaptation | `src/spatial_index.nim` |
| `-d:spatialStats` | Spatial query efficiency metrics | `src/spatial_index.nim` |
| `-d:flameGraph` | CPU sampling (flamegraph.pl compatible) | `src/tribal_village.nim` |
| `-d:aiAudit` | AI decision logging (`TV_AI_LOG=1`) | `src/scripted/ai_defaults.nim` |
| `-d:enableEvolution` | Enable role evolution and history | `src/scripted/ai_defaults.nim` |
