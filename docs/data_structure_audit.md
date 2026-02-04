# Data Structure Audit: Spatial Indexing, Entity Lookups, Observation Building

**Date**: 2026-02-04
**Auditor**: tv-wisp-j74qd (Polecat/Slit)
**Scope**: Analyze spatial indexing, entity lookups, and observation building for efficiency improvements

---

## Executive Summary

The codebase has a well-designed spatial index (`spatial_index.nim`) with O(1) amortized queries. However, several hotpath functions bypass the spatial index and iterate `thingsByKind[]` globally, creating O(n) bottlenecks. The primary optimization opportunities are:

1. **High Impact**: Replace `nearestFriendlyBuildingDistance` with spatial query (~200 buildings/call)
2. **High Impact**: Replace `hasTeamLanternNear` with spatial query (~50 lanterns/call)
3. **Medium Impact**: Replace `hasNearbyFood` with spatial query in gatherer logic
4. **Low Impact**: Cache `teamMask` on Thing objects to avoid per-entity `getTeamMask()` calls

---

## 1. Spatial Index Architecture

### Current Implementation (`spatial_index.nim`)

**Strengths**:
- Cell-based partitioning: 16x16 tile cells covering 305x191 map (20x12 grid = 240 cells)
- Pre-computed lookup tables (`DistToCellRadius16[]`) for O(1) distance-to-cell conversion
- Per-kind indices (`kindCells[ThingKind][cx][cy]`) for filtered queries without scanning all entities
- Optional adaptive tuning (`-d:spatialAutoTune`) for dynamic cell resizing based on density
- Swap-and-pop removal for O(1) entity removal from cells

**Data Structure** (types.nim:620-630):
```nim
SpatialIndex* = object
  cells*: array[SpatialCellsX, array[SpatialCellsY, SpatialCell]]
  kindCells*: array[ThingKind, array[SpatialCellsX, array[SpatialCellsY, seq[Thing]]]]
```

**Query Functions Available**:
| Function | Complexity | Use Case |
|----------|-----------|----------|
| `findNearestThingSpatial` | O(cells in radius) | Nearest single entity |
| `findNearestFriendlyThingSpatial` | O(cells in radius) | Nearest team-owned entity |
| `findNearestEnemyAgentSpatial` | O(cells in radius) | Nearest enemy agent |
| `findNearestEnemyBuildingSpatial` | O(cells in radius) | Nearest enemy structure |
| `collectEnemiesInRangeSpatial` | O(cells in radius) | All enemies in range |
| `collectThingsInRangeSpatial` | O(cells in radius) | All entities of type in range |

---

## 2. Identified Inefficiencies

### 2.1 HIGH: `nearestFriendlyBuildingDistance` (ai_core.nim:595-604)

**Problem**: Iterates ALL buildings of specified types globally.

```nim
proc nearestFriendlyBuildingDistance*(env: Environment, teamId: int,
                                      kinds: openArray[ThingKind], pos: IVec2): int =
  result = int.high
  for kind in kinds:
    for thing in env.thingsByKind[kind]:  # O(count[kind]) per kind
      if thing.isNil or thing.teamId != teamId:
        continue
      result = min(result, int(chebyshevDist(thing.pos, pos)))
```

**Call Sites**:
- `ai_defaults.nim:133` - Building placement checks
- `ai_defaults.nim:149` - Building spacing validation
- `builder.nim:241` - Mill placement near resources
- `builder.nim:285` - Resource camp placement

**Impact**: With ~50-200 buildings per type, this is O(k * n) where k = number of kinds checked.

**Fix**: Use `findNearestFriendlyThingSpatial` for each kind with appropriate maxDist:

```nim
proc nearestFriendlyBuildingDistance*(env: Environment, teamId: int,
                                      kinds: openArray[ThingKind], pos: IVec2): int =
  result = int.high
  for kind in kinds:
    let nearest = findNearestFriendlyThingSpatial(env, pos, teamId, kind, result)
    if not nearest.isNil:
      result = min(result, int(chebyshevDist(nearest.pos, pos)))
```

---

### 2.2 HIGH: `hasTeamLanternNear` (ai_core.nim:991-999)

**Problem**: Iterates ALL lanterns to find one within 3 tiles.

```nim
proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.thingsByKind[Lantern]:  # O(all lanterns)
    if thing.isNil or not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y)) < 3'i32:
      return true
  false
```

**Impact**: With ~50-100 lanterns, checking 50-100 entities when spatial query would check ~1-2 cells.

**Fix**: Use spatial index with radius 3:

```nim
proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  var nearby: seq[Thing] = @[]
  collectThingsInRangeSpatial(env, pos, Lantern, 3, nearby)
  for thing in nearby:
    if thing.lanternHealthy and thing.teamId == teamId:
      return true
  false
```

---

### 2.3 MEDIUM: `hasNearbyFood` (gatherer.nim:66-71)

**Problem**: Iterates ALL food things instead of using spatial query.

```nim
proc hasNearbyFood(env: Environment, pos: IVec2, radius: int): bool =
  for kind in FoodKinds:
    for thing in env.thingsByKind[kind]:  # O(all food of each kind)
      if thing.isNil:
        continue
      if chebyshevDist(thing.pos, pos) <= radius:
        return true
  false
```

**Impact**: With hundreds of food items, this iterates them all.

**Fix**: Use `findNearestThingOfKindsSpatial`:

```nim
proc hasNearbyFood(env: Environment, pos: IVec2, radius: int): bool =
  let nearest = findNearestThingOfKindsSpatial(env, pos, FoodKinds, radius)
  not nearest.isNil
```

---

### 2.4 MEDIUM: `fighterSeesEnemyStructureUncached` (fighter.nim:230-241)

**Problem**: Iterates building kinds via thingsByKind within vision radius.

```nim
proc fighterSeesEnemyStructureUncached(env: Environment, agent: Thing): bool =
  let teamId = getTeamId(agent)
  let radius = ObservationRadius.int32
  for kind in [Wall, Outpost, GuardTower, Castle, TownCenter, Monastery]:
    for thing in env.thingsByKind[kind]:  # O(all buildings of kind)
      if thing.isNil or thing.teamId == teamId or thing.teamId < 0:
        continue
      if chebyshevDist(agent.pos, thing.pos) <= radius:
        return true
  false
```

**Note**: This is already cached per-step (`fighterEnemyStructureCacheStep`), mitigating the impact.

**Fix**: Use `findNearestEnemyBuildingSpatial` with `ObservationRadius`:

```nim
proc fighterSeesEnemyStructureUncached(env: Environment, agent: Thing): bool =
  let teamId = getTeamId(agent)
  let building = findNearestEnemyBuildingSpatial(env, agent.pos, teamId, ObservationRadius.int)
  not building.isNil
```

---

### 2.5 LOW: `getTeamMask` Called Twice Per Entity

**Problem**: In team-filtered queries, `getTeamMask(teamId)` is pre-computed but `getTeamMask(thing.teamId)` is called for each entity (spatial_index.nim:565):

```nim
let teamMask = getTeamMask(teamId)  # Pre-computed
forEachInRadius(env, pos, kind, maxDist, thing):
  if (getTeamMask(thing.teamId) and teamMask) == 0:  # Called per entity
    continue
```

**Impact**: `getTeamMask` is a simple lookup (`1 shl teamId`), so overhead is minimal. However, caching on Thing would eliminate the call entirely.

**Potential Fix**: Add `teamMask` field to Thing, updated when `teamId` changes:
```nim
Thing* = ref object
  teamId*: int
  teamMask*: int  # = 1 shl teamId, or 0 if teamId < 0
```

---

### 2.6 LOW: `forEachInRadius` Loop Bounds

**Problem**: The nested loop checks `abs(dx) > searchRadius` inside the loop (spatial_index.nim:497-500):

```nim
for dx in -maxRadius .. maxRadius:
  if abs(dx) > searchRadius: continue  # Redundant check
  for dy in -maxRadius .. maxRadius:
    if abs(dy) > searchRadius: continue  # Redundant check
```

**Note**: `searchRadius` can shrink during the loop (early-exit optimization), so this check is intentional.

**Impact**: Low - the check is simple and enables the early-exit optimization.

---

## 3. Entity Lookup Patterns Summary

| Pattern | Current | Optimal | Files |
|---------|---------|---------|-------|
| Find nearest building (any team) | `thingsByKind` O(n) | Spatial O(cells) | ai_core.nim |
| Find nearest friendly building | `thingsByKind` O(n) | Spatial O(cells) | ai_core.nim |
| Find lantern within 3 tiles | `thingsByKind` O(n) | Spatial O(1 cell) | ai_core.nim |
| Find nearest food | `thingsByKind` O(n) | Spatial O(cells) | gatherer.nim |
| Find enemy in vision | Already cached | Spatial + cache | fighter.nim |
| Direct grid lookup | `grid[x][y]` O(1) | Already optimal | environment.nim |
| Per-kind iteration (render) | `thingsByKind` O(n) | Acceptable | renderer.nim |

---

## 4. Observation Building Analysis

### Current Implementation (environment.nim:766-817)

**Architecture**:
- Each agent has an 11x11 observation window (121 tiles)
- 82 observation layers encoded as uint8
- Rebuilt per-step, but stationary agents skip rebuild

**Optimization Already Applied**:
```nim
if firstRun or agentMoved:
  rebuildObservationsForAgent(env, agentId, agent)
```

**Complexity**: O(agents * tiles) = O(1006 * 121) ≈ 121K memory accesses per step (worst case)

**Potential Improvements** (not urgent):
1. Per-agent dirty bits instead of global flag
2. Vectorize terrain layer encoding
3. Pre-compute observation tile offsets at initialization

---

## 5. Recommendations Priority Matrix

| Priority | Change | Estimated Gain | Risk | Effort |
|----------|--------|----------------|------|--------|
| **P0** | Replace `nearestFriendlyBuildingDistance` with spatial queries | High | Low | Low |
| **P0** | Replace `hasTeamLanternNear` with spatial query | High | Low | Low |
| **P1** | Replace `hasNearbyFood` with spatial query | Medium | Low | Low |
| **P1** | Replace `fighterSeesEnemyStructureUncached` with spatial query | Medium | Low | Low |
| **P2** | Cache teamMask on Thing objects | Low | Medium | Medium |
| **P3** | Per-agent observation dirty bits | Low | Medium | High |

---

## 6. Implementation Notes

### For P0 Changes:

1. **nearestFriendlyBuildingDistance**: Can be implemented as a wrapper that calls `findNearestFriendlyThingSpatial` for each kind and returns minimum distance. The spatial index already supports team filtering.

2. **hasTeamLanternNear**: Use `collectThingsInRangeSpatial(env, pos, Lantern, 3, nearby)` and filter for healthy + teamId match. Alternatively, add a dedicated `hasTeamThingNearSpatial` helper.

### Testing Strategy:

1. Add unit tests comparing old vs new implementation results
2. Profile with `nimprof` before/after changes
3. Run existing test suite (`tests/test_behavior_balance.nim`)
4. Monitor `spatial_index.nim` stats with `-d:spatialStats`

---

## 7. Appendix: Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `src/spatial_index.nim` | Spatial partitioning queries | 949 |
| `src/types.nim` | Data structure definitions | 1200+ |
| `src/scripted/ai_core.nim` | AI utility functions | 1487 |
| `src/scripted/fighter.nim` | Fighter behavior | 1000+ |
| `src/scripted/gatherer.nim` | Gatherer behavior | 400+ |
| `src/environment.nim` | Grid/observation management | 1800+ |
