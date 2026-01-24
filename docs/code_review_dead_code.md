# Dead Code Review - tribal-village

**Generated:** 2026-01-24
**Scope:** src/*.nim, src/scripted/*.nim, tests/*.nim

This document catalogs potentially dead code, unused exports, and vestigial functionality.

---

## Summary

After thorough analysis of the codebase, the overwhelming majority of exported symbols are actively used. The codebase is well-organized with most exports serving clear purposes across module boundaries.

### Categories of Findings

1. **Legacy/Deprecated Layer Aliases** - Old names kept for backward compatibility
2. **Configuration Constants** - Exported but only used as configuration toggles
3. **Structure Character Constants** - Some exported but only used within terrain.nim
4. **Potentially Unused Procs** - Very few found

---

## Findings

### 1. Legacy Layer Alias Constants (types.nim, lines 260-279)

| Item | File | Line | Evidence | Confidence | Risks |
|------|------|------|----------|------------|-------|
| `LegacyObsLayer` | src/types.nim | 260 | Used only as alias base for AgentInventory*Layer constants | Investigate | Low - backward compat |
| `AgentLayer` | src/types.nim | 261 | Alias for ThingAgentLayer, not directly referenced elsewhere | Investigate | Low - clarity helper |
| `WallLayer` | src/types.nim | 262 | Alias for ThingWallLayer, not directly referenced elsewhere | Investigate | Low - clarity helper |
| `MagmaLayer` | src/types.nim | 263 | Alias for ThingMagmaLayer, not directly referenced elsewhere | Investigate | Low - clarity helper |
| `CliffLayer` | src/types.nim | 266 | Alias for ThingCliffEdgeNLayer, not directly referenced elsewhere | Investigate | Low - clarity helper |
| `AgentInventoryGoldLayer` | src/types.nim | 267 | Points to LegacyObsLayer, used in step.nim:745 | Used | N/A |
| `AgentInventoryStoneLayer` | src/types.nim | 268 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryBarLayer` | src/types.nim | 269 | Points to LegacyObsLayer, used in step.nim:746 | Used | N/A |
| `AgentInventoryWaterLayer` | src/types.nim | 270 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryWheatLayer` | src/types.nim | 271 | Points to LegacyObsLayer, used in step.nim:1126 | Used | N/A |
| `AgentInventoryWoodLayer` | src/types.nim | 272 | Points to LegacyObsLayer, used in step.nim:1116 | Used | N/A |
| `AgentInventorySpearLayer` | src/types.nim | 273 | Points to LegacyObsLayer, used in step.nim:496,543 | Used | N/A |
| `AgentInventoryLanternLayer` | src/types.nim | 274 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryArmorLayer` | src/types.nim | 275 | Points to LegacyObsLayer, used in combat.nim:146 | Used | N/A |
| `AgentInventoryBreadLayer` | src/types.nim | 276 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryMeatLayer` | src/types.nim | 277 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryFishLayer` | src/types.nim | 278 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |
| `AgentInventoryPlantLayer` | src/types.nim | 279 | Alias to LegacyObsLayer, no direct usage | Investigate | Low |

**Analysis:** These are backward-compatibility aliases. Many point to a generic layer constant rather than individual layers. Some (`AgentInventoryStoneLayer`, `AgentInventoryWaterLayer`, etc.) are exported but never directly referenced - they may exist for documentation or future use.

**Risk of Removal:** Low - These are compile-time constants. Removing unused aliases would have no runtime impact but could break external code that references them.

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

### 4. Terrain Type Aliases (terrain.nim, lines 135-143)

| Item | File | Line | Evidence | Confidence | Risks |
|------|------|------|----------|------------|-------|
| `TerrainEmpty` | src/terrain.nim | 135 | Alias for TerrainType.Empty, used in tests | Used | N/A |
| `TerrainWater` | src/terrain.nim | 136 | Alias for TerrainType.Water | Investigate | Low |
| `TerrainBridge` | src/terrain.nim | 137 | Alias for TerrainType.Bridge | Investigate | Low |
| `TerrainFertile` | src/terrain.nim | 138 | Alias for TerrainType.Fertile | Investigate | Low |
| `TerrainRoad` | src/terrain.nim | 139 | Alias for TerrainType.Road | Investigate | Low |
| `TerrainGrass` | src/terrain.nim | 140 | Alias for TerrainType.Grass | Investigate | Low |
| `TerrainDune` | src/terrain.nim | 141 | Alias for TerrainType.Dune | Investigate | Low |
| `TerrainSand` | src/terrain.nim | 142 | Alias for TerrainType.Sand | Investigate | Low |
| `TerrainSnow` | src/terrain.nim | 143 | Alias for TerrainType.Snow | Investigate | Low |

**Analysis:** These are convenience aliases for enum values. The code mostly uses the qualified names (e.g., `TerrainType.Water` or just `Water`). These may be for external API consumers.

**Risk of Removal:** Low - Compile-time aliases only.

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

2. **Terrain Type Aliases (terrain.nim:135-143)**: These appear to be convenience exports. If no external code uses them, they could be removed.

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
