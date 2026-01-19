# Terrain, Elevation, and Connectivity Notes

Date: 2026-01-19
Owner: Docs / Worldgen
Status: Draft

## Purpose
Several sessions focused on swamps, ramps, and connectivity. This doc summarizes how
biomes, elevation, cliffs, and ramps are currently generated so changes stay consistent
and connected.

## Biomes and Base Terrain
- Base biomes are assigned in `src/terrain.nim` and applied before water features.
- Swamp water is applied via `applySwampWater` in `src/terrain.nim`.

## Elevation Rules
Elevation is assigned per tile in `applyBiomeElevation` in `src/spawn.nim`:
- Swamp tiles: elevation `-1`
- Snow tiles: elevation `+1`
- All other tiles: elevation `0`
- Water and bridges are forced to elevation `0`

## Cliffs and Ramps
- Cliffs are placed based on elevation deltas in `applyCliffs` (`src/spawn.nim`).
- Ramps are implemented using Road tiles in `applyCliffRamps` (`src/spawn.nim`).
- Every 10th cliff edge becomes a ramp by converting the two adjacent tiles to Road.

## Movement Across Elevation
`env.canTraverseElevation` in `src/environment.nim` controls elevation traversal:
- Flat movement is always allowed.
- A 1-level step is allowed only if either tile is a Road (ramp).
- Larger elevation deltas are blocked.

## Ramp Tiles (Defined, Not Wired)
Terrain enums include ramp tiles (`RampUp*`, `RampDown*`) but they are not placed
or checked by `canTraverseElevation`. Roads currently act as ramps.

If you want true ramp tiles:
- Place them during generation (instead of roads).
- Update `canTraverseElevation` to accept ramp tiles.
- Register ramp visuals in the terrain catalog / renderer.

## Cliff Overlays
Cliffs are background Things and do not block movement themselves. They visualize
where elevation changes occur. See `docs/terrain_cliffs.md` for sprite details.

## Connectivity Pass
`makeConnected` in `src/connectivity.nim` runs after generation:
- Labels connected components on walkable tiles.
- Digs minimal paths through walls/terrain if multiple components exist.
- Uses `env.canTraverseElevation`, so ramps matter for connectivity.

## Trading Hub (Center Structure)
The neutral hub is spawned near the map center in `src/spawn.nim`:
- The hub area is cleared, tinted, and tint-locked.
- A castle, walls, towers, and a mix of neutral buildings are placed.
- Roads extend out to connect the hub with the rest of the map.

## Debugging Tips
- If swamps or snow appear at the wrong elevation, check `applyBiomeElevation`.
- If the map fragments, verify ramps exist and `makeConnected` runs after cliffs.
- Use `tribal-village play --render ansi` to inspect terrain layout quickly.
