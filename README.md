# Tribal Village

Multi-agent RL environment in Nim with a Python wrapper (PufferLib compatible). Teams of agents gather resources, craft items, build structures, and compete while defending against hostile tumors and wildlife.

<img width="2932" height="1578" alt="Tribal Village screenshot" src="https://github.com/user-attachments/assets/b1736191-ff85-48fa-b5cf-f47e441fd118" />

## Installation

**Requirements:** Python 3.12+, Nim 2.2.6+ (via nimby), OpenGL

```bash
# 1. Install Nim with nimby
curl -L https://github.com/treeform/nimby/releases/download/0.1.11/nimby-$(uname -s)-$(uname -m) -o ./nimby
chmod +x ./nimby && ./nimby use 2.2.6 && ./nimby sync -g nimby.lock

# 2. Install Python package
pip install -e .
```

## Quickstart

```bash
# Play interactively (builds Nim library if needed)
tribal-village play

# Run with random actions (text mode)
tribal-village play --render ansi --random-actions --steps 100

# Train with CoGames/PufferLib
pip install -e .[cogames]
tribal-village train --steps 1000000 --parallel-envs 8 --num-workers 4
```

**Controls:** Arrow keys/WASD (move), U (use/craft), Space (pause/step), scroll (zoom)

## Python API

```python
from tribal_village_env import TribalVillageEnv

env = TribalVillageEnv(config={
    'max_steps': 10000,
    'render_mode': 'rgb_array',  # or 'ansi'
})
obs, info = env.reset()
obs, reward, terminated, truncated, info = env.step(actions)
```

## Documentation

| Topic | Description |
|-------|-------------|
| [Quickstart](docs/quickstart.md) | Prerequisites, building, running, testing |
| [Game Logic](docs/game_logic.md) | Step loop, actions, entities, episode rules |
| [Action Space](docs/action_space.md) | Discrete 250 actions (verb * 25 + direction/argument) |
| [Observation Space](docs/observation_space.md) | 84 layers, 11x11 grid per agent |
| [Combat](docs/combat.md) | Combat rules, counters, damage |
| [Economy & Respawn](docs/economy_respawn.md) | Inventory, stockpiles, markets, hearts |
| [AI System](docs/ai_system.md) | AI wiring, roles, behavior model |
| [World Generation](docs/world_generation.md) | Trading hub, rivers, biomes, spawning |
| [CLI & Debugging](docs/cli_and_debugging.md) | CLI usage, debugging flags |
| [Training & Replays](docs/training_and_replays.md) | Training entrypoints, replay setup |
| [Asset Pipeline](docs/asset_pipeline.md) | Asset generation workflow |

See [docs/README.md](docs/README.md) for the complete documentation index.

## Project Structure

```
tribal_village.nim          # Entry point
src/
  environment.nim           # Simulation core
  ai_core.nim              # Built-in AI
  renderer.nim             # Rendering
  ffi.nim                  # C interface for Python
tribal_village_env/         # Python wrapper + CLI
data/                       # Sprites, fonts, UI
```

## License

MIT
