# Terrain and Spawn Pipeline

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document summarizes how maps are generated and populated: terrain, biomes, cliffs,
structures, resources, and spawns. It is a code-aligned guide to the world pipeline.

Key implementation files:
- `src/spawn.nim`
- `src/terrain.nim`
- `src/biome.nim`
- `src/connectivity.nim`
- `src/placement.nim`

## Core Data Structures
- **Terrain grid**: `env.terrain[x][y]` stores TerrainType (water, road, sand, etc.).
- **Things**:
  - `env.grid` holds blocking Things (agents, walls, trees, buildings).
  - `env.backgroundGrid` holds non-blocking Things (doors, cliffs, docks).
- **Biomes**: `env.biomes[x][y]` drives base terrain and coloring.
- **Elevation**: `env.elevation[x][y]` influences cliffs and obscured observation tiles.

## High-Level Generation Order (spawn.nim)
1. **Initialize state**
   - Reset tints, grids, stockpiles, and per-step state.

2. **Biome + terrain seed pass**
   - `initTerrain` assigns base biomes and terrain textures.

3. **Water pass**
   - Swamp water is applied.
   - Rivers are carved.
   - Optional tree oases carve small water clusters.

4. **Elevation and cliffs**
   - `applyBiomeElevation` sets base height by biome.
   - `applyCliffRamps` opens limited ramp/road connections.
   - `applyCliffs` places cliff Things (edges and corners) based on elevation deltas.

5. **Blocking structure pass**
   - City biome blocks become walls.
   - Dungeon zones create maze/radial wall masks.
   - Border walls are added around the map.

6. **Biome coloring**
   - `applyBiomeBaseColors` computes base tint colors and blends edges.

7. **Trading hub**
   - Carves a neutral central hub, locks its tint, and extends cardinal roads.

8. **Villages and teams**
   - Place village footprints spaced apart.
   - Add altar, town center, starting buildings, houses, doors, and walls.
   - Spawn six active agents per team (others are dormant).

9. **Hostile camps and spawners**
   - Goblin hives and structures are placed and goblin agents spawned.
   - Tumor spawners are placed with minimum distance to teams and each other.

10. **Resources and terrain Things**
    - Trees, wheat, stone, gold, plants, fish, and relics are spawned as Things.
    - Clusters are shaped by biome and density parameters.

11. **Connectivity pass**
    - `makeConnected` ensures the playable space is a single connected component,
      digging through walls, dunes, snow, or sparse blockers when needed.

12. **Wildlife**
    - Cow herds, wolves, and bears are placed after connectivity.

## Cliffs and Ramps
- Cliffs are Things placed in `backgroundGrid` so they are visible but do not occupy
  blocking slots.
- Cliff type is derived from elevation comparisons to neighbors, producing edge or
  corner variants.
- Ramps are represented by roads placed during `applyCliffRamps` to connect elevations.

## Roads and Bridges
- Roads are terrain tiles (TerrainRoad).
- Water crossings are replaced with TerrainBridge when roads pass through water.
- Trading hub roads are carved early; later road placement is limited by terrain and
  placement rules.

## Tuning and Debugging
- Biome sizes and counts are controlled in `src/terrain.nim` and `src/biome.nim`.
- Placement helpers live in `src/placement.nim` (structures, spacing, and empty-space checks).
- Connectivity issues can be diagnosed in `src/connectivity.nim`.
