# Tribal Village Environment

Multi-agent RL environment built in Nim with PufferLib integration. Features 15 agents across 3 teams competing for resources while fighting off hostile Clippies.

## Quick Start

**Standalone Game**
```bash
nim r tribal_village.nim
```

**PufferLib Training**
```bash
./build_lib.sh
python -c "from tribal_village_env import TribalVillageEnv; env = TribalVillageEnv()"
```

## Game Overview

**Map**: 192x108 grid with procedural terrain (rivers, wheat fields, tree groves)
**Agents**: 15 agents in 3 teams of 5, each with specialized AI roles
**Resources**: ore, batteries, water, wheat, wood, spear, lantern, armor, bread
**Threats**: Autonomous Clippies that spawn and attack agents/buildings

### Core Gameplay Loop
1. **Gather** resources (mine ore, harvest wheat, chop wood, collect water)
2. **Craft** items using specialized buildings (forge spears, weave lanterns, etc.)
3. **Cooperate** within teams and compete across teams
4. **Defend** against Clippies using crafted spears

## Controls

**Agent Selection**: Click agents to view inventory overlay in top-left
**Movement**: Arrow keys/WASD for cardinal, QEZC for diagonal
**Actions**: U (use/craft), P (special action)
**Global**: Space (pause), +/- (speed), Mouse (pan/zoom)

## Technical Details

### Observation Space
21 layers, 11x11 grid per agent:
- **Layer 0**: Team-aware agent presence (1=team0, 2=team1, 3=team2, 255=Clippy)
- **Layers 1-9**: Agent orientation + inventories (ore, battery, water, wheat, wood, spear, lantern, armor)
- **Layers 10-18**: Buildings (walls, mines, converters, altars) + status
- **Layers 19-20**: Environmental effects + bread inventory

### Action Space
Multi-discrete `[move_direction, action_type]`:
- **Movement**: 8 directions (N/S/E/W + diagonals)
- **Actions**: Move, attack, use/craft, give items, plant lanterns

### Architecture
- **Nim backend**: High-performance simulation and rendering
- **Python wrapper**: PufferLib-compatible interface for all 15 agents
- **Zero-copy communication**: Direct pointer passing for efficiency
- **Web ready**: Emscripten support for WASM deployment

## Files

**Core**: `tribal_village.nim` (main), `src/environment.nim` (simulation), `src/ai.nim` (built-in agents)
**Rendering**: `src/renderer.nim`, `src/ui.nim`, `src/controls.nim`
**Integration**: `src/tribal_village_interface.nim` (C interface), `tribal_village_env/` (Python wrapper)
**Build**: `build_lib.sh`, `tribal_village.nimble`

## Dependencies

**Nim**: 2.2.4+ with boxy, windy, vmath, chroma packages
**Python**: 3.8+ with gymnasium, numpy, pufferlib
**System**: OpenGL for rendering