# Terrain, Elevation, Cliffs, and Ramps

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Overview
The map has a terrain grid (water/grass/sand/etc.) plus a separate elevation grid used to
restrict movement. Cliffs are *background* Things that visualize elevation boundaries; they
are not the blocker themselves. Elevation changes are blocked unless a passable connector
exists (currently: roads).

Key files:
- `src/terrain.nim` (terrain enums and biome defaults)
- `src/spawn.nim` (`applyBiomeElevation`, `applyCliffRamps`, `applyCliffs`)
- `src/environment.nim` (`canTraverseElevation` movement rule)
- `src/registry.nim` / `src/types.nim` (cliff kinds + background kinds)

## Elevation
Elevation is computed from biome type in `applyBiomeElevation`:
- Water/Bridge -> elevation 0
- Swamp biome -> elevation -1
- Snow biome -> elevation +1
- All other biomes -> elevation 0

This means elevation boundaries only occur where snow or swamp biomes touch other biomes.

## Movement Across Elevation
Movement is cardinal only when traversing elevation (`dx + dy == 1`).
`canTraverseElevation` enforces:
- Same elevation -> allowed
- Elevation delta of 1 -> allowed **only if either tile is `Road`**
- Larger deltas -> blocked

So today, **roads act as ramps**. There are ramp terrain enums, but they are not wired
into traversal or placement yet.

## Cliff Placement
`applyCliffs` scans each tile and compares its elevation to neighbors. It adds a cliff
Thing on tiles that are higher than adjacent tiles:

- **Edges**: exactly one lower cardinal neighbor -> `CliffEdgeN/E/S/W`
- **Inner corners**: two lower cardinal neighbors forming a corner -> `CliffCornerIn*`
- **Outer corners**: no lower cardinal neighbors but one lower diagonal neighbor ->
  `CliffCornerOut*`

Cliffs are background Things (`BackgroundThingKinds`) and do not block movement directly.
They are a visual overlay for elevation boundaries.

## Cliff Ramps (Current Behavior)
`applyCliffRamps` is a simple passability hack:
- It scans elevation boundaries and every 10th boundary turns the *lower* and *higher*
  tiles into `Road`.
- Because roads allow elevation traversal, this creates sparse “ramps.”

There is no dedicated ramp tile placement today.

## Ramps (Defined, Not Wired)
Terrain includes ramp enums (`RampUp*`, `RampDown*`) but they are not used in map
generation, rendering catalogs, or `canTraverseElevation`. If you want real ramp tiles:

1. Place ramps in `applyCliffRamps` (or a new pass) instead of roads.
2. Update `canTraverseElevation` to accept ramp tiles as valid connectors.
3. Update `TerrainCatalog` / renderer assets so ramps draw correctly.
4. Update connectivity algorithms (if any) to treat ramps as passable.

## Rendering
Cliffs are drawn in a fixed order (`CliffDrawOrder` in `src/renderer.nim`) to ensure
consistent overlap when multiple cliff pieces occupy a region.

## Common Gotchas (from recent sessions)
- Cliffs are **visual only**. Movement is blocked by elevation, not by the cliff sprites.
- Roads are currently the *only* elevation connectors; this surprises people looking for
  explicit ramp tiles.
- If you update connectivity logic, you must account for elevation + roads, not just
  terrain passability.
