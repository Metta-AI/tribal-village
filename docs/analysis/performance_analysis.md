# Performance Analysis: tribal-village

This document identifies performance optimization opportunities in the tribal-village codebase based on analysis of hot path code in `src/step.nim`, `src/environment.nim`, and `src/scripted/ai_core.nim`.

## Executive Summary

The main step function processes ~1000 agents per frame on a 305x191 grid. Key bottlenecks include:
1. AI pathfinding with A* algorithm allocations
2. Tint system processing large active tile sets
3. Thing iteration with O(n) scans for nearest-thing queries
4. Hash table (Table) operations in inventory system

---

## Hot Path Identification

### 1. Main Step Function (`src/step.nim`)

The `step()` procedure is the performance-critical entry point, executing each frame. The existing timing infrastructure (compiled with `-d:stepTiming`) reveals the following phases:

| Phase | Description | Typical Cost |
|-------|-------------|--------------|
| actionTint | Decay short-lived tint overlays | Low-Medium |
| shields | Shield countdown decay | Low |
| preDeaths | Enforce zero HP deaths | Low |
| **actions** | Process all agent actions | **High** |
| **things** | Update all thing states (spawners, animals, buildings) | **High** |
| tumors | Process tumor branching | Medium |
| adjacency | Tumor contact resolution | Medium |
| popRespawn | Agent respawn logic | Low |
| survival | Apply survival penalties | Low |
| **tint** | Update/apply tint modifications | **High** |
| end | Territory scoring, logging | Low |

### 2. AI Core (`src/scripted/ai_core.nim`)

The scripted AI controller runs for each agent and includes:
- `findPath()` - A* pathfinding (lines 574-654)
- `getMoveTowards()` - Direction calculation (lines 515-572)
- `findNearestThing()` - Linear scan over `thingsByKind` (lines 184-191)
- `findAttackOpportunity()` - Linear scan over all things (lines 378-449)

### 3. Tint System (`src/tint.nim`)

- `updateTintModifications()` - Processes active tiles and all things
- `applyTintModifications()` - Applies computed tints to grid

---

## Specific Optimization Opportunities

### HIGH IMPACT

#### 1. A* Pathfinding Allocations (ai_core.nim:574-654)

**Location:** `proc findPath()`

**Problem:** Every pathfinding call allocates:
- `seq[IVec2]` for goals (line 576)
- `HashSet[IVec2]` for openSet (line 599)
- `Table[IVec2, IVec2]` for cameFrom (line 601)
- `Table[IVec2, int]` for gScore/fScore (lines 602-603)
- Final path `seq[IVec2]` (line 628)

**Impact:** High - pathfinding called frequently by Builder/Gatherer roles

**Suggestion:**
```nim
# Pre-allocate pathfinding scratch space per-controller
type PathfindingCache = object
  openSet: array[256, IVec2]
  openSetLen: int
  cameFrom: array[MapWidth * MapHeight div 4, tuple[key, val: IVec2]]
  cameFromLen: int
  gScore: array[MapWidth, array[MapHeight, int]]
  visited: array[MapWidth, array[MapHeight, bool]]
```

**Estimated Improvement:** 20-40% reduction in AI tick time

---

#### 2. Linear Thing Scans (ai_core.nim:184-191)

**Location:** `proc findNearestThing()`, `proc findAttackOpportunity()`

**Problem:** O(n) scan over `thingsByKind[kind]` for every query. With hundreds of trees, stones, etc., this is slow.

**Code:**
```nim
proc findNearestThing(env: Environment, pos: IVec2, kind: ThingKind,
                      maxDist: int = SearchRadius): Thing =
  result = nil
  var minDist = 999999
  for thing in env.thingsByKind[kind]:  # O(n) scan
    let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
    if dist < minDist and dist < maxDist:
      minDist = dist
      result = thing
```

**Impact:** High - called multiple times per agent per step

**Suggestion:** Implement spatial hashing or quadtree for `thingsByKind`:
```nim
type SpatialHash = object
  cells: array[CellsX, array[CellsY, seq[Thing]]]
  cellSize: int

proc nearestInRadius(hash: SpatialHash, pos: IVec2, radius: int): Thing =
  # Only check cells in radius
  let cx = pos.x div cellSize
  let cy = pos.y div cellSize
  let cellRadius = (radius div cellSize) + 1
  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      for thing in hash.cells[cx + dx][cy + dy]:
        # ...
```

**Estimated Improvement:** 30-50% reduction for resource gathering AI

---

#### 3. Tint System Redundant Computation (tint.nim:66-85)

**Location:** `addTintArea()` nested loop

**Problem:** For every agent/lantern/tumor, iterates over a radius computing tint. With 1000 agents each with radius=2, this processes 25,000 tiles per step.

**Code:**
```nim
proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
  for tileX in minX .. maxX:
    for tileY in minY .. maxY:
      if env.tintLocked[tileX][tileY]:
        continue
      # ... compute tint
```

**Impact:** High - O(agents * radius^2) per step

**Suggestion:**
1. Batch similar-colored tint additions
2. Skip tint updates for static entities (unchanged position)
3. Use delta-based updates (track moved entities only)

```nim
# Track entity movement to skip unchanged
type TintTracker = object
  lastPos: array[MapAgents, IVec2]

proc updateTintModifications(env: Environment) =
  for agentId in 0 ..< env.agents.len:
    let agent = env.agents[agentId]
    if agent.pos == tracker.lastPos[agentId]:
      continue  # Skip - hasn't moved
    # Remove old tint contribution
    # Add new tint contribution
    tracker.lastPos[agentId] = agent.pos
```

**Estimated Improvement:** 40-60% reduction in tint processing for typical gameplay

---

### MEDIUM IMPACT

#### 4. Inventory Hash Table Operations (items.nim:178-194)

**Location:** `getInv()`, `setInv()` procedures

**Problem:** Uses `Table[ItemKey, int]` which requires hash computation and potential collision resolution for every inventory access.

**Code:**
```nim
proc getInv*[T](thing: T, key: ItemKey): int =
  if key.kind == ItemKeyNone:
    return 0
  thing.inventory.getOrDefault(key, 0)  # Hash lookup
```

**Impact:** Medium - inventory checked frequently during actions

**Suggestion:** Replace Table with fixed-size array for ItemKind items:
```nim
type Inventory = object
  items: array[ItemKind, int]  # Direct indexing for common items
  extra: Table[string, int]     # Rare thing-items only

proc getInv(thing: Thing, kind: ItemKind): int {.inline.} =
  thing.inventory.items[kind]  # O(1) array access
```

**Estimated Improvement:** 15-25% reduction in action processing time

---

#### 5. String Allocations in ItemKey (items.nim:37-44)

**Location:** `ItemKey` variant type with string field

**Problem:** `ItemKeyThing` and `ItemKeyOther` store strings, causing allocations when creating keys for comparison.

**Code:**
```nim
ItemKey* = object
  case kind*: ItemKeyKind
  of ItemKeyThing, ItemKeyOther:
    name*: string  # Heap allocation
```

**Impact:** Medium - affects building/crafting systems

**Suggestion:** Intern strings or use enum IDs:
```nim
type ThingBuildId = enum
  BuildWall, BuildRoad, BuildDoor, ...

ItemKey* = object
  case kind*: ItemKeyKind
  of ItemKeyThing:
    thingId: ThingBuildId  # No allocation
```

**Estimated Improvement:** 10-15% reduction in build action processing

---

#### 6. Observation Updates (environment.nim:123-149)

**Location:** `updateObservations()` procedure

**Problem:** Called frequently, iterates over all agents to check if position is in their observation radius.

**Code:**
```nim
proc updateObservations(env: Environment, layer: ObservationName, pos: IVec2, value: int) =
  for agentId in 0 ..< agentCount:
    let agent = env.agents[agentId]
    # Check if pos in agent's observation window
    let dx = pos.x - agentPos.x
    let dy = pos.y - agentPos.y
    if dx < -ObservationRadius or dx > ObservationRadius or ...
```

**Impact:** Medium - called for every grid change

**Suggestion:** Reverse the lookup - maintain per-tile observer lists:
```nim
# Pre-compute which agents observe each tile
type TileObservers = array[MapWidth, array[MapHeight, seq[int16]]]

proc updateObservations(env: Environment, pos: IVec2, ...) =
  for agentId in tileObservers[pos.x][pos.y]:
    # Update only relevant agents
```

**Estimated Improvement:** 20-30% reduction in observation update time

---

### LOW IMPACT

#### 7. Seq Operations in Hot Loops (step.nim:1289-1291)

**Location:** Tumor processing, tower removal lists

**Problem:** Creates temporary sequences for deferred operations.

**Code:**
```nim
var newTumorsToSpawn: seq[Thing] = @[]
var tumorsToProcess: seq[Thing] = @[]
var towerRemovals: seq[Thing] = @[]
```

**Impact:** Low - small allocations per step

**Suggestion:** Pre-allocate with estimated capacity or use pooled buffers:
```nim
var newTumorsToSpawn: seq[Thing]
newTumorsToSpawn.setLen(0)
newTumorsToSpawn.reserve(32)  # Avoid reallocs
```

**Estimated Improvement:** 2-5% reduction in step processing

---

#### 8. Redundant `isValidPos` Checks

**Location:** Throughout codebase

**Problem:** Many functions check `isValidPos` multiple times for the same position.

**Suggestion:** Use `{.inline.}` pragma (already done) and trust callers when appropriate:
```nim
# Trust internal calls where position already validated
proc writeTileObsUnchecked(env: Environment, ...) {.inline.} =
  # Skip bounds check
```

**Estimated Improvement:** 1-3% reduction

---

#### 9. Animal Movement Allocation (step.nim:1549-1566)

**Location:** Cow herd and wolf pack movement

**Problem:** Corner target selection allocates `seq[IVec2]` candidates:
```nim
var candidates: seq[IVec2] = @[]
for corner in cornerTargets:
  # ...
  candidates.add(corner)
```

**Impact:** Low - only runs once per herd/pack per step

**Suggestion:** Use fixed-size array since there are only 4 corners:
```nim
var candidates: array[4, IVec2]
var candidateCount = 0
```

**Estimated Improvement:** 1-2% reduction

---

## Existing Profiling Infrastructure

The codebase includes good profiling support:

### scripts/profile_env.nim
```nim
## Build with profiling enabled:
##   nim r --nimcache:./nimcache --profiler:on --stackTrace:on scripts/profile_env.nim
import nimprof
```

### Step Timing (compile with -d:stepTiming)
Environment variables:
- `TV_STEP_TIMING` - Target step to start timing
- `TV_STEP_TIMING_WINDOW` - Number of steps to time

The timing output includes detailed phase breakdown which is valuable for measuring optimization impact.

---

## Recommended Optimization Order

1. **Spatial hashing for thingsByKind** - Highest ROI, affects all AI queries
2. **Pathfinding cache pre-allocation** - High impact on Builder/Gatherer performance
3. **Tint delta updates** - High impact on rendering/step time
4. **Inventory array conversion** - Medium impact, relatively easy change
5. **Observation update optimization** - Medium impact, more complex change

---

## Benchmarking Recommendations

1. Use existing `profile_env.nim` with `--profiler:on`
2. Enable `-d:stepTiming` for phase-level breakdown
3. Test with full agent count (1000 agents) over 500+ steps
4. Compare before/after for each optimization in isolation
5. Track memory allocations with `--gc:orc -d:useMalloc` and valgrind

---

## Conclusion

The tribal-village codebase has reasonable performance but several opportunities for optimization, particularly around:
- Memory allocations in hot loops (pathfinding, tint system)
- Linear scans that could use spatial data structures
- Hash table overhead that could be replaced with arrays

The existing timing infrastructure provides good visibility into performance. Implementing the high-impact optimizations could yield 30-50% overall step time reduction.
