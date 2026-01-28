# Dead Code Review - tribal-village

**Generated:** 2026-01-24
**Updated:** 2026-01-24
**Scope:** src/*.nim, src/scripted/*.nim, tests/*.nim

This document catalogs potentially dead code, unused exports, and vestigial functionality.

---

## Summary

After thorough analysis of the codebase, the overwhelming majority of exported symbols are actively used. The codebase is well-organized with most exports serving clear purposes across module boundaries.

### Dead Code Removed (2026-01-24)

The following dead code was identified and removed:

1. **Unused Layer Alias Constants** (types.nim) - 11 constants removed:
   - `WallLayer`, `MagmaLayer`, `altarLayer`, `CliffLayer`
   - `AgentInventoryStoneLayer`, `AgentInventoryWaterLayer`, `AgentInventoryLanternLayer`
   - `AgentInventoryBreadLayer`, `AgentInventoryMeatLayer`, `AgentInventoryFishLayer`, `AgentInventoryPlantLayer`

2. **Dead Import** (tests/domain_economy_buildings.nim):
   - Removed `import balance` - the module doesn't exist

### Dead Code Removed (2026-01-27)

3. **Vestigial AgentInventory*Layer aliases and call sites** (tv-lvcn):
   - `LegacyObsLayer` alias removed - only served as base for inventory aliases
   - `AgentInventoryGoldLayer`, `AgentInventoryBarLayer`, `AgentInventoryWheatLayer`,
     `AgentInventoryWoodLayer`, `AgentInventorySpearLayer`, `AgentInventoryArmorLayer` aliases removed
   - All call sites using these aliases removed from step.nim and combat.nim
   - **Rationale**: `updateObservations` is a no-op (observations rebuilt in batch at step end).
     All these aliases pointed to the same layer (`ThingAgentLayer`), making the calls
     semantically meaningless. The calls added execution overhead without any effect.

### Layer Aliases Retained (types.nim)

| Item | File | Status | Evidence |
|------|------|--------|----------|
| `AgentLayer` | src/types.nim | Kept | Used in step.nim and combat.nim for agent position updates |
| `altarHeartsLayer` | src/types.nim | Kept | Used in step.nim for altar heart updates |

---

### 2. Structure Character Constants (terrain.nim, lines 46-53)

| Item | File | Line | Evidence | Confidence | Risks |
|------|------|------|----------|------------|-------|
| `StructureTownCenterChar` | src/terrain.nim | 46 | Used in spawn.nim:1064 | Used | N/A |
| `StructureBarracksChar` | src/terrain.nim | 47 | Used in spawn.nim:1070 | Used | N/A |
| `StructureArcheryRangeChar` | src/terrain.nim | 48 | Used in spawn.nim:1076 | Used | N/A |
| `StructureStableChar` | src/terrain.nim | 49 | Used in spawn.nim:1082 | Used | N/A |
| `StructureSiegeWorkshopChar` | src/terrain.nim | 50 | Used in spawn.nim:1088 | Used | N/A |
| `StructureMarketChar` | src/terrain.nim | 51 | Used in spawn.nim:1094 | Used | N/A |
| `StructureDockChar` | src/terrain.nim | 52 | Used in spawn.nim:1100 | Used | N/A |
| `StructureUniversityChar` | src/terrain.nim | 53 | Used in spawn.nim:1106 | Used | N/A |

**Analysis:** All these constants are actively used. No dead code here.

---

### 3. Biome Configuration Constants (terrain.nim, lines 85-131)

| Item | File | Line | Evidence | Confidence | Risks |
|------|------|------|----------|------------|-------|
| `UseBiomeTerrain` | src/terrain.nim | 85 | Configuration flag, controls biome terrain behavior | Used | N/A |
| `UseBiomeZones` | src/terrain.nim | 95 | Configuration flag, used in terrain generation | Used | N/A |
| `UseDungeonZones` | src/terrain.nim | 96 | Configuration flag, used in terrain generation | Used | N/A |
| `UseLegacyTreeClusters` | src/terrain.nim | 97 | Configuration flag, used in spawn.nim | Used | N/A |
| `UseTreeOases` | src/terrain.nim | 98 | Configuration flag, used in spawn.nim | Used | N/A |

**Analysis:** These are configuration toggles that control behavior at compile time. All appear to be referenced.

---

### 4. Terrain Type Aliases (terrain.nim)

**Dead Code Removed (2026-01-27):**
- `TerrainWater`, `TerrainBridge`, `TerrainFertile` - Removed, never used outside definitions

**Aliases Retained:**

| Item | File | Evidence | Status |
|------|------|----------|--------|
| `TerrainEmpty` | src/terrain.nim | Used in tests/ai_harness.nim, tests/test_utils.nim, spawn.nim | Kept |
| `TerrainRoad` | src/terrain.nim | Used in ai_defaults.nim (10+), options.nim, fighter.nim, builder.nim | Kept |
| `TerrainGrass` | src/terrain.nim | Used in spawn.nim (ResourceGround, TreeGround sets) | Kept |
| `TerrainDune` | src/terrain.nim | Used in spawn.nim, terrain.nim (biome generation) | Kept |
| `TerrainSand` | src/terrain.nim | Used in spawn.nim, terrain.nim (biome generation) | Kept |
| `TerrainSnow` | src/terrain.nim | Used in spawn.nim (ResourceGround set) | Kept |
| `TerrainMud` | src/terrain.nim | Used in spawn.nim (ResourceGround, TreeGround sets) | Kept |

**Analysis:** The remaining aliases are actively used throughout the codebase for terrain sets and AI logic.

---

### 5. Exported Procs - Usage Verification

All major exported procs were verified as being used:

| Proc | File | Used In |
|------|------|---------|
| `nowSeconds` | common.nim | tribal_village.nim, spawn.nim, agent_control.nim |
| `logicalMousePos` | common.nim | tribal_village.nim (multiple) |
| `orientationToVec` | common.nim | step.nim (10+ uses), ai_defaults.nim |
| `encodeAction` | common.nim | test_utils.nim, step.nim |
| `ivec2` | common.nim | Throughout codebase |
| `generateDfViewAssets` | tileset.nim | tribal_village.nim |
| `initRand`, `next`, `randIntInclusive`, `randChance`, `sample` | entropy.nim | Throughout codebase |
| `newEnvironment` | spawn.nim | tests, tribal_village.nim |
| `step`, `reset` | step.nim | FFI, tests, main |
| `decideAction`, `updateController` | ai_defaults.nim | agent_control.nim, tests |
| `newController` | ai_core.nim | agent_control.nim, tests |
| All biome mask builders | biome.nim | terrain.nim, spawn.nim |
| All renderer procs | renderer.nim | tribal_village.nim |
| All registry procs | registry.nim | Throughout codebase |

---

### 6. Types Verification

All exported types were verified as being used:

| Type | File | Usage |
|------|------|-------|
| `Environment` | types.nim | Central game state, used everywhere |
| `Thing` | types.nim | Entity type, used everywhere |
| `Controller` | ai_core.nim | AI controller, used in agent_control |
| `OptionDef` | options.nim | Behavior options, used in gatherer/builder/fighter |
| `RoleCatalog`, `RoleDef`, `BehaviorDef` | roles.nim | Evolution system |
| `EvolutionConfig` | evolution.nim | Evolution configuration |
| `CraftRecipe` | items.nim | Crafting system |
| `ZoneRect` | terrain.nim | Zone generation |
| `ReplayWriter` | replay_writer.nim | Replay system |
| `FooterButton`, `FooterButtonKind` | renderer.nim | UI system |
| `TempleInteraction`, `TempleHybridRequest` | types.nim | Temple hybridization |
| `TerritoryScore` | types.nim | Scoring system |

---

### 7. Potentially Vestigial Code (Low Confidence)

| Item | File | Line | Evidence | Confidence | Risks |
|------|------|------|----------|------------|-------|
| `shortBehaviorName` | roles.nim | 86 | Only used internally in `generateRoleName` | Likely Used | Low - internal helper |

---

## Recommendations

### Safe to Remove (if desired)

None identified with high confidence. The codebase is clean.

### Investigate Further

1. **Layer Aliases (types.nim:260-279)**: Consider whether all the `AgentInventory*Layer` aliases are needed, or if they're vestigial from an earlier observation system design. Currently they all point to the same base layer.

2. ~~**Terrain Type Aliases (terrain.nim:135-143)**~~ - **RESOLVED (2026-01-27)**: Investigated. Removed `TerrainWater`, `TerrainBridge`, `TerrainFertile` (unused). Kept all others (actively used in spawn.nim, AI logic, tests).

### Keep As-Is

1. **Configuration Constants**: All biome/terrain config constants serve as tuning parameters.

2. **FFI Interface**: All FFI procs are exported for the Python bindings and should be kept.

3. **Test Utilities**: The test_utils.nim procs are test helpers and actively used.

---

## Notes

- The codebase uses Nim's module include system extensively (e.g., `include "combat"` in environment.nim), which makes some procs appear local when they're actually part of a larger compilation unit.

- Many exported symbols in `types.nim` serve as the public API for the game engine and are intentionally exported even if only used in a few places.

- The FFI module (`ffi.nim`) exports procs for Python/C interop that may not be called within the Nim codebase but are essential for the library interface.

---

## Methodology

1. Used `grep` to find all exported symbols (marked with `*`)
2. Searched for usage of each symbol across the entire codebase
3. Verified proc calls, type instantiations, and constant references
4. Cross-referenced includes to understand module boundaries
5. Checked test files for additional usage patterns
