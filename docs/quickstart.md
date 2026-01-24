# Quickstart Guide

Date: 2026-01-24
Owner: Docs / Onboarding
Status: Draft

This guide helps new developers get up and running with Tribal Village quickly.

## Prerequisites

### Nim

- **Version**: 2.2.6 or later
- **Installation**: Use [nimby](https://github.com/treeform/nimby) for version management

```bash
# Download nimby (adjust URL for your platform)
curl -L https://github.com/treeform/nimby/releases/download/0.1.11/nimby-linux-x86_64 -o ./nimby
# macOS ARM: nimby-macOS-ARM64
# macOS x64: nimby-macOS-x86_64
chmod +x ./nimby

# Install Nim and sync dependencies
./nimby use 2.2.6
./nimby sync -g nimby.lock
```

After installation, ensure `~/.nimby/nim/bin` is on your PATH.

### Python (for training bindings)

- **Version**: 3.12.x
- **Packages**: gymnasium, numpy, pufferlib

```bash
pip install -e .
python -c "import tribal_village_env; print('import ok')"
```

For training support with CoGames/PufferLib:

```bash
pip install -e .[cogames]
```

### System Dependencies

- **OpenGL**: Required for graphical rendering
- **Linux**: OpenGL libraries (libGL, etc.)
- **macOS**: Metal/OpenGL (included with system)

## Building the Project

### Basic Compilation

Compile and run with release optimizations:

```bash
nim r -d:release --path:src src/tribal_village.nim
```

Or compile only:

```bash
nim c -d:release --path:src src/tribal_village.nim
```

### With Evolution Enabled

The AI evolution layer is disabled by default. To enable:

```bash
nim r -d:release -d:enableEvolution --path:src src/tribal_village.nim
```

### With Profiling (nimprof)

For low-level CPU profiling:

```bash
nim r --nimcache:./nimcache --profiler:on --stackTrace:on scripts/profile_env.nim
```

### With Step Timing

For per-step timing breakdown (useful for debugging performance):

```bash
nim r -d:stepTiming -d:release --path:src src/tribal_village.nim
```

Set environment variables to control timing output:

```bash
TV_STEP_TIMING=100 TV_STEP_TIMING_WINDOW=50 \
  nim r -d:stepTiming -d:release --path:src src/tribal_village.nim
```

## Running Headless (No Graphics)

### Profile AI Script

Run the built-in AI without rendering to measure performance:

```bash
nim r -d:release --path:src scripts/profile_ai.nim
```

With custom parameters:

```bash
TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_ai.nim
TV_PROFILE_STEPS=3000 TV_PROFILE_REPORT_EVERY=500 TV_PROFILE_SEED=42 \
  nim r -d:release --path:src scripts/profile_ai.nim
```

### Profile Environment Script

For nimprof CPU profiling with randomized actions:

```bash
nim r --nimcache:./nimcache --profiler:on --stackTrace:on scripts/profile_env.nim
```

### Profile Roles Script

For per-role action tracking and success rates:

```bash
nim r -d:release --path:src scripts/profile_roles.nim
TV_PROFILE_STEPS=3000 TV_PROFILE_REPORT_EVERY=500 \
  nim r -d:release --path:src scripts/profile_roles.nim
```

### Headless via CLI

Using the Python CLI with ANSI rendering:

```bash
tribal-village play --render ansi --steps 128
```

## Running with Graphics

### Main Entry Point

The graphical viewer runs via:

```bash
nim r -d:release --path:src src/tribal_village.nim
```

Or through the Python CLI:

```bash
tribal-village play
# This internally runs: nim r -d:release tribal_village.nim
```

### Keyboard Controls

| Key | Action |
|-----|--------|
| **Space** | Play/pause; step once when paused |
| **-** or **[** | Decrease simulation speed (0.5x) |
| **=** or **]** | Increase simulation speed (2x) |
| **N** / **M** | Cycle observation overlays |
| **Mouse drag** | Pan the map |
| **Scroll wheel** | Zoom in/out |

#### Agent Selection and Control

| Key | Action |
|-----|--------|
| **Click** | Select agent or tile |
| **W/S/A/D** or **Arrow keys** | Move selected agent (cardinal) |
| **Q/E/Z/C** | Move selected agent (diagonal) |
| **U** | Use/craft action in facing direction |

### Render Timing

For frame-by-frame render timing:

```bash
nim r -d:renderTiming -d:release --path:src src/tribal_village.nim
```

With environment variable control:

```bash
TV_RENDER_TIMING=0 TV_RENDER_TIMING_WINDOW=100 TV_RENDER_TIMING_EVERY=10 \
  nim r -d:renderTiming -d:release --path:src src/tribal_village.nim
```

## Running Tests

### Full Test Suite

Run all tests via the aggregator script:

```bash
nim r --path:src scripts/run_all_tests.nim
```

### AI Harness Only

Run just the AI harness tests:

```bash
nim r --path:src tests/ai_harness.nim
```

### Validation Sequence (from AGENTS.md)

1. Compile check:
   ```bash
   nim c -d:release tribal_village.nim
   ```

2. Smoke test (15s timeout):
   ```bash
   timeout 15s nim r -d:release tribal_village.nim
   ```

3. Test suite:
   ```bash
   nim r --path:src tests/ai_harness.nim
   ```

## Environment Variables Reference

### Profiling

| Variable | Description | Default |
|----------|-------------|---------|
| `TV_PROFILE_STEPS` | Number of steps to run in headless profile mode | 3000 |
| `TV_PROFILE_REPORT_EVERY` | Log progress every N steps (0 disables) | 0 |
| `TV_PROFILE_SEED` | Random seed for profiling runs | 42 |

### Step Timing (requires `-d:stepTiming`)

| Variable | Description | Default |
|----------|-------------|---------|
| `TV_STEP_TIMING` | Target step to start timing | -1 (disabled) |
| `TV_STEP_TIMING_WINDOW` | Number of steps to time | 0 |

### Render Timing (requires `-d:renderTiming`)

| Variable | Description | Default |
|----------|-------------|---------|
| `TV_RENDER_TIMING` | Target frame to start timing | -1 (disabled) |
| `TV_RENDER_TIMING_WINDOW` | Number of frames to time | 0 |
| `TV_RENDER_TIMING_EVERY` | Log every N frames | 1 |
| `TV_RENDER_TIMING_EXIT` | Exit after this frame | -1 (disabled) |

### Replay Recording

| Variable | Description | Default |
|----------|-------------|---------|
| `TV_REPLAY_DIR` | Directory for replay files | (none) |
| `TV_REPLAY_PATH` | Explicit replay file path (overrides dir) | (none) |
| `TV_REPLAY_NAME` | Base name for replay files | `tribal_village` |
| `TV_REPLAY_LABEL` | Label metadata in replay | `Tribal Village Replay` |

### Controller Mode

| Variable | Description |
|----------|-------------|
| `TRIBAL_PYTHON_CONTROL` | Use external neural network controller |
| `TRIBAL_EXTERNAL_CONTROL` | Use external neural network controller |

### Build Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `TRIBAL_VILLAGE_NIM_VERSION` | Nim version for Python build | 2.2.6 |
| `TRIBAL_VILLAGE_NIMBY_VERSION` | Nimby version for Python build | 0.1.11 |
| `TRIBAL_VECTOR_BACKEND` | Vector backend for training (serial/ray) | serial |

## Quick Reference

### Common Commands

```bash
# Play with graphics
tribal-village play
nim r -d:release --path:src src/tribal_village.nim

# Headless smoke test
tribal-village play --render ansi --steps 128

# Profile AI for 3000 steps
TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_ai.nim

# Run tests
nim r --path:src scripts/run_all_tests.nim

# Build shared library for Python
nim c --app:lib --mm:arc --opt:speed -d:danger --out:libtribal_village.so src/ffi.nim

# Train with CoGames
tribal-village train --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
```

### Compile-Time Flags

| Flag | Purpose |
|------|---------|
| `-d:release` | Enable optimizations |
| `-d:danger` | Maximum speed (no bounds checks) |
| `-d:stepTiming` | Enable step timing instrumentation |
| `-d:renderTiming` | Enable render timing instrumentation |
| `-d:enableEvolution` | Enable AI evolution layer |

## Troubleshooting

### "nim" or "nimble" not found

Ensure `~/.nimby/nim/bin` is on your PATH:

```bash
export PATH="$HOME/.nimby/nim/bin:$PATH"
```

### Missing sprite errors

Verify assets exist under `data/` and regenerate if needed:

```bash
python scripts/generate_assets.py
```

### GUI hangs after "[Exec]"

1. Try ANSI mode to confirm stepping works:
   ```bash
   tribal-village play --render ansi --steps 32
   ```

2. Enable step timing to see progress:
   ```bash
   TV_STEP_TIMING=0 TV_STEP_TIMING_WINDOW=100 \
     nim r -d:stepTiming -d:release --path:src src/tribal_village.nim
   ```

3. Verify OpenGL is available on your system.

## Next Steps

- See `docs/README.md` for the full documentation index
- See `docs/cli_and_debugging.md` for detailed CLI usage
- See `docs/ai_profiling.md` for AI performance analysis
- See `docs/training_and_replays.md` for ML training setup
