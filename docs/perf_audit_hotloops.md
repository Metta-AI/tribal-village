# Performance Audit: Hotloop Inefficiencies in step.nim and ai_core.nim

**Bead**: tv-wisp-sapm3
**Date**: 2026-02-04
**Files Audited**: `src/step.nim`, `src/scripted/ai_core.nim`

## Executive Summary

This audit identifies hotloop inefficiencies in the step processing and AI controller code. The primary issues are:

1. **O(n) containment checks on sequences** - Linear scans where HashSets would provide O(1)
2. **Iterating all agents instead of specialized collections** - Scanning ~100+ agents when only a handful match
3. **Duplicate population calculations** - Computing team pop caps/counts 2-3 times per step
4. **Heap allocations in hot paths** - `@[]` seq literals inside frequently-called procs

---

## Critical Issues

### 1. O(n) Containment Checks in step.nim (OPEN)

**Location**: `step.nim` (spawner/tumor loops), `step.nim` (agent loops)

**Problem**: Using `in` operator on `seq[Thing]` performs O(n) linear scan. When called inside loops over Spawners/Tumors/Agents, this creates O(n*m) complexity.

```nim
# Inside loop over all Spawners
if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
  continue

# Inside loop over all Tumors
if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
  continue
```

**Status**: `tempTowerRemovals` is still `seq[Thing]` in `types.nim`. The `len > 0` guard avoids the scan when the list is empty, but worst-case is still O(n).

**Impact**: Mitigated by the length guard (skips scan when no towers fired), but converting to `HashSet[Thing]` would provide O(1) lookups.

**Recommended Fix**: Convert `tempTowerRemovals` to `HashSet[Thing]` for O(1) lookups.

---

### 2. ~~Iterating All Agents Instead of Specialized Collection~~ (FIXED)

**Location**: `step.nim` (`stepRechargeMonkFaith`)

**Status**: **Fixed.** `stepRechargeMonkFaith` now iterates `env.monkUnits` instead of all agents, consistent with `stepApplyMonkAuras`.

---

### 3. Duplicate Population Calculations

**Location**: `step.nim:1066-1080`, `step.nim:2632-2640`, `step.nim:3054-3060`

**Problem**: Team population caps and counts are calculated 3 times per step:

**First calculation** (lines 1066-1080):
```nim
for i in 0 ..< MapRoomObjectsTeams:
  env.stepTeamPopCaps[i] = 0
  env.stepTeamPopCounts[i] = 0
for thing in env.thingsByKind[TownCenter]:
  if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
    env.stepTeamPopCaps[thing.teamId] += TownCenterPopCap
for thing in env.thingsByKind[House]:
  if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
    env.stepTeamPopCaps[thing.teamId] += HousePopCap
for agent in env.agents:
  if not isAgentAlive(env, agent):
    continue
  let teamId = getTeamId(agent)
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    inc env.stepTeamPopCounts[teamId]
```

**Second calculation** (lines 2632-2640) - IDENTICAL to first:
```nim
var teamPopCaps: array[MapRoomObjectsTeams, int]
for thing in env.thingsByKind[TownCenter]:
  if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
    teamPopCaps[thing.teamId] += TownCenterPopCap
for thing in env.thingsByKind[House]:
  if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
    teamPopCaps[thing.teamId] += HousePopCap
```

**Third calculation** (lines 3054-3060) - Partial duplicate:
```nim
var teamPopCounts: array[MapRoomObjectsTeams, int]
for agent in env.agents:
  if not isAgentAlive(env, agent):
    continue
  # ... counts agents again
```

**Impact**: 3 iterations over TownCenters, 3 iterations over Houses, 2-3 iterations over all agents. Each agent iteration is O(agents) = ~400 ops.

**Recommended Fix**: Remove the second and third calculations, use `env.stepTeamPopCaps` and `env.stepTeamPopCounts` which are already computed:

```nim
# At line 2632, replace local teamPopCaps with:
# (Use env.stepTeamPopCaps directly)

# At line 3054, the comment says "Town Centers + Houses already counted above"
# but then recalculates anyway. Just use env.stepTeamPopCounts directly.
```

---

## Moderate Issues

### 4. Seq Allocations in Hot Paths (ai_core.nim)

**Location**: `ai_core.nim:321`, `ai_core.nim:776`, `ai_core.nim:894/922/989`

**Problem**: Using `@[]` creates heap allocation. In frequently-called procs this causes memory churn:

```nim
# ai_core.nim:321 - getThreatsInRange
result = @[]  # Heap allocation

# ai_core.nim:776 - canEnterForMove (called for EVERY move decision)
var nearbyLanterns: seq[Thing] = @[]  # Heap allocation inside hot path
collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns)

# ai_core.nim:894,922,989 - findPath (called for pathfinding)
return @[]  # Multiple exit points with allocation
```

**Impact**: `canEnterForMove` is called multiple times per agent per step (8 directions tested). With 400 agents, that's potentially 3200+ allocations per step just from this one proc.

**Recommended Fix**: Use pre-allocated arena buffers (already available in Environment):

```nim
# For canEnterForMove, use arena buffer:
var nearbyLanterns = addr env.arena.things4  # Reuse pre-allocated
nearbyLanterns[].setLen(0)
collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns[])

# For getThreatsInRange, consider using a fixed-size array with count
# when the result is small and bounded
```

---

### 5. Inefficient Fertile Tile Search in ai_core.nim

**Location**: `ai_core.nim:1013-1028` (`tryPlantOnFertile`)

**Problem**: Nested loop scans 17x17 = 289 tiles looking for fertile terrain:

```nim
let startX = max(0, agent.pos.x - 8)
let endX = min(MapWidth - 1, agent.pos.x + 8)
let startY = max(0, agent.pos.y - 8)
let endY = min(MapHeight - 1, agent.pos.y + 8)
for x in startX..endX:
  for y in startY..endY:
    if env.terrain[x][y] != TerrainType.Fertile:
      continue
    # ...
```

**Impact**: Called for each gatherer agent that might plant. With ~50 gatherers, this is 50 * 289 = 14,450 terrain checks per step.

**Recommended Fix**: Consider a spatial index for fertile tiles, or use the Mill's fertile radius which is already tracked. Alternatively, cache fertile tile positions per team.

---

### 6. ~~hasTeamLanternNear Iterates All Lanterns~~ (FIXED)

**Location**: `ai_core.nim`

**Status**: **Fixed.** `hasTeamLanternNear` now uses `collectThingsInRangeSpatial(env, pos, Lantern, 3, nearby)` for O(1 cell) lookups instead of iterating all lanterns. Note: still allocates a local `seq[Thing]` per call; could be further optimized with a pre-allocated buffer.

---

## Summary Table

| Issue | Location | Severity | Status |
|-------|----------|----------|--------|
| O(n) `in` on tempTowerRemovals | step.nim | High | **Open** (mitigated by len>0 guard) |
| O(n) `in` on tumorsToRemove | step.nim | High | Open |
| stepRechargeMonkFaith iterates all agents | step.nim | Medium | **Fixed** (uses monkUnits) |
| Duplicate pop cap calculation | step.nim | Medium | Open |
| Seq allocation in canEnterForMove | ai_core.nim | Medium | Open |
| Fertile tile 17x17 scan | ai_core.nim | Low | Open |
| hasTeamLanternNear O(n) scan | ai_core.nim | Low | **Fixed** (uses spatial index) |

---

## Recommendations Priority

1. **Immediate** (high impact, low effort):
   - Convert tempTowerRemovals/tumorsToRemove to HashSet
   - Remove duplicate pop cap calculations

2. **Short-term** (medium impact):
   - Replace `@[]` with arena buffers in `canEnterForMove`

3. **Later** (optimization opportunities):
   - Index fertile tiles per team
   - Profile to find additional hotspots

### Already Completed
- ~~Use monkUnits in stepRechargeMonkFaith~~ (done)
- ~~Add spatial query for hasTeamLanternNear~~ (done)
