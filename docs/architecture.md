# Architecture Overview

Date: 2026-01-27
Owner: Systems
Status: Active

This document provides a high-level architectural overview of the Tribal Village codebase.

## System Components

The system consists of three main layers:

```
┌─────────────────────────────────────────────────────────────┐
│                     Python Layer                            │
│  tribal_village_env/environment.py (PufferLib integration) │
│  tribal_village_env/cogames/ (training utilities)          │
└─────────────────────────┬───────────────────────────────────┘
                          │ ctypes FFI
┌─────────────────────────▼───────────────────────────────────┐
│                      FFI Layer                              │
│              src/ffi.nim (exported C functions)             │
└─────────────────────────┬───────────────────────────────────┘
                          │ direct calls
┌─────────────────────────▼───────────────────────────────────┐
│                     Nim Core                                │
│  Environment, Step, Spawn, Combat, Terrain, Renderer, AI   │
└─────────────────────────────────────────────────────────────┘
```

### Nim Core (~17,000 lines)

The core game simulation written in Nim for performance. Key modules:

| Module | Responsibility |
|--------|----------------|
| `types.nim` | Core type definitions, constants, `Environment` struct |
| `environment.nim` | Game state, observation building, stockpiles |
| `step.nim` | Per-tick action execution, entity updates |
| `spawn.nim` | Map generation, entity placement |
| `combat.nim` | Damage calculation, unit interactions |
| `terrain.nim` | Terrain types, movement costs, biomes |
| `agent_control.nim` | Controller interface (built-in AI or external NN) |
| `renderer.nim` | Visual rendering (Boxy/OpenGL) |
| `scripted/` | Built-in AI behavior system |

### FFI Layer

`src/ffi.nim` exports C-compatible functions for Python:

- `tribal_village_create()` - Create environment
- `tribal_village_reset_and_get_obs()` - Reset and get observations
- `tribal_village_step_with_pointers()` - Step with direct buffer I/O
- `tribal_village_render_rgb()` / `tribal_village_render_ansi()` - Rendering
- `tribal_village_destroy()` - Cleanup

Uses zero-copy buffer communication for performance.

### Python Wrapper

`tribal_village_env/environment.py` provides:

- `TribalVillageEnv` class implementing PufferLib's `PufferEnv`
- Gymnasium-compatible `reset()` / `step()` interface
- Direct numpy buffer passing to Nim (no conversion overhead)
- Cross-platform shared library loading

## Data Flow

### Step Cycle

```
Python                          Nim FFI                    Nim Core
  │                               │                          │
  │ step(actions_dict)            │                          │
  ├──────────────────────────────►│                          │
  │  actions_buffer (uint8[N])    │ step_with_pointers()     │
  │                               ├─────────────────────────►│
  │                               │                          │ env.step()
  │                               │                          │   - decode actions
  │                               │                          │   - execute moves/attacks
  │                               │                          │   - update entities
  │                               │                          │   - rebuild observations
  │                               │◄─────────────────────────┤
  │◄──────────────────────────────┤ write to buffers:        │
  │  obs_buffer, rewards,         │   observations           │
  │  terminals, truncations       │   rewards                │
  │                               │   terminals              │
  │                               │   truncations            │
```

### Observation Tensor

Shape: `[MapAgents, ObservationLayers, 11, 11]`

- 1006 agents total (8 teams × 125 + 6 goblins)
- ~85 observation layers (terrain one-hot, thing one-hot, metadata)
- 11×11 viewport centered on each agent

Observations are rebuilt in batch at end of each step for efficiency.

### Action Encoding

Actions are encoded as single uint8:
```
action = verb * 25 + argument
```

10 verbs × 25 arguments = 250 action space.

See `docs/action_space.md` for verb definitions.

## Module Dependencies

```
tribal_village.nim (main entry)
    ├── environment.nim
    │       ├── types.nim
    │       │       ├── terrain.nim
    │       │       ├── items.nim
    │       │       └── common.nim
    │       ├── registry.nim
    │       ├── spatial_index.nim
    │       ├── biome.nim
    │       ├── entropy.nim
    │       └── includes:
    │           ├── colors.nim
    │           ├── placement.nim
    │           ├── combat.nim
    │           ├── connectivity.nim
    │           ├── spawn.nim
    │           ├── tint.nim
    │           └── step.nim
    │               └── actions.nim
    ├── renderer.nim
    ├── agent_control.nim
    │       └── scripted/
    │           ├── ai_core.nim
    │           ├── ai_defaults.nim
    │           ├── roles.nim
    │           ├── options.nim
    │           ├── gatherer.nim
    │           ├── builder.nim
    │           ├── fighter.nim
    │           ├── coordination.nim
    │           └── evolution.nim
    └── tileset.nim

ffi.nim (shared library entry)
    ├── environment.nim
    └── agent_control.nim
```

Note: Several modules are `include`d rather than `import`ed for compile-time inlining.

## Key Entry Points

### `tribal_village.nim`

Main executable entry point for the standalone game/renderer:

1. Creates `Environment` via `newEnvironment()`
2. Initializes windowing (Windy) and rendering (Boxy)
3. Loads assets from `data/`
4. Runs game loop: input → `env.step()` → render

### `src/ffi.nim`

Shared library entry point (`libtribal_village.{dylib,so,dll}`):

1. Exports C-compatible functions with `{.exportc, dynlib.}`
2. Maintains global `Environment` instance
3. Provides direct buffer interface for Python
4. Used by `TribalVillageEnv` in Python

### `tribal_village_env/environment.py`

Python environment wrapper:

1. Loads Nim shared library via ctypes
2. Implements PufferLib's `PufferEnv` interface
3. Allocates numpy buffers for observations/rewards
4. Translates between Python dicts and C buffers

## Build Process

### Prerequisites

- Nim 2.2.4+
- nimble (Nim package manager)
- Python 3.10+ with pufferlib

### Building the Shared Library

```bash
# Install Nim dependencies
nimble install

# Build shared library for Python
nimble buildLib
# Produces: libtribal_village.{dylib,so,dll}
```

The nimble task runs:
```
nim c --app:lib --mm:arc --opt:speed -d:danger --out:libtribal_village.{ext} src/ffi.nim
```

### Building the Standalone Game

```bash
nimble run
# Or directly:
nim c -r tribal_village.nim
```

### Build Variants

| Define | Effect |
|--------|--------|
| `-d:danger` | Disable all runtime checks (production) |
| `-d:release` | Optimized build with some checks |
| `-d:renderTiming` | Enable frame timing profiler |
| `-d:stepTiming` | Enable step timing profiler |
| `-d:enableEvolution` | Enable AI role evolution |
| `-d:emscripten` | WASM build for web |

### Python Package

```bash
pip install -e .
# Runs setup.py which triggers nimble buildLib
```

## Runtime Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TRIBAL_PYTHON_CONTROL` | Enable external NN controller |
| `TRIBAL_EXTERNAL_CONTROL` | Enable external NN controller |
| `TV_PROFILE_STEPS` | Run N steps then exit (profiling) |
| `TV_RENDER_TIMING` | Start frame timing at step N |
| `TV_LOG_RENDER` | Enable step logging |

### Python Config

`TribalVillageEnv` accepts config dict:
```python
env = TribalVillageEnv(config={
    "max_steps": 10000,
    "render_mode": "rgb_array",
    "render_scale": 4,
    "tumor_spawn_rate": 0.1,
    # ... reward coefficients
})
```

Config is passed to Nim via `tribal_village_set_config()`.

## Related Documentation

- `docs/quickstart.md` - Getting started guide
- `docs/game_logic.md` - Game rules and mechanics
- `docs/observation_space.md` - Observation tensor details
- `docs/action_space.md` - Action encoding
- `docs/ai_system.md` - Built-in AI architecture
