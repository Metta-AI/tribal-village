# Terrain, Biomes, Elevation, and Cliffs

Date: 2026-01-19
Owner: Design / Systems
Status: Draft

## Generation Pipeline (High Level)
Map generation is staged so terrain, biomes, elevation, and cliffs stay consistent:
1) `initTerrain` sets base terrain + biome types (no water yet).
2) `applyBiomeZones` overlays biome zones (forest/desert/caves/city/plains/snow/swamp).
3) `applySwampWater` paints water ponds inside swamp biomes.
4) `generateRiver` carves a river across the map.
5) Optional tree oases add extra water and trees.
6) `applyBiomeElevation` assigns elevation from biome types.
7) `applyCliffRamps` adds occasional road ramps across elevation changes.
8) `applyCliffs` places cliff overlays where higher tiles border lower tiles.

See: `src/terrain.nim` and `src/spawn.nim`.

## Biome Zones and Masks
Biome zones are blob-shaped regions distributed across the map. The zone selection order is
sequential by default (`UseSequentialBiomeZones = true`) so every biome appears at least once
on most maps. Each zone has its own mask, then each biome applies additional rules:

- Forest / Caves / Plains
  - Uses a biome-specific mask to dither edges and add internal texture.
- Desert
  - Blends sand into the zone edges (low density), then applies dunes on top.
- City
  - Separate block and road masks. Blocks later become walls, roads remain passable.
- Snow / Swamp
  - Uses an inset fill (inner mask only) so the biome core is solid and the edge ring
    is left as base biome. This supports clear elevation/cliff boundaries.

Zones do not freely overwrite each other. `canApplyBiome` only allows overwriting if the
current biome is base, empty, or the same biome. This keeps overlaps stable and predictable.

## Elevation Rules
Elevation is derived from biome type in `applyBiomeElevation`:
- Snow = +1
- Swamp = -1
- Everything else = 0
- Water / bridge tiles are forced to 0

This means snow forms plateaus and swamp forms basins relative to the base terrain.

## Cliffs and Ramps
Cliffs are visual overlays that mark elevation transitions:
- `applyCliffs` checks each tile against its neighbors and drops an oriented cliff overlay
  wherever a higher tile borders a lower tile.
- Cliffs are background things (non-blocking). Movement is restricted by elevation, not
  by cliffs directly.
- `applyCliffRamps` sometimes converts adjacent tiles to `Road` to create a ramp between
  elevation steps (roads are the ramp mechanic).

Placement rules in `src/placement.nim` ensure cliffs own their tile: other background things
cannot overwrite a cliff, and cliffs can replace existing background overlays.

## Movement and Observation Effects
- `canTraverseElevation` allows movement on the same elevation, or a 1-step height change
  if either the source or destination tile is `Road`.
- The observation system masks tiles above the agent's elevation via `ObscuredLayer` in
  `src/ffi.nim` (`applyObscuredMask`). Higher tiles are blanked out for that agent.

## Practical Notes
- Zone masks are blob + dither based, so biome edges are intentionally irregular.
- Snow and swamp zones are contiguous in their cores, but can still inherit holes from
  the zone mask itself. The inset fill only guarantees the inner region is filled.
