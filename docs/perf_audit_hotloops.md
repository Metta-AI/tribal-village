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

### 1. O(n) Containment Checks in step.nim

**Location**: `step.nim:2729`, `step.nim:2796`, `step.nim:908`, `step.nim:936`

**Problem**: Using `in` operator on `seq[Thing]` performs O(n) linear scan. When called inside loops over Spawners/Tumors/Agents, this creates O(n*m) complexity.

```nim
# step.nim:2729 - Inside loop over all Spawners
if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
  continue

# step.nim:2796 - Inside loop over all Tumors
if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
  continue

# step.nim:908 - Inside loop over all Agents
if tumor in tumorsToRemove[]:
  continue

# step.nim:936
if predator notin predatorsToRemove[]:
  predatorsToRemove[].add(predator)
```

**Impact**: With ~50 towers firing per step and ~200 tumors, this is O(50*200) = 10,000 comparisons. The `tempTowerRemovals` is typically small, but worst-case could be significant.

**Recommended Fix**: Convert `tempTowerRemovals`, `tumorsToRemove`, and `predatorsToRemove` to `HashSet[Thing]` (or `HashSet[pointer]`) for O(1) lookups:

```nim
# In Environment object, change:
#   tempTowerRemovals*: seq[Thing]
# To:
#   tempTowerRemovals*: HashSet[Thing]

# Usage becomes:
if thing in env.tempTowerRemovals:  # Now O(1)
  continue
```

---

### 2. Iterating All Agents Instead of Specialized Collection

**Location**: `step.nim:568-578` (`stepRechargeMonkFaith`)

**Problem**: This proc iterates ALL agents to find monks, but `env.monkUnits` already tracks monks specifically:

```nim
proc stepRechargeMonkFaith(env: Environment) =
  ## Regenerate faith for monks over time (AoE2-style faith recharge)
  for monk in env.agents:           # <-- Iterates ALL agents
    if not isAgentAlive(env, monk):
      continue
    if monk.unitClass != UnitMonk:  # <-- Filters out ~95% of iterations
      continue
    # ... rest of logic
```

**Contrast with stepApplyMonkAuras** at line 526 which correctly uses the specialized collection:
```nim
for monk in env.monkUnits:  # <-- Correct: only iterates actual monks
```

**Impact**: With 100+ agents per team, this scans ~400 agents to find ~4-8 monks. The monkUnits collection has exactly the monks.

**Recommended Fix**:
```nim
proc stepRechargeMonkFaith(env: Environment) =
  for monk in env.monkUnits:  # Use specialized collection
    if not isAgentAlive(env, monk):
      continue
    if isThingFrozen(monk, env):
      continue
    if monk.faith < MonkMaxFaith:
      monk.faith = min(MonkMaxFaith, monk.faith + MonkFaithRechargeRate)
```

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

### 6. hasTeamLanternNear Iterates All Lanterns

**Location**: `ai_core.nim:991-999`

**Problem**: Iterates all lanterns to find one within 3 tiles:

```nim
proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.thingsByKind[Lantern]:  # O(lanterns)
    if thing.isNil or not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y)) < 3'i32:
      return true
  false
```

**Impact**: With 50+ lanterns and called during building decisions, this adds up.

**Recommended Fix**: Use spatial index query:
```nim
proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  var lanterns: seq[Thing] = @[]
  collectThingsInRangeSpatial(env, pos, Lantern, 3, lanterns)
  for thing in lanterns:
    if thing.teamId == teamId and thing.lanternHealthy:
      return true
  false
```

---

## Summary Table

| Issue | Location | Severity | Fix Complexity |
|-------|----------|----------|----------------|
| O(n) `in` on tempTowerRemovals | step.nim:2729,2796 | High | Low (use HashSet) |
| O(n) `in` on tumorsToRemove | step.nim:908 | High | Low (use HashSet) |
| stepRechargeMonkFaith iterates all agents | step.nim:568 | Medium | Low (use monkUnits) |
| Duplicate pop cap calculation | step.nim:2632,3054 | Medium | Low (reuse existing) |
| Seq allocation in canEnterForMove | ai_core.nim:776 | Medium | Low (use arena) |
| Fertile tile 17x17 scan | ai_core.nim:1013 | Low | Medium (add index) |
| hasTeamLanternNear O(n) scan | ai_core.nim:991 | Low | Low (use spatial) |

---

## Recommendations Priority

1. **Immediate** (high impact, low effort):
   - Convert tempTowerRemovals/tumorsToRemove to HashSet
   - Use monkUnits in stepRechargeMonkFaith
   - Remove duplicate pop cap calculations

2. **Short-term** (medium impact):
   - Replace @[] with arena buffers in canEnterForMove
   - Add spatial query for hasTeamLanternNear

3. **Later** (optimization opportunities):
   - Index fertile tiles per team
   - Profile to find additional hotspots
