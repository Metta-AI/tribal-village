# Configuration Reference

Date: 2026-01-27
Owner: Docs / Systems
Status: Active

This document is the canonical reference for all Tribal Village configuration options. It covers
runtime parameters (tunable at initialization), compile-time constants, and environment variables.

## Runtime Configuration (EnvironmentConfig)

The `EnvironmentConfig` object controls runtime behavior of the simulation. These parameters can
be adjusted when creating an environment without recompiling.

### Python Usage

```python
from tribal_village_env import make_tribal_village_env

env = make_tribal_village_env(config={
    "max_steps": 5000,
    "heart_reward": 2.0,
    "death_penalty": -10.0,
    # ... other options
})
```

Configuration values are passed through the FFI layer to the Nim engine. Unspecified values use
defaults from `defaultEnvironmentConfig()` in `src/types.nim`.

### Core Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_steps` | int | 3000 | Maximum simulation steps per episode. Episode truncates when this limit is reached. |

**Impact:** Controls episode length. Longer episodes allow more complex strategies but increase
training time. Short episodes (1000-2000) are good for rapid iteration; production training
typically uses 3000-10000.

### Combat Configuration

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `tumor_spawn_rate` | float | 0.1 | 0.0-1.0 | Probability per step that spawners generate new tumors. |

**Impact:** Higher values increase environmental pressure from clippy/tumors. At 0.0, tumors never
spawn (peaceful mode). At 1.0, spawners attempt to create tumors every step.

### Reward Configuration

Rewards shape agent learning by providing positive or negative signals for specific actions or
outcomes. The default configuration uses the "arena_basic_easy_shaped" reward profile.

#### Active Rewards (Default Profile)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `heart_reward` | float | 1.0 | Reward for depositing bars at an altar (creates hearts). |
| `ore_reward` | float | 0.1 | Reward for mining gold ore from deposits. |
| `bar_reward` | float | 0.8 | Reward for smelting ore into bars at magma pools. |

**Gameplay impact:** These rewards encourage the core resource loop: mine ore -> smelt bars ->
deposit at altar. The relative weights (ore: 0.1, bar: 0.8, heart: 1.0) create increasing rewards
as resources are processed.

#### Disabled Rewards (Set to 0.0 by Default)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `wood_reward` | float | 0.0 | Reward for harvesting wood from trees. |
| `water_reward` | float | 0.0 | Reward for collecting water (fishing, buckets). |
| `wheat_reward` | float | 0.0 | Reward for harvesting wheat. |
| `spear_reward` | float | 0.0 | Reward for crafting spears. |
| `armor_reward` | float | 0.0 | Reward for crafting armor. |
| `food_reward` | float | 0.0 | Reward for producing food (bread, cooked items). |
| `cloth_reward` | float | 0.0 | Reward for producing cloth at weaving looms. |
| `tumor_kill_reward` | float | 0.0 | Reward for destroying tumors. |

**Usage:** Enable these rewards to encourage specific behaviors. For example, set `wood_reward: 0.1`
to incentivize wood gathering for construction-focused training.

#### Penalties

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `survival_penalty` | float | -0.01 | Per-step penalty applied to all alive agents. |
| `death_penalty` | float | -5.0 | One-time penalty when an agent dies. |

**Gameplay impact:**
- `survival_penalty` creates time pressure, encouraging efficient action rather than idle behavior.
  Stronger penalties (-0.05 to -0.1) push agents toward faster resource gathering.
- `death_penalty` discourages risky behavior. Adjust based on whether you want cautious or
  aggressive agents.

### Example Configurations

#### Peaceful Exploration

```python
config = {
    "max_steps": 10000,
    "tumor_spawn_rate": 0.0,
    "survival_penalty": 0.0,
    "death_penalty": 0.0,
}
```

#### Aggressive Combat Training

```python
config = {
    "max_steps": 2000,
    "tumor_spawn_rate": 0.3,
    "tumor_kill_reward": 2.0,
    "death_penalty": -2.0,
}
```

#### Full Economy

```python
config = {
    "max_steps": 5000,
    "heart_reward": 1.0,
    "ore_reward": 0.1,
    "bar_reward": 0.5,
    "wood_reward": 0.1,
    "food_reward": 0.3,
    "cloth_reward": 0.2,
}
```

## Compile-Time Constants

These values are set at compile time in `src/types.nim` and require recompilation to change.
They define the structural parameters of the simulation.

### Map Layout

| Constant | Value | Description |
|----------|-------|-------------|
| `MapLayoutRoomsX` | 1 | Number of rooms horizontally. |
| `MapLayoutRoomsY` | 1 | Number of rooms vertically. |
| `MapBorder` | 1 | Border tiles around the map. |
| `MapRoomWidth` | 305 | Width of each room in tiles. |
| `MapRoomHeight` | 191 | Height of each room in tiles. |
| `MapWidth` | computed | Total map width (rooms * room_width + border). |
| `MapHeight` | computed | Total map height (rooms * room_height + border). |

### Agent Configuration

| Constant | Value | Description |
|----------|-------|-------------|
| `MapRoomObjectsTeams` | 8 | Number of player teams. |
| `MapAgentsPerTeam` | 125 | Agent slots per team. |
| `MapAgents` | 1006 | Total agent slots (8 teams * 125 + 6 goblins). |
| `AgentMaxHp` | 5 | Default max HP for villagers. |
| `MapObjectAgentMaxInventory` | 5 | Maximum inventory slots per agent. |

### Observation System

| Constant | Value | Description |
|----------|-------|-------------|
| `ObservationWidth` | 11 | Width of agent observation window. |
| `ObservationHeight` | 11 | Height of agent observation window. |
| `ObservationRadius` | 5 | Observation radius (width / 2). |
| `ObservationLayers` | 79 | Total observation tensor layers. |

### Unit Stats

#### Health Points

| Unit | Max HP | Notes |
|------|--------|-------|
| Villager | 5 | Default unit. |
| Man-at-Arms | 7 | Frontline infantry. |
| Archer | 4 | Ranged, fragile. |
| Scout | 6 | Fast, medium durability. |
| Knight | 8 | Heavy cavalry. |
| Monk | 4 | Support unit. |
| Battering Ram | 18 | Siege, high HP. |
| Mangonel | 12 | Siege, AoE damage. |
| Goblin | 4 | NPC hostile. |

#### Attack Damage

| Unit | Damage | Range | Notes |
|------|--------|-------|-------|
| Villager | 1 | 1 | Basic attack. |
| Man-at-Arms | 2 | 1 | Strong melee. |
| Archer | 1 | 3 | Ranged attack. |
| Scout | 1 | 1 | Fast attack. |
| Knight | 2 | 1 | Heavy attack. |
| Monk | 0 | - | Heals/converts instead. |
| Battering Ram | 2 | 1 | Siege bonus vs structures (3x). |
| Mangonel | 2 | 3 | AoE damage, siege bonus. |
| Goblin | 1 | 1 | NPC attack. |

### Building Stats

| Building | Max HP | Special |
|----------|--------|---------|
| Wall | 10 | Basic defense. |
| Door | 5 | Passable by team. |
| Outpost | 8 | Vision. |
| Guard Tower | 14 | Auto-attacks (damage: 2, range: 4). |
| Town Center | 20 | Population cap. |
| Castle | 30 | Auto-attacks (damage: 3, range: 6). |

### Wildlife

| Animal | Max HP | Damage | Behavior |
|--------|--------|--------|----------|
| Bear | 6 | 2 | Aggressive, aggro radius: 6. |
| Wolf | 3 | 1 | Pack hunter, pack size: 3-5. |
| Cow | - | - | Passive, herd movement. |

### Resource Costs

| Constant | Value | Description |
|----------|-------|-------------|
| `RoadWoodCost` | 1 | Wood to build road. |
| `OutpostWoodCost` | 1 | Wood to build outpost. |
| `ResourceCarryCapacity` | 5 | Max resources an agent can carry. |
| `ResourceNodeInitial` | 25 | Starting resources in nodes (trees, mines). |
| `MineDepositAmount` | 100 | Resources in mine deposits. |

## Environment Variables

These variables control runtime behavior and are read at process startup.

### Profiling

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_PROFILE_STEPS` | 3000 | Steps to run in headless profile mode. |
| `TV_PROFILE_REPORT_EVERY` | 0 | Log progress every N steps (0 = disabled). |
| `TV_PROFILE_SEED` | 42 | Random seed for profiling runs. |

### Step Timing (requires `-d:stepTiming`)

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_STEP_TIMING` | -1 | Target step to start timing (-1 = disabled). |
| `TV_STEP_TIMING_WINDOW` | 0 | Number of steps to time. |

### Render Timing (requires `-d:renderTiming`)

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_RENDER_TIMING` | -1 | Target frame to start timing (-1 = disabled). |
| `TV_RENDER_TIMING_WINDOW` | 0 | Number of frames to time. |
| `TV_RENDER_TIMING_EVERY` | 1 | Log every N frames. |
| `TV_RENDER_TIMING_EXIT` | -1 | Exit after this frame (-1 = disabled). |

### Render Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_LOG_RENDER` | false | Enable render logging. |
| `TV_LOG_RENDER_WINDOW` | 100 | Window size for render logging. |
| `TV_LOG_RENDER_EVERY` | 1 | Log every N renders. |
| `TV_LOG_RENDER_PATH` | "" | Path for render log output. |

### Replay Recording

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_REPLAY_DIR` | "" | Directory for replay files. |
| `TV_REPLAY_PATH` | "" | Explicit replay file path (overrides dir). |
| `TV_REPLAY_NAME` | "tribal_village" | Base name for replay files. |
| `TV_REPLAY_LABEL` | "Tribal Village Replay" | Label metadata in replay. |

### Controller Mode

| Variable | Description |
|----------|-------------|
| `TRIBAL_PYTHON_CONTROL` | Use external neural network controller. |
| `TRIBAL_EXTERNAL_CONTROL` | Use external neural network controller. |

### Build Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TRIBAL_VILLAGE_NIM_VERSION` | 2.2.6 | Nim version for Python build. |
| `TRIBAL_VILLAGE_NIMBY_VERSION` | 0.1.11 | Nimby version for Python build. |
| `TRIBAL_VECTOR_BACKEND` | "serial" | Vector backend for training (serial/ray). |

## Compile-Time Flags

These flags are passed to the Nim compiler to enable optional features.

| Flag | Purpose |
|------|---------|
| `-d:release` | Enable optimizations. |
| `-d:danger` | Maximum speed (no bounds checks). |
| `-d:stepTiming` | Enable step timing instrumentation. |
| `-d:renderTiming` | Enable render timing instrumentation. |
| `-d:enableEvolution` | Enable AI evolution layer. |

## Reference Files

- `src/types.nim`: EnvironmentConfig definition and compile-time constants.
- `src/ffi.nim`: FFI layer for Python config passing.
- `tribal_village_env/environment.py`: Python configuration interface.
- `docs/quickstart.md`: Additional environment variable documentation.
