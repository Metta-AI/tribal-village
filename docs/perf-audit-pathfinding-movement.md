# Performance Audit: Pathfinding and Movement Calculation Overhead

**Issue**: tv-69rq3n
**Date**: 2026-02-06
**Auditor**: polecat/cheedo

## Executive Summary

AI decision-making consumes **86% of tick time** (5.9ms average), with pathfinding and movement being core contributors. The existing implementation is well-optimized with generation counters, spatial indexing, and path caching. This audit identifies remaining overhead sources and optimization opportunities.

## Profiling Results

```
=== AI TICK PERFORMANCE (1006 agents, 8 teams) ===
AI (getActions):  avg=5.900ms  max=11.487ms  (86.1% of tick)
Sim (env.step):   avg=0.949ms  max=1.891ms   (13.9% of tick)

Steps/second: 146.0
Per-agent AI: 5.86 microseconds
```

## Architecture Analysis

### A* Pathfinding (`findPath` in ai_core.nim:978-1102)

**Well-optimized:**
- Generation counters for O(1) cache invalidation (vs O(map_size) clearing)
- Pre-allocated PathfindingCache avoids per-call heap allocations
- Binary heap for O(log n) open set operations
- 250-node exploration cap bounds worst-case cost

**Overhead sources:**
| Location | Issue | Impact |
|----------|-------|--------|
| Line 1066 | `newSeq[IVec2](pathLen)` on success | Heap alloc per pathfind |
| Line 1076 | `canEnterForMove` per neighbor | Up to 8 calls × 250 nodes |

### Movement Calculation (`moveTo` in ai_core.nim:1202-1275)

**Well-optimized:**
- Path caching in `state.plannedPath` - reuses paths when target unchanged
- Distance threshold: A* only for dist >= 6, greedy for short distances
- Blocked target tracking avoids repeated pathfinding to unreachable targets

**Overhead sources:**
| Location | Issue | Impact |
|----------|-------|--------|
| canEnterForMove | Allocates `seq[Thing]` for lantern spacing check | 1-3 heap allocs per blocked tile |
| getMoveTowards | Called multiple times for builder role | Redundant calculations |

### Passability Checking (`canEnterForMove` in ai_core.nim:867-917)

**Optimization opportunity:**
```nim
# Current (allocates on heap):
template spacingOk(nextPos: IVec2): bool =
  var nearbyLanterns: seq[Thing] = @[]  # HEAP ALLOCATION
  collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns)
```

This is called when a lantern blocks the path. In maps with many lanterns, this creates garbage collection pressure.

## Previously Optimized Hotpaths (Reference)

These were O(n) but have been fixed:
- `updateThreatMapFromVision`: Now O(visionRange²) via spatial cells
- `findAttackOpportunity`: Now O(8×maxRange) line scan
- `fighterFindNearbyEnemy`: Now O(enemyRadius²) grid scan
- `needsPopCapHouse`: Now O(1) cached per-step

## Remaining O(n) Hotpaths

| Function | Location | Current Complexity | Notes |
|----------|----------|-------------------|-------|
| `nearestFriendlyBuildingDistance` | ai_core.nim:676 | O(buildings) per call | Uses `thingsByKind` iteration |
| `hasTeamLanternNear` | ai_core.nim:1104 | O(lanterns in range) | Uses spatial, but allocs seq |
| `revealTilesInRange` | ai_core.nim:252 | O(visionRadius²) per agent | Called every step per agent |

## Recommendations

### High Impact / Low Effort

1. **Use existing lantern spacing buffer in canEnterForMove**

   The buffer already exists (types.nim:1269, used in step.nim:1302), but `canEnterForMove` in ai_core.nim allocates locally:
   ```nim
   # Current in ai_core.nim (allocates):
   var nearbyLanterns: seq[Thing] = @[]
   collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns)

   # Should use existing buffer like step.nim does:
   env.tempLanternSpacing.setLen(0)
   collectThingsInRangeSpatial(env, nextPos, Lantern, 2, env.tempLanternSpacing)
   ```
   **Impact**: Eliminates heap allocation per blocked lantern check in AI pathfinding

2. **Add path result buffer to PathfindingCache**
   ```nim
   # Instead of allocating new seq each pathfind:
   pathResult*: seq[IVec2]  # Pre-allocated, resized as needed
   ```
   **Impact**: Eliminates heap allocation per successful pathfind

### Medium Impact / Medium Effort

3. **Stagger fog reveals across agents**
   Currently all agents reveal fog every step. Could stagger to 1/N agents per step (similar to threat map updates).
   **Impact**: Reduces `revealTilesInRange` calls by factor of N

4. **Cache nearestFriendlyBuildingDistance results per-step**
   ```nim
   # In Controller, add per-step cache:
   nearestBuildingCache*: array[MapRoomObjectsTeams, array[ThingKind, tuple[pos: IVec2, dist: int, step: int]]]
   ```
   **Impact**: Avoids redundant building distance calculations

### Lower Priority

5. **Optimize getMoveTowards for builder role**
   Builder role calls getMoveTowards twice in some paths. Could combine or cache result.

6. **Consider hierarchical pathfinding**
   For very long paths (> 50 tiles), pre-compute region connectivity graph. Not currently needed given 250-node cap.

## Conclusion

The pathfinding system is already well-architected with several key optimizations in place. The remaining overhead is primarily from:
1. Small heap allocations in hot paths (lantern checking, path results)
2. O(n) building distance lookups that could be cached

Implementing recommendations 1-2 would reduce GC pressure. Recommendations 3-4 would reduce CPU time for large unit counts.

## Files Analyzed

- `src/scripted/ai_core.nim` - Core pathfinding and movement
- `src/scripted/ai_types.nim` - PathfindingCache structure
- `src/scripted/ai_defaults.nim` - decideAction entry point
- `src/spatial_index.nim` - Spatial query system
- `scripts/profile_ai.nim` - Profiling infrastructure
