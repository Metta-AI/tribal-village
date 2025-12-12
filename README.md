# Tribal Village Environment

Multi‑agent RL playground in Nim with a Python wrapper (PufferLib compatible). Sixty agents (8 teams) compete for
resources while hostile tumors spread a freezing “clippy” tint across the map. Code: <https://github.com/Metta-AI/tribal-village>

<img width="2932" height="1578" alt="image" src="https://github.com/user-attachments/assets/b1736191-ff85-48fa-b5cf-f47e441fd118" />

## Quick Start (prioritized)

**You’ll need**: Nim 2.2.x (via nimby), Python 3.12.x, `pip`, OpenGL libs.

1. Install Nim with nimby + sync deps

```bash
curl -L https://github.com/treeform/nimby/releases/download/0.1.13/nimby-macOS-ARM64 -o ./nimby
chmod +x ./nimby
./nimby use 2.2.6
./nimby sync -g nimby.lock
```

2. Install Python wrapper (editable) + quick smoke test

```bash
pip install -e .
python -c "import tribal_village_env; print('import ok')"
```

3. Play via CLI (builds/refreshes the Nim lib if missing)

```bash
tribal-village play # hold the spacebar to step the environment
```

or

```bash
nim r -d:release tribal_village.nim
```

5. Train with CoGames / PufferLib

```bash
cogames train-tribal -p class=tribal --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
```

## Configuration (Python)

Pass a config dict to tweak the simulation:

```python
config = {
    'max_steps': 1000,          # Episode length
    'ore_per_battery': 1,       # Ore needed to craft battery
    'batteries_per_heart': 1,   # Batteries needed for heart at assembler
    'enable_combat': True,      # Enable tumor spawning and combat
    'tumor_spawn_rate': 0.1,   # Tumor spawn frequency (lower = slower spawns)
    'tumor_damage': 1,         # Damage tumors deal to agents
    'heart_reward': 1.0,        # Reward for heart crafting
    'ore_reward': 0.1,          # Reward for mining ore
    'battery_reward': 0.8,      # Reward for crafting batteries
    'wood_reward': 0.0,         # Reward for chopping wood
    'water_reward': 0.0,        # Reward for collecting water
    'wheat_reward': 0.0,        # Reward for harvesting wheat
    'spear_reward': 0.0,        # Reward for crafting spears
    'armor_reward': 0.0,        # Reward for crafting armor
    'food_reward': 0.0,         # Reward for crafting bread
    'cloth_reward': 0.0,        # Reward for crafting lanterns
    'tumor_kill_reward': 0.0,  # Reward for clearing tumors
    'survival_penalty': 0.0,    # Penalty per step (negative)
    'death_penalty': 0.0        # Penalty for agent death (negative)
}
env = TribalVillageEnv(config=config)
```

## Game Overview

- Map: 192x108 grid, procedural rivers/fields/trees.
- Agents: 60 agents (8 teams, 5 per team).
- Resources: ore, batteries, water, wheat, wood, spears, lanterns, armor, bread.
- Threats: tumors spread dark clippy tint; frozen tiles/objects cannot be harvested or used until thawed.
- Coalition touches we enjoyed while building it:
  - Territory control via lanterns
  - Tiny async loops (e.g., craft 5x armor from wood and hand off to teammates)
  - Tank / DPS / healer roles that synergize in combat
  - Hearts power respawns for your squad

### Core Gameplay Loop

1. **Gather** resources (mine ore, harvest wheat, chop wood, collect water)
2. **Craft** items using specialized buildings (forge spears, weave lanterns, etc.)
3. **Cooperate** within teams and compete across teams
4. **Defend** against tumors using crafted spears

## Controls

**Select**: click agent (inventory overlay top-left)  
**Move**: Arrow keys / WASD (cardinal), QEZC (diagonal)  
**Act**: U (use/craft), P (special)  
**Global**: Space (pause), +/- (speed), mouse (pan/zoom)

## Technical Details

### Observation Space

21 layers, 11x11 grid per agent:

- **Layer 0**: Team-aware agent presence (1=team0, 2=team1, 3=team2, 255=Tumor)
- **Layers 1-9**: Agent orientation + inventories (ore, battery, water, wheat, wood, spear, lantern, armor)
- **Layers 10-18**: Buildings (walls, mines, converters, assemblers) + status
- **Layers 19-20**: Environmental effects + bread inventory

### Action Space

Multi-discrete `[move_direction, action_type]`:

- **Movement**: 8 directions (N/S/E/W + diagonals)
- **Actions**: Move, attack, use/craft, give items, plant lanterns

### Architecture

- **Nim backend**: High-performance simulation and rendering
- **Python wrapper**: PufferLib-compatible interface for all 60 agents
- **Zero-copy communication**: Direct pointer passing for efficiency
- **Web ready**: Emscripten support for WASM deployment

## Build

- Native shared library for Python: `nim c --app:lib ... src/tribal_village_interface.nim` (see Quick Start step 3)
- Native desktop viewer: `nim r -d:release tribal_village.nim`
- WebAssembly demo (requires Emscripten): command in `scripts/` section below; outputs `build/web/tribal_village.html`

### PufferLib Rendering

- Python bindings default to `render_mode="rgb_array"` and stream full-map RGB frames via Nim.
- Adjust `render_scale` in the env config (default 4) to control output resolution.
- Set `render_mode="ansi"` for lightweight terminal output.

## Files

**Core**: `tribal_village.nim` (entry), `src/environment.nim` (simulation), `src/ai.nim` (built-ins)  
**Rendering**: `src/renderer.nim`, `src/ui.nim`, `src/controls.nim`  
**Integration**: `src/tribal_village_interface.nim` (C interface), `tribal_village_env/` (Python wrapper)  
**Build**: `nimby.lock`, `tribal_village.nimble`

## Dependencies

**Nim**: 2.2.x with boxy, windy, vmath, chroma (installed via `nimby sync -g nimby.lock`)  
**Python**: 3.12.x with gymnasium, numpy, pufferlib (pulled via `pip install -e .`)  
**System**: OpenGL for rendering
