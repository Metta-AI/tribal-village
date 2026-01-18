# Tribal Village Environment

Multi‑agent RL playground in Nim with a Python wrapper (PufferLib compatible). 1000 village agent slots (8 teams, 125 per
team; 6 active per team at start) plus 6 goblin agents compete for resources while hostile tumors spread a freezing
“clippy” tint across the map.
Code: <https://github.com/Metta-AI/tribal-village>

<img width="2932" height="1578" alt="image" src="https://github.com/user-attachments/assets/b1736191-ff85-48fa-b5cf-f47e441fd118" />

## Quick Start (prioritized)

**You’ll need**: Nim 2.2.6+ (via nimby), Python 3.12.x, `pip`, OpenGL libs.

1. Install Nim with nimby + sync deps

```bash
curl -L https://github.com/treeform/nimby/releases/download/0.1.11/nimby-macOS-ARM64 -o ./nimby
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
tribal-village play
# this play command actually runs: nim r -d:release tribal_village.nim
# Space toggles play/pause; when paused, press Space to step once
```

4. Train with CoGames / PufferLib

```bash
# Requires CoGames: pip install -e .[cogames]
tribal-village train --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
# or, if using the cogames CLI:
cogames train-tribal -p class=tribal --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
```

If you want to train via the metta workspace, use the helper wrapper from this repo:

```bash
# Uses metta/.venv via uv and the local tribal-village checkout.
scripts/train_metta.sh --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
# Override the metta repo location if needed:
METTA_DIR=/path/to/metta scripts/train_metta.sh --steps 1000000 --parallel-envs 8 --num-workers 4
```

## Configuration (Python)

Pass a config dict to the Python wrapper (rendering + gameplay tuning):

```python
config = {
    'max_steps': 10000,         # Episode length (Python-side truncation)
    'render_mode': 'rgb_array', # or 'ansi'
    'render_scale': 4,          # RGB scale factor (full-map render)
    'ansi_buffer_size': 1_000_000,
    # Nim gameplay tuning (optional)
    'tumor_spawn_rate': 0.1,
    'heart_reward': 1.0,
    'ore_reward': 0.1,  # gold mining reward
    'bar_reward': 0.8,
    'wood_reward': 0.0,
    'water_reward': 0.0,
    'wheat_reward': 0.0,
    'spear_reward': 0.0,
    'armor_reward': 0.0,
    'food_reward': 0.0,
    'cloth_reward': 0.0,
    'tumor_kill_reward': 0.0,
    'survival_penalty': -0.01,
    'death_penalty': -5.0,
}
env = TribalVillageEnv(config=config)
```
These gameplay settings map to `EnvironmentConfig` in `src/environment.nim`.

## Game Overview

- Map: 234x148 grid, procedural rivers/fields/trees/biomes.
- Agents: 1000 village slots (8 teams, 125 per team; 6 active per team at start) plus 6 goblin agents. Dormant village
  slots can respawn at altars by spending hearts.
- Units: Villager, Man-at-Arms, Archer, Scout, Knight, Monk, Battering Ram, Mangonel, Boat, Goblin.
- Resources: gold, stone, water, wheat, wood, bars, spears, lanterns, armor, bread, plants, fish, meat, relics (plus team
  stockpiles for food/wood/stone/gold/water).
- Threats: tumors from spawners spread clippy tint; frozen tiles/objects can't be used until thawed. Bears, wolves, and
  goblins roam the map.
- Coalition touches we enjoyed while building it:
  - Territory control via lanterns
  - Tiny async loops (e.g., craft armor from bars and hand off to teammates)
  - Tank / DPS / healer roles that synergize in combat
  - Altars + hearts power respawns for your squad
  - Note: most production building cooldowns are currently 0 (use/craft actions are available every step)

### Core Gameplay Loop

1. **Gather** resources (mine gold/stone, harvest wheat, chop wood, collect water, hunt fish/meat, forage plants)
2. **Craft** items using specialized buildings (forge spears/armor, bake bread, weave lanterns, etc.)
3. **Build & train** structures and units (barracks, archery range, stables, siege, monastery, castle)
4. **Cooperate** within teams and compete across teams
5. **Defend** against tumors, goblins, and wildlife using trained units and crafted gear

## Controls

**Select**: click agent  
**Move**: Arrow keys / WASD (cardinal), QEZC (diagonal)  
**Act**: U (use/craft in facing direction)  
**Global**: Space (play/pause + step when paused), `-`/`=` or `[`/`]` (speed), N/M (cycle observation overlays), mouse drag (pan), scroll (zoom)

## Technical Details

### Observation Space

84 layers, 11x11 grid per agent:

- **Terrain layers (17)**: Empty, Water, Bridge, Fertile, Road, Grass, Dune, Sand, Snow,
  RampUpN/S/W/E, RampDownN/S/W/E
- **Thing layers (62)**: Agent, Wall, Door, Tree, Wheat, Fish, Relic, Stone, Gold, Bush, Cactus, Stalagmite, Magma,
  Altar, Spawner, Tumor, Cow, Bear, Wolf, Corpse, Skeleton, ClayOven, WeavingLoom, Outpost, GuardTower, Barrel, Mill,
  Granary, LumberCamp, Quarry, MiningCamp, Stump, Lantern, TownCenter, House, Barracks, ArcheryRange, Stable,
  SiegeWorkshop, MangonelWorkshop, Blacksmith, Market, Dock, Monastery, University, Castle, GoblinHive, GoblinHut,
  GoblinTotem, Stubble, CliffEdgeN/E/S/W, CliffCornerInNE/SE/SW/NW, CliffCornerOutNE/SE/SW/NW
- **TeamLayer**: team id + 1 for agents and team-owned buildings, 0 otherwise
- **AgentOrientationLayer**: orientation + 1 for agents, 0 otherwise
- **AgentUnitClassLayer**: unit class + 1 for agents, 0 otherwise
- **TintLayer**: action/combat tint codes (`ActionTint*` in `src/types.nim`)
- **ObscuredLayer**: 1 when target tile is above observer elevation (all other layers zeroed)

Inventory is **not** encoded in spatial observations (see `src/environment.nim`).

### Action Space

Discrete 250 (`verb * 25 + argument`). Most verbs interpret arguments 0..7 as directions; higher arguments (8..24) are
used for build choices and resource-planting variants.

- **Directions**: N/S/E/W + diagonals (0..7)
- **Verbs**: 0=noop, 1=move, 2=attack, 3=use/craft, 4=swap, 5=give, 6=plant lantern, 7=plant wheat/tree, 8=build, 9=orient

### Architecture

- **Nim backend**: High-performance simulation and rendering
- **Python wrapper**: PufferLib-compatible interface for all 1000 agents
- **Zero-copy communication**: Direct pointer passing for efficiency
- **Web ready**: Emscripten support for WASM deployment

## Build

- Native shared library for Python:
  `nim c --app:lib --mm:arc --opt:speed -d:danger --out:libtribal_village.(so|dylib|dll) src/ffi.nim`
  (the CLI runs this automatically via `tribal_village_env.build.ensure_nim_library_current`).
- Native desktop viewer: `nim r -d:release tribal_village.nim`
- WebAssembly demo (requires Emscripten): command in `scripts/` section below; outputs `build/web/tribal_village.html`

## Asset Workflow

- Add or update prompts in `data/prompts/assets.tsv`.
- Generate sprites via `python scripts/generate_assets.py` (requires `GOOGLE_API_KEY` or gcloud ADC).
- For oriented units, keep the solid royal purple background in prompts and let the script postprocess/key it out.
- Use `python scripts/render_asset_preview.py` to review oriented sets (e.g., `--glob "data/oriented/tumor*.png"`).

### PufferLib Rendering

- Python bindings default to `render_mode="rgb_array"` and stream full-map RGB frames via Nim.
- Adjust `render_scale` in the env config (default 4) to control output resolution.
- Set `render_mode="ansi"` for lightweight terminal output.

## Files

**Core**: `tribal_village.nim` (entry), `src/environment.nim` (simulation), `src/ai_core.nim` (built-ins)  
**Rendering**: `src/renderer.nim`, `data/` (sprites/fonts/UI)  
**Integration**: `src/ffi.nim` (C interface), `tribal_village_env/` (Python wrapper + CLI)  
**Build**: `nimby.lock`, `tribal_village.nimble`, `pyproject.toml`

## Dependencies

**Nim**: 2.2.6+ with boxy, windy, vmath, chroma (installed via `nimby sync -g nimby.lock`)  
**Python**: 3.12.x with gymnasium, numpy, pufferlib (pulled via `pip install -e .`)  
**System**: OpenGL for rendering
