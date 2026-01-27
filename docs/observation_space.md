# Observation Space Reference

Date: 2026-01-19
Owner: Engineering / AI
Status: Draft

## Shape and layout
- **Spatial size:** `ObservationWidth` x `ObservationHeight` = **11 x 11**.
- **Radius:** `ObservationRadius` = 5 (centered on the agent).
- **Layers:** `ObservationLayers` = `ord(ObservationName.high) + 1` = **84**.
- **Type:** `uint8` values per layer cell.

The canonical enum lives in `src/types.nim` under `ObservationName`.

## Layer groups
The observation tensor is grouped into three conceptual blocks:

### 1) Terrain layers (one-hot)
Examples: `TerrainEmptyLayer`, `TerrainWaterLayer`, `TerrainBridgeLayer`,
`TerrainFertileLayer`, `TerrainRoadLayer`, plus the ramp directions
(`TerrainRampUp*` / `TerrainRampDown*`).

These are written as one-hot per tile via `updateObservations()` and
`rebuildObservations()` in `src/environment.nim`.

### 2) Thing layers (one-hot)
These correspond 1:1 to `ThingKind` entries such as agents, walls, resources,
animals, and buildings. Both blocking and background things are written to the
same layer bucket for that tile.

See the full list in `ObservationName` (e.g. `ThingAgentLayer`, `ThingWallLayer`,
`ThingGoblinHiveLayer`, `ThingMarketLayer`, etc.).

### 3) Meta layers
- `TeamLayer`: **team id + 1**, 0 means neutral/none.
- `AgentOrientationLayer`: **orientation + 1** for agents; 0 otherwise.
- `AgentUnitClassLayer`: **unit class + 1** for agents; 0 otherwise.
- `TintLayer`: action/combat tint codes (see below).
- `ObscuredLayer`: 1 if the target tile is above the observer elevation.

`ObscuredLayer` is applied in the FFI path (`src/ffi.nim`); when a tile is
obscured the other layers for that tile are zeroed.

## Action tint codes (TintLayer)
Defined in `src/types.nim`:
- `ActionTintNone` = 0
- `ActionTintAttackVillager` = 1
- `ActionTintAttackManAtArms` = 2
- `ActionTintAttackArcher` = 3
- `ActionTintAttackScout` = 4
- `ActionTintAttackKnight` = 5
- `ActionTintAttackMonk` = 6
- `ActionTintAttackBatteringRam` = 7
- `ActionTintAttackMangonel` = 8
- `ActionTintAttackBoat` = 9
- `ActionTintAttackTower` = 10
- `ActionTintAttackCastle` = 11
- `ActionTintAttackBonus` = 12 (generic bonus, rarely used)
- `ActionTintBonusArcher` = 13 (archer counter bonus vs infantry)
- `ActionTintBonusInfantry` = 14 (infantry counter bonus vs cavalry)
- `ActionTintBonusScout` = 15 (scout counter bonus vs archers)
- `ActionTintBonusKnight` = 16 (knight counter bonus vs archers)
- `ActionTintBonusBatteringRam` = 17 (battering ram siege bonus vs structures)
- `ActionTintBonusMangonel` = 18 (mangonel siege bonus vs structures)
- `ActionTintShield` = 20
- `ActionTintHealMonk` = 30
- `ActionTintHealBread` = 31
- `ActionTintMixed` = 200

These codes are written into the tint layer per world tile as events occur.

## Update mechanics
- `updateObservations()` performs incremental updates for a single world tile.
- `rebuildObservations()` reconstructs full observation buffers from scratch.
- The FFI entrypoints copy the buffer directly and apply the obscured mask.

Notes:
- The `layer` parameter on `updateObservations()` is legacy; the function
  rebuilds all layers for the tile by reading `env.terrain`, `env.grid`, and
  `env.backgroundGrid`.
- Inventory counts are not encoded in the spatial layers. Inventory update
  hooks exist but are currently no-ops, so inventories must be tracked outside
  the observation tensor.

If you change the observation layout (layers or meanings), update:
- `ObservationName` and related constants in `src/types.nim`.
- Any docs or README sections describing the observation space.
- Any Python wrappers that assume layer indices.
