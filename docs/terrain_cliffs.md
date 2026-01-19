# Terrain Cliffs

## Overview
Cliffs are visual overlays generated from the elevation field. They are
non-blocking background Things that sit on top of terrain tiles.

## How Cliffs Are Generated
1) `applyBiomeElevation` assigns elevation by biome:
   - Swamp = -1
   - Snow = +1
   - Others = 0
2) `applyCliffRamps` occasionally turns adjacent elevation deltas into Road
   tiles so steep changes can be traversed.
3) `applyCliffs` scans each tile and compares neighbor elevations:
   - If a neighbor is lower, a cliff edge or corner overlay is placed.
   - Cardinal adjacency yields edge or inner-corner pieces.
   - Diagonal-only gaps yield outer-corner pieces.

Cliff overlays are placed as Things (background grid), so they do not block
movement by themselves.

## Rendering + Layers
- Draw order is defined in `renderer.nim` (`CliffDrawOrder`) to ensure edges
  render cleanly.
- Observation layers exist for each cliff piece
  (`ThingCliffEdgeNLayer`, etc.).

## Assets
Cliff assets are registered in `registry.nim` and map to sprite keys like:
- `cliff_edge_ew`, `cliff_edge_ns`
- `oriented/cliff_corner_in_ne`, `oriented/cliff_corner_out_sw`, etc.
