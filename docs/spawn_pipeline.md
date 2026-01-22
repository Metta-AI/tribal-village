# Spawn and Placement Pipeline

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document summarizes the spawn and placement flow in `src/spawn.nim` once the
terrain/biomes are established. It focuses on villages, structures, resources,
and creature spawns.

Related docs:
- `docs/terrain_biomes.md`
- `docs/world_generation.md`

Key implementation files:
- `src/spawn.nim`
- `src/placement.nim`
- `src/connectivity.nim`

## Core Data Structures
- **Terrain grid**: `env.terrain[x][y]` stores TerrainType (water, road, sand, etc.).
- **Blocking grid**: `env.grid` holds blocking Things (agents, walls, trees, buildings).
- **Background grid**: `env.backgroundGrid` holds non-blocking Things (doors, cliffs, docks).

Placement helpers (typical):
- `env.isSpawnable`, `env.canPlace`, `env.findEmptyPositionsAround`
- `tryPickEmptyPos`, `pickInteriorPos`, `placeResourceCluster`

## High-Level Spawn Order (spawn.nim)
1. **Initialize state**
   - Reset tints, grids, stockpiles, and per-step state.

2. **Trading hub and core roads**
   - Carve a neutral central hub, lock its tint, and extend cardinal roads.
   - Road tiles are TerrainRoad; bridges are placed where roads cross water.

3. **Villages and teams**
   - Choose village centers with spacing constraints.
   - Clear a village footprint, place altar and town center, and lay out
     starting buildings, doors, and walls.
   - Spawn six active agents per team; remaining slots are dormant.
   - Apply per-team tint to the village area.

4. **Hostile camps and spawners**
   - Place goblin hives and nearby goblin structures, then spawn goblin agents.
   - Place tumor spawners with minimum distance from teams and other spawners.

5. **Resources and terrain Things**
   - Trees, wheat, stone, gold, plants, fish, and relics are spawned as Things.
   - Clusters are shaped by biome constraints and density parameters.

6. **Connectivity pass**
   - `makeConnected` ensures the playable space is a single connected component,
     digging through sparse blockers when necessary.

7. **Wildlife**
   - Cow herds, wolves, and bears are placed after connectivity.

## Tuning and Debugging
- Resource densities and cluster sizes live in `src/spawn.nim` constants.
- Placement and spacing helpers live in `src/placement.nim`.
- Connectivity issues can be diagnosed in `src/connectivity.nim`.
