# Observation Layers and Updates

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document describes the agent observation tensor: which layers exist, how they are encoded,
and how updates are applied as the world changes.

Key implementation files:
- `src/types.nim`
- `src/environment.nim`
- `src/step.nim`
- `src/colors.nim`
- `src/ffi.nim`

## Observation Tensor Shape
- `ObservationWidth` x `ObservationHeight` is **11 x 11**.
- Observations are stored as:
  `env.observations[agentId][layer][x][y]`.
- `ObservationLayers` is derived from `ObservationName` in `src/types.nim`.

## Layer Groups
Layers are a mix of one-hot and numeric channels:

1. **Terrain layers**
   - One layer per TerrainType.
   - Written at `TerrainLayerStart + ord(terrain)`.

2. **Thing layers**
   - One layer per ThingKind.
   - Written at `ThingLayerStart + ord(thing.kind)`.
   - Both blocking (`env.grid`) and background (`env.backgroundGrid`) Things contribute.

3. **Team and Agent metadata**
   - `TeamLayer`: team id + 1, 0 means none/neutral.
   - `AgentOrientationLayer`: orientation enum + 1 for agents, else 0.
   - `AgentUnitClassLayer`: unit class enum + 1 for agents, else 0.

4. **Tint and Obscured**
   - `TintLayer`: action/combat tint codes (see `src/colors.nim`).
   - `ObscuredLayer`: set to 1 in FFI when target tile is above the observer elevation.
     All other layers at that tile are zeroed in the FFI view.

## Update Strategy
Observations are updated incrementally whenever a world tile changes.

- `updateObservations` in `src/environment.nim` re-reads terrain and Things for a world tile
  and writes the full set of layers for any agents whose observation window includes it.
- The `layer` and `value` parameters are legacy; the function always rebuilds all layers for
  that tile to keep updates consistent.
- Full refresh is available via `rebuildObservations` when needed (e.g., after reset).

## Action Tint Encoding
Combat and healing events write into `env.actionTintCode` and are copied to `TintLayer`:
- Attack, heal, shield, and bonus-hit codes are defined in `src/types.nim`.
- `applyActionTint` in `src/colors.nim` keeps `TintLayer` in sync with visual effects.

## Inventory Observations
Inventory counts are not encoded in the spatial observation layers. The inventory update hooks
(`updateAgentInventoryObs`) are currently no-ops, so inventories must be tracked separately.

## Adding New Terrain or Things
When adding a new TerrainType or ThingKind:
1. Add the enum entry in `src/terrain.nim` or `src/types.nim`.
2. Add the corresponding ObservationName layer in `src/types.nim`.
3. Ensure any rendering or interaction logic places the Thing in `env.grid` or
   `env.backgroundGrid` appropriately.

Observation layers are derived from the enums, so keeping the enums consistent is critical.
