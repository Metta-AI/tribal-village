# AI Profiling and Evolution Toggle

Date: 2026-01-19
Owner: AI / Systems
Status: Draft

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
