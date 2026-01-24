# Code Review: Unnecessary Indirection Analysis

This document analyzes helper functions and procs in the tribal-village codebase that may be candidates for inlining due to low usage or being simple wrappers.

## Summary

After analyzing all proc definitions in `src/` and `src/scripted/`, the codebase generally follows good practices with well-named helper functions. Most helpers are used multiple times and provide clear documentation value. However, several candidates for potential inlining or investigation were identified.

---

## Inlining Candidates (Single-Use or Wrapper Procs)

### High Priority - Clear Inlining Candidates

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `useAt` | ai_core.nim | 799 | 30 | **Inline** | Simple wrapper that just calls `actAt` with hardcoded verb 3. One-liner with no documentation value beyond the name. |
| `actOrMove` | options.nim | 28 | 14 | **Keep** | Despite being a small wrapper, it's used 14 times and encapsulates the act-or-move-towards pattern cleanly. |
| `fighterActOrMove` | fighter.nim | 63 | 9 | **Keep** | Same pattern as `actOrMove`, used 9 times within fighter options. Provides role-specific semantics. |

### Medium Priority - Investigate

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `sameTeam` | ai_core.nim | 375 | 5 | **Investigate** | Simple one-liner (`agentA.teamId == agentB.teamId`), but the name provides clear documentation. Keep unless profiling shows overhead. |
| `isAdjacent` | ai_core.nim | 715 | 40+ | **Keep** | Used extensively (40+ usages). Despite being simple (`chebyshevDist(a, b) <= 1`), provides excellent documentation value. |
| `clampToPlayable` | ai_core.nim | 150 | 4 | **Keep** | Only 4 usages but marked `{.inline.}` and provides clear boundary-clamping semantics. |
| `findAttackOpportunity` | ai_core.nim | 378 | 2 | **Investigate** | Only 2 usages (definition + 1 call in ai_defaults.nim:915). Complex enough to warrant a helper, but could be moved closer to usage. |

### Low Priority - Single-Use Helpers Worth Keeping

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `moveToNearestSmith` | ai_core.nim | 820 | 3 | **Keep** | Only 3 usages but encapsulates blacksmith-seeking logic clearly. |
| `ensureWater` | ai_core.nim | 962 | 2 | **Keep** | Only 2 usages but part of a consistent `ensure*` family providing clear intent. |
| `ensureHuntFood` | ai_core.nim | 1003 | 3 | **Keep** | Only 3 usages but maintains `ensure*` pattern consistency. |
| `updateGathererTask` | gatherer.nim | 30 | 2 | **Keep** | Only called from 1 location but complex enough (40 lines) to warrant separation. |
| `gathererTryBuildCamp` | gatherer.nim | 70 | 3 | **Keep** | Used 3 times within gatherer, encapsulates camp building logic. |

---

## Wrapper Procs Analysis

### Pattern: `canStart*` / `opt*` Pairs

The codebase uses a consistent pattern of `canStart*` predicates paired with `opt*` action functions. While some `canStart*` functions are very simple (single-line boolean expressions), they should be **kept** because:
1. They're used as function pointers in option arrays
2. The naming convention provides excellent self-documentation
3. Inlining would break the options system architecture

Examples that are simple but should remain:
- `canStartFighterBreakout` (line 121): Returns `fighterIsEnclosed(env, agent)`
- `shouldTerminateFighterBreakout` (line 125): Returns `not fighterIsEnclosed(env, agent)`
- `canStartFighterRetreat` (line 142): Returns `agent.hp * 2 < agent.maxHp`

### Pattern: Default Callbacks

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `optionsAlwaysCanStart` | options.nim | 3 | 3 | **Keep** | Used as default `canStart` callback, returns `true`. Essential for options system. |
| `optionsAlwaysTerminate` | options.nim | 7 | 65+ | **Keep** | Used as default `shouldTerminate` callback, returns `true`. Essential for options system. |

---

## Find* Helper Functions

The codebase has many `find*` helper functions. Usage analysis:

### Well-Used (Keep)

| Function | File | Line | Usage Count | Recommendation |
|----------|------|------|-------------|----------------|
| `findNearestThing` | ai_core.nim | 184 | 7 | Keep - core search utility |
| `findNearestThingSpiral` | ai_core.nim | 227 | 20+ | Keep - heavily used |
| `findNearestFriendlyThing` | ai_core.nim | 217 | 5 | Keep - core search utility |
| `findNearestFriendlyThingSpiral` | ai_core.nim | 286 | 18+ | Keep - heavily used |
| `findNearestWater` | ai_core.nim | 194 | 5 | Keep - used by spiral variant |
| `findNearestWaterSpiral` | ai_core.nim | 260 | 4 | Keep - part of search family |
| `findNearestEnemyBuilding` | options.nim | 145 | 8 | Keep - used across options |
| `findNearestPredator` | options.nim | 349 | 4 | Keep - clear intent |
| `findNearestGoblinStructure` | options.nim | 360 | 4 | Keep - clear intent |
| `findDropoffBuilding` | ai_core.nim | 830 | 3 | Keep - complex logic |

### Investigate (Lower Usage)

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `findNearestEnemyPresence` | options.nim | 159 | 3 | **Investigate** | Only 3 usages. Could potentially be inlined into callers. |
| `findNearestNeutralHub` | options.nim | 183 | 3 | **Investigate** | Only 3 usages, all in builder.nim. Consider moving to builder.nim if kept. |
| `findLanternFrontierCandidate` | options.nim | 199 | 3 | **Keep** | Complex search logic (20+ lines). |
| `findLanternGapCandidate` | options.nim | 220 | 2 | **Investigate** | Only 2 usages. Complex enough to keep but consider colocation. |
| `findFrozenEdgeCandidate` | options.nim | 244 | 2 | **Investigate** | Only 2 usages. |
| `findWallChokeCandidate` | options.nim | 257 | 2 | **Investigate** | Only 2 usages. |
| `findDoorChokeCandidate` | options.nim | 286 | 2 | **Investigate** | Only 2 usages. |
| `findFertileTarget` | gatherer.nim | 1 | 3 | **Keep** | Complex search logic. |
| `findIrrigationTarget` | options.nim | 323 | 3 | **Investigate** | Only 3 usages across 2 files. |
| `findNearestWaterEdge` | options.nim | 371 | 2 | **Investigate** | Only 2 usages. Wrapper around `findNearestWaterSpiral`. |

---

## Fighter-Specific Helpers

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `fighterIsEnclosed` | fighter.nim | 10 | 3 | **Keep** | Clear semantic meaning, used in can/terminate pair. |
| `fighterFindNearbyEnemy` | fighter.nim | 17 | 4 | **Keep** | Complex enemy-finding logic with caching. |
| `fighterSeesEnemyStructure` | fighter.nim | 50 | 3 | **Keep** | Clear predicate with observation-based logic. |

---

## Utility Helpers

### Math/Distance Helpers (Keep All)

| Function | File | Line | Usage Count | Recommendation |
|----------|------|------|-------------|----------------|
| `signi` | ai_core.nim | 117 | 7 | Keep - standard utility |
| `chebyshevDist` | ai_core.nim | 122 | 30+ | Keep - core distance metric |
| `vecToOrientation` | ai_core.nim | 103 | 5 | Keep - coordinate conversion |
| `neighborDirIndex` | ai_core.nim | 365 | 5 | Keep - direction encoding |

### State Management Helpers (Keep All)

| Function | File | Line | Usage Count | Recommendation |
|----------|------|------|-------------|----------------|
| `saveStateAndReturn` | ai_core.nim | 95 | 18+ | Keep - essential state management |
| `updateClosestSeen` | ai_core.nim | 127 | 11 | Keep - search state tracking |
| `getNextSpiralPoint` | ai_core.nim | 155 | 7 | Keep - spiral search algorithm |

---

## Non-Scripted File Analysis

### registry.nim

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `toSnakeCase` | registry.nim | 116 | 5 | **Keep** | Used for consistent naming across sprite keys. |

### colors.nim

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `applyActionTint` | colors.nim | 13 | 12 | **Keep** | Core tinting function used throughout step.nim. |
| `combinedTileTint` | colors.nim | 28 | 4 | **Keep** | Used in rendering and FFI. |

### combat.nim

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `killAgent` | combat.nim | 58 | 3 | **Keep** | Complex agent cleanup logic (60 lines). |
| `enforceZeroHpDeaths` | combat.nim | 164 | 3 | **Keep** | Clear semantic purpose for death enforcement. |

### actions.nim

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `applyUnitAttackTint` | actions.nim | 40 | 8 | **Keep** | Marked `{.inline.}`, used 8 times in step.nim. |

### roles.nim (Scripted)

| Function | File | Line | Usage Count | Recommendation | Rationale |
|----------|------|------|-------------|----------------|-----------|
| `stripPrefix` | roles.nim | 79 | 4 | **Investigate** | Only used in `shortBehaviorName`. Could be inlined. |
| `shortBehaviorName` | roles.nim | 86 | 2 | **Keep** | Provides clear name transformation. |
| `shuffleIds` | roles.nim | 320 | 2 | **Keep** | Standard shuffle algorithm. |
| `weightedPickIndex` | roles.nim | 331 | 4 | **Keep** | Used in evolution and role selection. |
| `resolveTierOrder` | roles.nim | 350 | 2 | **Keep** | Complex tier resolution logic. |
| `agentHasAnyItem` | options.nim | 73 | 7 | **Keep** | Used extensively in item checking. |

---

## Summary of Recommendations

### Inline (1)
- `useAt` (ai_core.nim:799) - Simple wrapper adding no value beyond `actAt` with verb 3

### Investigate Further (12)
- `findAttackOpportunity` - Consider moving closer to single usage
- `findNearestEnemyPresence` - Only 3 usages
- `findNearestNeutralHub` - Consider moving to builder.nim
- `findLanternGapCandidate` - Only 2 usages
- `findFrozenEdgeCandidate` - Only 2 usages
- `findWallChokeCandidate` - Only 2 usages
- `findDoorChokeCandidate` - Only 2 usages
- `findIrrigationTarget` - 3 usages across 2 files
- `findNearestWaterEdge` - Only 2 usages, simple wrapper
- `sameTeam` - One-liner, but name provides value
- `stripPrefix` - Only used within `shortBehaviorName`

### Keep (All Others)
The vast majority of helpers in this codebase are well-designed:
- Used multiple times
- Provide clear documentation through naming
- Part of consistent patterns (ensure*, find*Spiral, canStart*/opt*)
- Too complex to inline without hurting readability

---

## Architectural Observations

1. **Options Pattern**: The `canStart*`/`opt*`/`shouldTerminate*` pattern is well-structured. Even simple predicates should remain as separate functions due to their use as function pointers.

2. **Spiral Search Family**: The `find*Spiral` variants that wrap basic `find*` functions provide important state-aware search behavior. Keep as separate functions.

3. **ensure* Family**: `ensureWood`, `ensureStone`, `ensureGold`, `ensureWater`, `ensureWheat`, `ensureHuntFood` form a cohesive family. Even low-usage members should be kept for consistency.

4. **Inline Pragmas**: Functions marked with `{.inline.}` (like `clampToPlayable`, `applyUnitAttackTint`) are already optimized by the compiler.

5. **Nested Procs**: Several files use nested procs within larger functions (e.g., `heuristic` inside `findPath`). These are appropriately scoped and should remain nested.
