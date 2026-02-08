# Performance Optimization Roadmap

> Consolidated from individual audit docs on 2026-02-08.
> See also: `PERF_OPTIMIZATION_TASKS.md` for the completed spatial optimization sprint (7/7 tasks done).

## Performance Baseline

| Date | Agents | Steps/sec | Per-agent AI | Notes |
|------|--------|-----------|-------------|-------|
| 2026-01-24 | 1006 | ~2.25 | - | Pre-optimization baseline |
| 2026-01-28 | 1006 | 733 → 1017 | - | After observation batch rebuild (+38%) |
| 2026-02-04 | 1006 | 76.4 (step only) | 10.98us | With stepTiming instrumentation |
| 2026-02-06 | 1006 | 146.0 | 5.86us | After spatial optimizations, AI profiled separately |

## Step() Subsystem Breakdown

Profiled with `-d:release -d:stepTiming`, 1006 agents over 1000 steps:

| Subsystem | Avg % | Notes |
|-----------|-------|-------|
| **tintObs** | 82-86% | Dominant hotpath, grows over time as trails accumulate |
| actions | 7-10% | Agent action processing |
| things | 2-3% | Thing updates (spawners, animals, buildings) |
| tumorDamage | 2% | Tumor damage calculation |
| tumors | 1% | Tumor processing |
| popRespawn | 0.5% | Respawn logic |
| preDeaths | 0.3% | Zero HP enforcement |
| auras | 0.1% | Aura processing |
| shields | 0.1% | Shield decay |
| actionTint | 0.1% | Action tint decay |

The tintObs subsystem grows 3-6x over a game as more tiles become "active" from agent movement trails (0.73ms at step 100-200, 2.45ms at step 900-1000).

---

## Completed Optimizations

### Observation Batch Rebuild (2026-01-28) DONE

Replaced incremental per-tile `updateObservations()` (called ~50+ times/step, each iterating all 1006 agents) with a single `rebuildObservations()` at end of step.

- **Before**: ~50,300 agent iterations/step (50 updates x 1006 agents), 65% of runtime
- **After**: 121,726 writes/step (1006 agents x 121 tiles), batch rebuild is 57% of runtime
- **Result**: 733 → 1017 steps/sec (+38%)
- **Key insight**: Doing more work in a single batch can be faster than less work spread across many calls due to cache locality and reduced function call overhead.

### Spatial Index Infrastructure (2026-02-02) DONE

Added `SpatialIndex` with cell-based partitioning for O(1) amortized spatial queries. See `src/spatial_index.nim`. Utilities added:
- `findNearestThingOfKindsSpatial()` - multi-kind queries
- `collectThingsInRangeSpatial()` - generic collection by kind
- `collectAgentsByClassInRange()` - unit-class filtering (tanks, monks)

### Predator Targeting with Spatial Queries DONE
Commit: `c4c693d` — Replaced O(radius^2) grid scans with `findNearestPredatorTargetSpatial()` for wolves and bears.

### Aura Processing Optimization DONE
Commit: `cea913f` — Added `env.tankUnits` and `env.monkUnits` collections maintained on spawn/death/class-change. Aura processing iterates only relevant units instead of all agents.

### Spawner Tumor Scan with Spatial Query DONE
Commit: `3ad7b56` — Replaced 11x11 grid scans with `countUnclaimedTumorsInRangeSpatial()`.

### Staggered AI Threat Map Updates DONE
Commits: `ae9e378`, `24431b2` — Threat map updates staggered by agent ID mod 5, reducing per-step cost by 5x. Decay also staggered to every 5 steps.

### Fighter Target Re-evaluation Optimization DONE
Commits: `e6cde2f`, `a3c91b5` — Increased `TargetSwapInterval` and added caching for `isThreateningAlly()` results.

### Combat Aura Damage Check with Spatial Query DONE
Commit: `1e9a8c9` — Replaced O(n) agent scan with `collectAgentsByClassInRange()` for tank aura damage reduction.

### stepRechargeMonkFaith DONE
Now iterates `env.monkUnits` instead of all agents, consistent with `stepApplyMonkAuras`.

### hasTeamLanternNear Spatial Query DONE
Now uses `collectThingsInRangeSpatial(env, pos, Lantern, 3, nearby)` for O(cells) lookups instead of iterating all lanterns. (Still allocates a local `seq[Thing]` per call — see open item below.)

### nearestFriendlyBuildingDistance DONE
Now uses `findNearestFriendlyThingSpatial` for O(cells) lookups instead of O(buildings).

### Pathfinding Cache Pre-allocation DONE
`PathfindingCache` added to `Controller` with pre-allocated arrays, generation counters for O(1) cache invalidation, binary heap for O(log n) open set, and 250-node exploration cap.

### Previously-O(n) Hotpaths Fixed
- `updateThreatMapFromVision`: Now O(visionRange^2) via spatial cells
- `findAttackOpportunity`: Now O(8 x maxRange) line scan
- `fighterFindNearbyEnemy`: Now O(enemyRadius^2) grid scan
- `needsPopCapHouse`: Now O(1) cached per-step
- `findNearestThing` / `findNearestThingSpiral`: Replaced with spatial index lookups

---

## Open Optimization Opportunities

### HIGH IMPACT

#### 1. Tint/Observation System (82-86% of step time)

The tint observation subsystem is the dominant hotpath and grows over time as agents leave trails. Options:
- Reduce trail persistence (faster decay) to shrink active tile set
- Batch tint updates less frequently (every N steps)
- Use SIMD for tint color calculations
- Delta-based updates: track entity positions, only update tint for moved entities (est. 40-60% reduction in tint processing since most agents don't move every step)

#### 2. Convert tempTowerRemovals to HashSet

**Location**: `step.nim` (spawner/tumor loops)

`tempTowerRemovals` is `seq[Thing]` — `in` operator performs O(n) linear scan. The `len > 0` guard mitigates empty-list cases, but converting to `HashSet[Thing]` provides O(1) lookups. Same applies to `tumorsToRemove`.

#### 3. Eliminate Duplicate Population Calculations

**Location**: `step.nim` (three separate locations)

Team population caps and counts are calculated 3 times per step:
1. Lines ~1066-1080: Into `env.stepTeamPopCaps` / `env.stepTeamPopCounts`
2. Lines ~2632-2640: Into local `teamPopCaps` (identical recalculation)
3. Lines ~3054-3060: Into local `teamPopCounts` (partial recalculation)

**Fix**: Remove duplicates 2 and 3, reuse `env.stepTeamPopCaps` / `env.stepTeamPopCounts`.

### MEDIUM IMPACT

#### 4. Heap Allocations in canEnterForMove

**Location**: `ai_core.nim` — called per neighbor per pathfind node (up to 8 x 250 = 2000 calls per pathfind)

```nim
var nearbyLanterns: seq[Thing] = @[]  # Heap allocation per call
collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns)
```

A pre-allocated `tempLanternSpacing` buffer exists on Environment but is not used here. Using it eliminates heap allocation per blocked lantern check.

#### 5. Path Result Allocation in findPath

**Location**: `ai_core.nim:~1066`

`findPath` still allocates `newSeq[IVec2](pathLen)` on success. Could reuse a pre-allocated buffer on `PathfindingCache`.

#### 6. Seq Allocations in getThreatsInRange

**Location**: `ai_core.nim:321`

`result = @[]` creates heap allocation. Consider using a pre-allocated arena buffer.

#### 7. Stagger Fog Reveals Across Agents

Currently all agents reveal fog every step. Could stagger to 1/N agents per step (similar to threat map update staggering). Reduces `revealTilesInRange` calls by factor of N.

#### 8. Cache nearestFriendlyBuildingDistance Per-Step

Add per-step cache on Controller to avoid redundant building distance calculations for same team/kind combinations.

### LOW IMPACT

#### 9. Inventory Hash Table → Array

**Location**: `items.nim`

`Table[ItemKey, int]` requires hash computation per access. Replace with `array[ItemKind, int]` for common items, keep Table fallback for rare thing-items. Est. 15-25% reduction in action processing time.

#### 10. String Allocations in ItemKey

`ItemKeyThing` and `ItemKeyOther` store strings, causing heap allocations. Consider interning strings or using enum IDs.

#### 11. Fertile Tile 17x17 Scan

**Location**: `ai_core.nim:~1013-1028` (`tryPlantOnFertile`)

Nested loop scans 289 tiles looking for fertile terrain. With ~50 gatherers, that's ~14,450 terrain checks per step. Consider a spatial index for fertile tiles or caching fertile positions per team.

#### 12. Seq Allocations in Hot Loops

**Location**: `step.nim` — tumor processing, tower removal lists

```nim
var newTumorsToSpawn: seq[Thing] = @[]
var tumorsToProcess: seq[Thing] = @[]
```

Pre-allocate with `reserve(32)` to avoid reallocs. Est. 2-5% reduction.

#### 13. Redundant isValidPos Checks

Many functions check `isValidPos` multiple times for the same position. Trust callers when position is already validated; use unchecked variants for internal calls.

#### 14. Animal Movement Allocation

Corner target selection allocates `seq[IVec2]` candidates. Use `array[4, IVec2]` since there are only 4 corners.

#### 15. Builder getMoveTowards Redundancy

Builder role calls `getMoveTowards` twice in some paths. Could combine or cache result.

---

## Profiling Infrastructure

The codebase has good profiling support:

- **Step timing**: Compile with `-d:release -d:stepTiming`, set `TV_STEP_TIMING=100` (start step) and `TV_STEP_TIMING_WINDOW=50` (window)
- **AI profiling**: `scripts/profile_ai.nim` — per-agent AI tick breakdown
- **Nim profiler**: `nim r --profiler:on --stackTrace:on scripts/profile_env.nim`
- **Benchmarking**: `make benchmark` for steps/sec + regression detection
- **Perf baseline**: `nim c -r -d:release --path:src scripts/perf_baseline.nim --steps 1000`
- **Spatial auto-tune**: Compile with `-d:spatialAutoTune`

---

## Recommended Priority Order

1. **Tint system optimization** — 82-86% of step time, highest ROI
2. **Eliminate duplicate pop calculations** — easy win, remove redundant iterations
3. **Convert tempTowerRemovals to HashSet** — easy, O(1) vs O(n)
4. **Pre-allocated buffers for canEnterForMove** — reduces GC pressure in pathfinding
5. **Path result buffer** — eliminates per-pathfind allocation
6. **Stagger fog reveals** — reduces per-step O(agents) work
7. **Inventory array conversion** — medium effort, medium payoff

---

## Source Documents

This roadmap was consolidated from:
- `docs/perf_audit_hotloops.md` (2026-02-04) — Hotloop audit of step.nim and ai_core.nim
- `docs/perf-audit-pathfinding-movement.md` (2026-02-06) — Pathfinding and movement overhead audit
- `docs/analysis/performance_analysis.md` (2026-01-28) — General performance analysis
- `docs/analysis/performance_scaling_1000_agents.md` (2026-01-24) — 1000+ agent scaling investigation
- `docs/analysis/perf-improvements.md` (2026-01-28) — Observation batch rebuild improvement
- `docs/analysis/step_hotpath_profile.md` (2026-02-04) — Step hotpath profile analysis
