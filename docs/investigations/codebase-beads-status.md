# Tribal Village Investigation Report

**Date:** 2026-01-25  
**Investigator:** rictus (polecat)  
**Bead:** tv-jhet

## 1. Project Purpose and Architecture

**Tribal Village** is a multi-agent reinforcement learning environment written in **Nim** with Python bindings (PufferLib compatible). Teams of agents:
- Gather resources (wood, stone, food, gold)
- Craft items (tools, weapons, armor)
- Build structures (houses, temples, fortifications)
- Compete against other teams
- Defend against hostile tumors and wildlife

### Architecture Overview

```
tribal_village.nim          # Entry point (windowed game loop)
src/
  environment.nim           # Simulation core, observation building
  types.nim                 # Core types and data structures
  terrain.nim               # Terrain and biome management
  combat.nim                # Combat rules and damage
  spawn.nim                 # Entity spawning
  scripted/
    ai_core.nim             # Built-in AI system
    roles.nim               # Agent roles (gatherer, builder, fighter)
    gatherer.nim            # Resource gathering behaviors
    builder.nim             # Construction behaviors
    fighter.nim             # Combat behaviors
  renderer.nim              # OpenGL rendering
  ffi.nim                   # C interface for Python binding
tribal_village_env/         # Python wrapper + CLI
tests/                      # Test harness (ai_harness.nim)
data/                       # Sprites, fonts, UI assets
docs/                       # Comprehensive documentation
```

## 2. Current Development Priorities

### P1 (High Priority) - 8 beads

| Bead | Type | Description |
|------|------|-------------|
| tv-z20 | feature | Add Gatherer flee behavior when enemies nearby |
| tv-3ns | feature | Add Builder flee behavior when enemies nearby |
| tv-96g | feature | Add true siege conversion for combat units |
| tv-cbg | feature | Add structure repair behavior for Builder |
| tv-puj | feature | Add kiting behavior for ranged units (Archers) |
| tv-02pb | task | Pre-allocate pathfinding scratch space to reduce GC pressure |
| tv-c035 | task | Add spatial index for O(1) nearest-thing queries |
| tv-v0lg | task | Track entity movement for incremental tint updates |

### P2 (Standard Priority) - Selected notable items

| Bead | Type | Description |
|------|------|-------------|
| tv-2bk | task | Implement EmergencyHeal behavior for agents with low HP |
| tv-8b8 | task | Add BuildingRepair behavior for damaged structures |

## 3. In-Progress Work

| Bead | Assignee | Description |
|------|----------|-------------|
| tv-agd | polecats/nux | Create comprehensive tribal_village backlog (~50 beads) |
| tv-wisp-5uv | - | Load context and verify assignment (molecule step) |
| tv-wisp-7uh | - | Submit work and self-clean (molecule step) |
| tv-wisp-9gv | - | Run tests and verify coverage (molecule step) |

## 4. Blockers

**None identified.** All ready beads have no blockers.

## 5. Recommended Next Steps

1. **Continue backlog creation** (tv-agd) - nux is actively building out the ~50 bead backlog
2. **Prioritize flee behaviors** (tv-z20, tv-3ns) - These are P1 and improve agent survivability
3. **Performance work** (tv-02pb, tv-c035, tv-v0lg) - These P1 tasks will improve scalability

## 6. Key Documentation

- `docs/quickstart.md` - Build and run instructions
- `docs/game_logic.md` - Core game loop and mechanics
- `docs/ai_system.md` - Built-in AI architecture
- `docs/combat.md` - Combat rules and counters
- `AGENTS.md` - Agent workflow (git, validation, commit protocol)

## Summary

Tribal Village is a mature multi-agent RL environment with active development. The codebase is well-structured with comprehensive documentation. Current focus areas are:
1. AI behavior improvements (flee, kiting, healing)
2. Performance optimizations (spatial indexing, GC reduction)
3. Gameplay features (siege, repair)

The project uses beads for task tracking with clear priorities. No blockers exist on the ready work queue.
