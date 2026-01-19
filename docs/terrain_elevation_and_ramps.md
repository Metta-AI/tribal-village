# Terrain Elevation and Ramps

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Overview
Elevation is a separate grid from terrain. It controls movement across height
boundaries, while cliffs are just the visual overlay (see `docs/terrain_cliffs.md`).
Ramps exist as terrain enums but are not fully wired yet; roads currently serve as
passable connectors across elevation changes.

Key files:
- `src/spawn.nim` (`applyBiomeElevation`, `applyCliffRamps`)
- `src/environment.nim` (`canTraverseElevation` movement rule)
- `src/terrain.nim` (terrain enums)

## Elevation Sources
`applyBiomeElevation` assigns elevation by biome:
- Water/Bridge -> 0
- Swamp -> -1
- Snow -> +1
- Others -> 0

So elevation boundaries appear where snow/swamp zones meet other biomes.

## Movement Rule
`canTraverseElevation` enforces:
- Movement must be cardinal (no diagonal elevation steps).
- Same elevation -> allowed.
- Elevation delta of 1 -> allowed **only if either tile is `Road`**.
- Larger deltas -> blocked.

This is why roads currently function as “ramps.”

## Cliff Ramps (Current Behavior)
`applyCliffRamps` turns some elevation boundaries into roads:
- Every 10th boundary converts both the lower and higher tile to `Road`.
- This creates sparse, deterministic passable connectors.

## Ramp Tiles (Defined, Not Wired)
Terrain enums include:
- `RampUpN/S/E/W`
- `RampDownN/S/E/W`

They are **not** placed in map generation and are **not** checked by
`canTraverseElevation`. If you want true ramp tiles, you will need to:

1. Place ramp tiles during generation (`applyCliffRamps` or a new pass).
2. Update `canTraverseElevation` to accept ramp tiles as connectors.
3. Update `TerrainCatalog` and renderer assets for correct visuals.
4. Update any connectivity logic to treat ramps as passable.

## Common Gotchas (from recent sessions)
- Cliffs are visual only; elevation rules are what block movement.
- Road is the only elevation connector right now, so “ramps” are effectively
  roads on boundaries.
- Connectivity algorithms must account for elevation + roads, not just terrain.
