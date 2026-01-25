# Performance Investigation: 1000+ Agent Scaling

**Date**: 2026-01-24
**Bead**: tv-he40
**Status**: Complete

## Executive Summary

This investigation profiles the tribal-village simulation to identify bottlenecks preventing smooth operation at 1000+ agent scale. The simulation currently runs **8 teams × 125 agents = 1000 agents** on a 305×191 tile grid (58,255 tiles).

### Key Findings

| Bottleneck | Impact | Root Cause | Fix Complexity |
|------------|--------|------------|----------------|
| A* Pathfinding Allocations | **HIGH** | HashSet/Table allocs per-call | Medium |
| Linear Thing Scans | **HIGH** | O(n) scan for nearest queries | Medium |
| Tint System Iteration | **HIGH** | O(agents × radius²) per step | Medium |
| Observation Rebuild | **MEDIUM** | O(agents × 121 tiles) batch | Already optimized |
| Inventory Hash Tables | **MEDIUM** | Hash lookup per access | Easy |

**Estimated potential improvement**: 40-60% reduction in step time with proposed optimizations.

---

## Architecture Overview

### Simulation Step Pipeline (`src/step.nim`)

Each simulation step executes these phases sequentially:

```
step() pipeline:
├── Decay action tints (actionTintPositions traversal)
├── Decay shields (fixed MapAgents iteration)
├── Enforce zero HP deaths
├── Process agent actions (MapAgents loop)
│   ├── Parse action verb/argument
│   ├── Execute action (move/attack/use/build/etc.)
│   └── Update grid/observations
├── Update thing states (spawners, animals, buildings)
│   ├── Cow herd movement
│   ├── Wolf pack movement
│   ├── Bear movement
│   └── Predator attacks
├── Process tumors (branching, adjacency)
├── Apply tank/monk auras
├── Respawn dead agents
├── Update tint modifications (ALL agents/lanterns/tumors)
├── Apply tint modifications (active tiles)
└── Rebuild observations (ALL agents × 121 tiles)
```

### Agent Decision System (`src/scripted/ai_core.nim`)

Per-agent decision making in `decideAction()`:

```
decideAction(env, agentId):
├── Get/initialize agent state
├── Check attack opportunities (findAttackOpportunity)
│   └── O(things) scan for targets
├── Role-specific behavior:
│   ├── Gatherer: find resources, dropoff, plant
│   │   └── findNearestThingSpiral() - O(thingsByKind[kind])
│   ├── Builder: find build sites, construct
│   │   └── findPath() - A* with allocations
│   └── Fighter: engage enemies
│       └── findAttackOpportunity() - O(things)
└── Pathfinding if needed (findPath)
    └── O(explored) nodes with hash table ops
```

---

## Bottleneck Analysis

### 1. A* Pathfinding Allocations (HIGH IMPACT)

**Location**: `src/scripted/ai_core.nim:574-654`

**Problem**: Every `findPath()` call allocates:
- `seq[IVec2]` for goals (line 576)
- `HashSet[IVec2]` for openSet (line 599)
- `Table[IVec2, IVec2]` for cameFrom (line 601)
- `Table[IVec2, int]` for gScore (line 602)
- `Table[IVec2, int]` for fScore (line 603)
- Final `seq[IVec2]` path (line 628)

**Frequency**: Called by ~40% of agents (Builders, some Gatherers) per step when pathfinding to targets.

**Code excerpt**:
```nim
proc findPath(env: Environment, agent: Thing, fromPos, targetPos: IVec2): seq[IVec2] =
  var goals: seq[IVec2] = @[]  # Allocation 1
  # ...
  var openSet = initHashSet[IVec2]()  # Allocation 2
  var cameFrom = initTable[IVec2, IVec2]()  # Allocation 3
  var gScore = initTable[IVec2, int]()  # Allocation 4
  var fScore = initTable[IVec2, int]()  # Allocation 5
  # ... A* loop with hash operations
  result = @[cur]  # Allocation 6
```

**Impact**: With 400 agents pathfinding per step × 6 allocations × 3000 steps = 7.2M allocations per episode.

---

### 2. Linear Thing Scans (HIGH IMPACT)

**Location**: `src/scripted/ai_core.nim:184-191, 378-449`

**Problem**: `findNearestThing()` and `findAttackOpportunity()` perform O(n) scans over `thingsByKind[kind]` or all things.

**Code excerpt**:
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

**Frequency**: Called multiple times per agent per step. With ~500 trees, ~100 stones, etc., this is significant.

**Impact**: 1000 agents × 3 resource queries × 500 things = 1.5M iterations per step.

---

### 3. Tint System Iteration (HIGH IMPACT)

**Location**: `src/tint.nim:66-126`

**Problem**: Every agent, lantern, and tumor adds tint in a radius, iterating over (2×radius+1)² tiles.

**Code excerpt**:
```nim
proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
  for tileX in minX .. maxX:
    for tileY in minY .. maxY:
      if env.tintLocked[tileX][tileY]:
        continue
      # ... compute and apply tint
```

**Calculation**:
- 1000 agents × radius=2 = 1000 × 25 tiles = 25,000 tile updates
- Plus lanterns and tumors
- Multiplied by 2 passes (update + apply)

**Impact**: ~50,000+ tile operations per step just for tint.

---

### 4. Observation Rebuild (MEDIUM IMPACT - Already Optimized)

**Location**: `src/environment.nim:311-331`

**Status**: Already optimized from incremental to batch rebuild (see `docs/perf-improvements.md`).

**Current implementation**:
```nim
proc rebuildObservations*(env: Environment) =
  zeroMem(addr env.observations, sizeof(env.observations))
  for agentId in 0 ..< env.agents.len:
    # ... write 11×11 = 121 tiles per agent
```

**Cost**: 1000 agents × 121 tiles = 121,000 writes per step (acceptable).

---

### 5. Inventory Hash Tables (MEDIUM IMPACT)

**Location**: `src/items.nim:178-194`

**Problem**: Inventory uses `Table[ItemKey, int]` requiring hash computation for every access.

**Code excerpt**:
```nim
proc getInv*[T](thing: T, key: ItemKey): int =
  if key.kind == ItemKeyNone:
    return 0
  thing.inventory.getOrDefault(key, 0)  # Hash lookup
```

**Frequency**: Multiple inventory checks per action (resource gathering, building, trading).

---

## Proposed Optimizations

### Optimization 1: Pathfinding Cache (HIGH PRIORITY)

**Approach**: Pre-allocate pathfinding scratch space per-controller.

```nim
type PathfindingCache = object
  openSet: array[512, IVec2]
  openSetLen: int
  openSetHash: array[MapWidth, array[MapHeight, bool]]  # Fast lookup
  cameFrom: array[MapWidth, array[MapHeight, IVec2]]
  gScore: array[MapWidth, array[MapHeight, int]]
  visited: array[MapWidth, array[MapHeight, bool]]
  path: array[256, IVec2]
  pathLen: int

# Attach to Controller
type Controller = ref object
  # ... existing fields
  pathCache: PathfindingCache
```

**Changes**:
- Replace HashSet with fixed array + bool grid
- Replace Table with 2D arrays (only valid within search bounds)
- Clear visited/gScore within bounding box instead of full grid
- Reuse path array instead of allocating

**Expected Impact**: 20-40% reduction in AI tick time.

---

### Optimization 2: Spatial Hashing for Things (HIGH PRIORITY)

**Approach**: Partition world into cells, index things by cell.

```nim
const
  CellSize = 16  # Tiles per cell
  CellsX = (MapWidth + CellSize - 1) div CellSize   # 20 cells
  CellsY = (MapHeight + CellSize - 1) div CellSize  # 12 cells

type SpatialIndex = object
  cells: array[CellsX, array[CellsY, seq[Thing]]]

proc addThing(index: var SpatialIndex, thing: Thing) =
  let cx = thing.pos.x div CellSize
  let cy = thing.pos.y div CellSize
  index.cells[cx][cy].add(thing)

proc nearestInRadius(index: SpatialIndex, pos: IVec2, kind: ThingKind,
                     radius: int): Thing =
  let cx = pos.x div CellSize
  let cy = pos.y div CellSize
  let cellRadius = (radius + CellSize - 1) div CellSize
  var minDist = int.high
  result = nil
  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= CellsX or ny < 0 or ny >= CellsY:
        continue
      for thing in index.cells[nx][ny]:
        if thing.kind != kind:
          continue
        let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
        if dist < minDist and dist <= radius:
          minDist = dist
          result = thing
```

**Changes**:
- Maintain `SpatialIndex` per `ThingKind` (or combined)
- Update index on thing add/remove/move
- Replace linear scans with cell-based lookup

**Expected Impact**: 30-50% reduction in resource gathering time.

---

### Optimization 3: Delta-Based Tint Updates (HIGH PRIORITY)

**Approach**: Track entity positions and only update tint for moved entities.

```nim
type TintTracker = object
  lastAgentPos: array[MapAgents, IVec2]
  lastLanternCount: int
  lastTumorCount: int

proc updateTintModifications(env: Environment, tracker: var TintTracker) =
  # Only process agents that moved
  for agentId in 0 ..< env.agents.len:
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    if agent.pos == tracker.lastAgentPos[agentId]:
      continue  # Skip - hasn't moved

    # Remove old tint contribution (negative)
    let oldPos = tracker.lastAgentPos[agentId]
    if isValidPos(oldPos):
      subtractTintArea(oldPos, agentColor, radius=2)

    # Add new tint contribution
    addTintArea(agent.pos, agentColor, radius=2)
    tracker.lastAgentPos[agentId] = agent.pos
```

**Expected Impact**: 40-60% reduction in tint processing (most agents don't move every step).

---

### Optimization 4: Inventory Array Conversion (MEDIUM PRIORITY)

**Approach**: Replace Table with fixed array for common items.

```nim
type Inventory = object
  items: array[ItemKind, int16]  # Direct indexing for common items
  thingItems: Table[string, int16]  # Rare thing-items only

proc getInv(thing: Thing, kind: ItemKind): int {.inline.} =
  thing.inventory.items[ord(kind)]  # O(1) array access

proc setInv(thing: Thing, kind: ItemKind, value: int) {.inline.} =
  thing.inventory.items[ord(kind)] = value.int16
```

**Expected Impact**: 15-25% reduction in action processing time.

---

## PR Proposals

### PR 1: Pathfinding Cache Pre-allocation

**Title**: `perf: Pre-allocate pathfinding scratch space to reduce GC pressure`

**Scope**:
- Modify `Controller` type to include `PathfindingCache`
- Rewrite `findPath()` to use cache arrays
- Add cache clearing/reset between pathfinding calls

**Risk**: Low - isolated to AI system, behavior unchanged

---

### PR 2: Spatial Hashing for Thing Queries

**Title**: `perf: Add spatial index for O(1) nearest-thing queries`

**Scope**:
- Add `SpatialIndex` type to `Environment`
- Update `add()`/`removeThing()` to maintain index
- Replace `findNearestThing()` and `findNearestThingSpiral()` with spatial lookup

**Risk**: Medium - requires index maintenance on all thing mutations

---

### PR 3: Delta-Based Tint System

**Title**: `perf: Track entity movement for incremental tint updates`

**Scope**:
- Add `TintTracker` to `Environment`
- Modify `updateTintModifications()` to check position changes
- Add negative tint contribution for moved entities

**Risk**: Medium - tint accumulation edge cases need testing

---

### PR 4: Inventory Array Optimization

**Title**: `perf: Convert inventory from Table to array for common items`

**Scope**:
- Change `Inventory` type definition
- Update all `getInv()`/`setInv()` call sites
- Keep Table fallback for thing-items

**Risk**: Low - straightforward type change

---

## Benchmarking Recommendations

1. **Compile with timing**: `nim r -d:release -d:stepTiming --path:src scripts/profile_roles.nim`

2. **Environment variables**:
   - `TV_STEP_TIMING=100` - Start timing at step 100
   - `TV_STEP_TIMING_WINDOW=50` - Time 50 steps
   - `TV_PROFILE_STEPS=3000` - Run for 3000 steps

3. **Expected output**:
   ```
   step=150 total_ms=8.5 actions_ms=4.2 things_ms=1.1 tint_ms=2.8 ...
   ```

4. **Baseline target**: <5ms per step for 1000 agents at 60 FPS gameplay

---

## Conclusion

The tribal-village simulation has clear scaling bottlenecks at 1000+ agents:

1. **Memory allocations** in hot paths (pathfinding) cause GC pressure
2. **Linear scans** for nearest-thing queries don't scale
3. **Tint system** processes all entities every step regardless of movement

Implementing the proposed optimizations (pathfinding cache, spatial hashing, delta tint) should yield **40-60% overall step time reduction**, enabling smooth 60 FPS gameplay with 1000+ agents.

The existing timing infrastructure (`-d:stepTiming`) provides excellent visibility for measuring optimization impact.
