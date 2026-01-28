# Tribal Village Investigation Report

**Date:** 2026-01-28 (Updated)
**Investigator:** valkyrie (polecat)
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
  environment.nim           # Simulation core (42KB)
  types.nim                 # Core types and data structures (27KB)
  terrain.nim               # Terrain and biome management (47KB)
  combat.nim                # Combat rules and damage (10KB)
  spawn.nim                 # Entity spawning (66KB)
  step.nim                  # Step loop and action processing (105KB)
  scripted/                 # AI behaviors
    ai_core.nim             # Built-in AI system
    roles.nim               # Agent roles (gatherer, builder, fighter)
    coordination.nim        # Team coordination
  renderer.nim              # OpenGL rendering (32KB)
  ffi.nim                   # C interface for Python binding
tribal_village_env/         # Python wrapper + CLI
tests/                      # Domain-specific test harnesses
data/                       # Sprites, fonts, UI assets
docs/                       # Comprehensive documentation (45+ files)
```

## 2. Recent Development Progress

### Completed P1 Work (since last report)

All original P1 items have been **completed**:

| Bead | Type | Status | Description |
|------|------|--------|-------------|
| tv-z20 | feature | ✓ DONE | Gatherer flee behavior |
| tv-3ns | feature | ✓ DONE | Builder flee behavior |
| tv-96g | feature | ✓ DONE | True siege conversion |
| tv-cbg | feature | ✓ DONE | Structure repair for Builder |
| tv-puj | feature | ✓ DONE | Kiting for ranged units |
| tv-02pb | task | ✓ DONE | Pathfinding pre-allocation |
| tv-c035 | task | ✓ DONE | Spatial index O(1) queries |
| tv-v0lg | task | ✓ DONE | Entity movement tracking |

### Recent Feature Additions (git log)

- **Blacksmith upgrade system** for unit stats
- **Attack-move command** for military units
- **External patrol API** for military units
- **AoE2-style market trading** mechanics
- **Monk conversion** mechanic
- **Town Center garrison bonus**
- **Castle unique unit spawning**
- **Trebuchet pack/unpack** mechanic
- **Scout line-of-sight exploration**

## 3. Current Open Work

### P1 (High Priority) - 2 beads

| Bead | Type | Assignee | Description |
|------|------|----------|-------------|
| tv-t0ekp | task | capable | Audit recent merges for quality and integration |
| tv-d6m3x | bug | slit | Pre-existing test failure: AI Scout Behavior |

### Ready Work (No Blockers) - 3 beads

| Bead | Priority | Type | Description |
|------|----------|------|-------------|
| tv-8fvq6 | P4 | task | Consolidate and organize docs/ analysis files |
| tv-minx5 | P4 | task | Review action_space.md for outdated source paths |
| tv-58t60 | P4 | feature | Implement civilization bonuses using TeamModifiers |

### Upcoming Features (P3)

| Bead | Type | Description |
|------|------|-------------|
| tv-bus5q | feature | Victory conditions system (conquest, wonder, relic) |
| tv-bovho | feature | Batch training UI and mechanics |
| tv-14prc | feature | Trade Cog units for Dock-to-Dock gold |

## 4. Blockers

| Bead | Blocked By | Description |
|------|------------|-------------|
| tv-d6m3x | wisp | AI Scout Behavior test failure (in progress) |
| tv-t0ekp | wisp | Audit task (in progress) |

Both P1 blockers have assigned polecats actively working them.

## 5. Test Status

Tests pass on main. Test command:
```bash
nim c -r --path:src tests/ai_harness.nim
nim c -r --path:src tests/domain_economy_buildings.nim
```

Domain test suites cover:
- AI harness (scout, cliff damage, trebuchet)
- Economy buildings (market, crafting, storage, training)
- Attack-move, patrol, garrison, blacksmith upgrades
- Conversion/relics, navigation/spawn

## 6. Recommended Next Steps

1. **Complete P1 audit** (tv-t0ekp) - Ensure recent merges integrate cleanly
2. **Fix scout test failure** (tv-d6m3x) - Restore full test coverage
3. **Documentation consolidation** (tv-8fvq6) - Clean up analysis files
4. **Civilization bonuses** (tv-58t60) - Ready feature work

## 7. Key Documentation

- `docs/quickstart.md` - Build and run instructions
- `docs/game_logic.md` - Core game loop and mechanics
- `docs/ai_system.md` - Built-in AI architecture
- `docs/combat.md` - Combat rules and counters
- `docs/role_audit_report.md` - Deep audit of gatherer, builder, fighter roles
- `AGENTS.md` - Agent workflow (git, validation, commit protocol)

## Summary

Tribal Village has made significant progress since the last report. **All original P1 work is complete**, including flee behaviors, kiting, siege conversion, and performance optimizations. Recent merges added substantial AoE2-inspired features (market trading, monks, trebuchets, scouts, blacksmith upgrades).

Current focus:
1. **Quality assurance** - Auditing recent merges, fixing test failures
2. **Documentation** - Consolidating analysis files
3. **Future features** - Victory conditions, civilization bonuses

The project is in a healthy state with 2 P1 issues actively being worked, 3 ready tasks available, and comprehensive test coverage.
