# Code Review: Verbosity Patterns in tribal-village

Date: 2026-01-28
Owner: Engineering / Analysis
Status: Active

This document identifies verbose code patterns in the codebase and suggests simplifications.

## Summary

The review covered:
- `src/environment.nim`
- `src/step.nim`
- `src/terrain.nim`
- `src/types.nim`
- `src/scripted/*.nim`

---

## High Priority

### 1. Repeated `basePos` pattern (13+ occurrences)

**Files:** `src/scripted/fighter.nim`, `src/scripted/options.nim`, `src/scripted/gatherer.nim`

**Locations:**
- `fighter.nim:155`, `fighter.nim:185`, `fighter.nim:343`
- `options.nim:394`, `options.nim:422`, `options.nim:510`, `options.nim:526`, `options.nim:542`, `options.nim:548`, `options.nim:565`, `options.nim:593`, `options.nim:609`, `options.nim:733`, `options.nim:804`
- `gatherer.nim:122`, `gatherer.nim:133`, `gatherer.nim:166`, `gatherer.nim:249`, `gatherer.nim:355`

**Current verbose pattern:**
```nim
let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
state.basePosition = basePos
```

**Suggested simplification:**
Extract to a utility proc:
```nim
proc getBasePos(agent: Thing): IVec2 =
  if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos

# Usage:
let basePos = agent.getBasePos()
state.basePosition = basePos
```

**Impact:** Reduces repetition across 13+ locations, improves maintainability.

---

### 2. Repeated nil-check + continue pattern in agent iteration

**File:** `src/scripted/fighter.nim`

**Locations:** Lines 31-40, 105-111, 534-541

**Current verbose pattern:**
```nim
for idx, other in env.agents:
  if other.agentId == agent.agentId:
    continue
  if not isAgentAlive(env, other):
    continue
  if sameTeam(agent, other):
    continue
  # ... actual logic
```

**Suggested simplification:**
Extract to an iterator:
```nim
iterator enemyAgents(env: Environment, agent: Thing): Thing =
  for other in env.agents:
    if other.agentId != agent.agentId and
       isAgentAlive(env, other) and
       not sameTeam(agent, other):
      yield other

# Usage:
for enemy in env.enemyAgents(agent):
  # ... actual logic
```

**Impact:** Reduces 6+ lines per occurrence to 1 line, clearer intent.

---

### 3. Repeated `actOrMove` pattern

**Files:** `src/scripted/fighter.nim`, `src/scripted/options.nim`

**Locations:**
- `fighter.nim:63-68` (definition), usage at lines 90-93, 98-101, 117, 517, 528, 550
- `options.nim:28-33` (duplicate definition)

**Current verbose pattern:**
```nim
return (if isAdjacent(agent.pos, target.pos):
  controller.useAt(env, agent, agentId, state, target.pos)
else:
  controller.moveTo(env, agent, agentId, state, target.pos))
```

**Suggested simplification:**
The `actOrMove` proc exists but is defined in both files. Consolidate to one location and use consistently:
```nim
# Already defined - just use it consistently:
return actOrMove(controller, env, agent, agentId, state, target.pos, 3'u8)
```

**Impact:** Remove duplicate proc definition, use existing helper consistently.

---

### 4. Verbose JSON parsing with repeated hasKey checks

**File:** `src/scripted/roles.nim`

**Locations:** Lines 228-246, 268-306

**Current verbose pattern:**
```nim
proc applyBehaviorHistory(catalog: var RoleCatalog, node: JsonNode) =
  if node.kind != JObject:
    return
  if not node.hasKey("behaviors"):
    return
  for entry in node["behaviors"].items:
    if entry.kind != JObject:
      continue
    let name = entry{"name"}.getStr()
    let idx = findBehaviorId(catalog, name)
    if idx < 0:
      continue
    if entry.hasKey("fitness"):
      catalog.behaviors[idx].fitness = entry["fitness"].getFloat().float32
    if entry.hasKey("games"):
      catalog.behaviors[idx].games = entry["games"].getInt()
    if entry.hasKey("uses"):
      catalog.behaviors[idx].uses = entry["uses"].getInt()
```

**Suggested simplification:**
Use the `{}` operator which already handles missing keys:
```nim
proc applyBehaviorHistory(catalog: var RoleCatalog, node: JsonNode) =
  if node.kind != JObject or not node.hasKey("behaviors"):
    return
  for entry in node["behaviors"].items:
    if entry.kind != JObject:
      continue
    let name = entry{"name"}.getStr()
    let idx = findBehaviorId(catalog, name)
    if idx < 0:
      continue
    # Use getFloat/getInt with defaults - already handles missing keys
    catalog.behaviors[idx].fitness = entry{"fitness"}.getFloat(catalog.behaviors[idx].fitness.float64).float32
    catalog.behaviors[idx].games = entry{"games"}.getInt(catalog.behaviors[idx].games)
    catalog.behaviors[idx].uses = entry{"uses"}.getInt(catalog.behaviors[idx].uses)
```

**Impact:** Reduces conditional nesting, more idiomatic JSON handling.

---

## Medium Priority

### 5. Verbose `isNil` checks that could use early return

**File:** `src/scripted/options.nim`

**Locations:** Lines 145-157, 159-181, 349-358, 360-369

**Current verbose pattern:**
```nim
proc findNearestEnemyBuilding(env: Environment, pos: IVec2, teamId: int): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if thing.teamId < 0 or thing.teamId == teamId:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < bestDist:
      bestDist = dist
      best = thing
  best
```

**Suggested simplification:**
Combine conditions:
```nim
proc findNearestEnemyBuilding(env: Environment, pos: IVec2, teamId: int): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind) or
       thing.teamId < 0 or thing.teamId == teamId:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < bestDist:
      bestDist = dist
      best = thing
  best
```

**Impact:** Fewer `continue` statements, clearer filtering logic.

---

### 6. Repeated wall/door neighbor checking pattern

**File:** `src/scripted/options.nim`

**Locations:** Lines 266-284, 295-304

**Current verbose pattern:**
```nim
let north = env.getThing(pos + ivec2(0, -1))
let south = env.getThing(pos + ivec2(0, 1))
let east = env.getThing(pos + ivec2(1, 0))
let west = env.getThing(pos + ivec2(-1, 0))
let northDoor = env.getBackgroundThing(pos + ivec2(0, -1))
let southDoor = env.getBackgroundThing(pos + ivec2(0, 1))
let eastDoor = env.getBackgroundThing(pos + ivec2(1, 0))
let westDoor = env.getBackgroundThing(pos + ivec2(-1, 0))
let northWall = (not isNil(north) and north.kind == Wall) or
  (not isNil(northDoor) and northDoor.kind == Door)
# ... repeat for south, east, west
```

**Suggested simplification:**
Extract to a helper:
```nim
proc hasWallOrDoor(env: Environment, pos: IVec2): bool =
  let thing = env.getThing(pos)
  let bg = env.getBackgroundThing(pos)
  (not isNil(thing) and thing.kind == Wall) or
  (not isNil(bg) and bg.kind == Door)

# Usage:
let northWall = env.hasWallOrDoor(pos + ivec2(0, -1))
let southWall = env.hasWallOrDoor(pos + ivec2(0, 1))
# etc.
```

**Impact:** Reduces 16 lines to 4 lines per usage.

---

### 7. Verbose task ordering pattern

**File:** `src/scripted/gatherer.nim`

**Locations:** Lines 55-67

**Current verbose pattern:**
```nim
var ordered: seq[(GathererTask, int)] = @[
  (TaskFood, env.stockpileCount(teamId, ResourceFood)),
  (TaskWood, env.stockpileCount(teamId, ResourceWood)),
  (TaskStone, env.stockpileCount(teamId, ResourceStone)),
  (TaskGold, env.stockpileCount(teamId, ResourceGold))
]
if altarFound:
  ordered.insert((TaskHearts, altarHearts), 0)
var best = ordered[0]
for i in 1 ..< ordered.len:
  if ordered[i][1] < best[1]:
    best = ordered[i]
task = best[0]
```

**Suggested simplification:**
Use min() with a key:
```nim
var ordered = @[
  (TaskFood, env.stockpileCount(teamId, ResourceFood)),
  (TaskWood, env.stockpileCount(teamId, ResourceWood)),
  (TaskStone, env.stockpileCount(teamId, ResourceStone)),
  (TaskGold, env.stockpileCount(teamId, ResourceGold))
]
if altarFound:
  ordered.insert((TaskHearts, altarHearts), 0)
task = ordered.minByIt(it[1])[0]
```

**Impact:** Reduces 6 lines to 1 line, clearer intent.

---

### 8. Repeated radius boundary calculations

**Files:** `src/scripted/gatherer.nim`, `src/scripted/options.nim`

**Locations:**
- `gatherer.nim:1-9`, `gatherer.nim:273-279`
- `options.nim:323-329`, `options.nim:244-248`, `options.nim:257-260`, `options.nim:286-289`

**Current verbose pattern:**
```nim
let cx = center.x.int
let cy = center.y.int
let startX = max(0, cx - radius)
let endX = min(MapWidth - 1, cx + radius)
let startY = max(0, cy - radius)
let endY = min(MapHeight - 1, cy + radius)
```

**Suggested simplification:**
Extract to a helper:
```nim
proc radiusBounds(center: IVec2, radius: int): tuple[startX, endX, startY, endY: int] =
  let cx = center.x.int
  let cy = center.y.int
  (max(0, cx - radius), min(MapWidth - 1, cx + radius),
   max(0, cy - radius), min(MapHeight - 1, cy + radius))

# Usage:
let (startX, endX, startY, endY) = radiusBounds(center, radius)
```

**Impact:** Reduces 6 lines to 1 line per usage, 6+ occurrences.

---

## Low Priority

### 9. Redundant type annotations

**File:** `src/scripted/fighter.nim`

**Locations:** Lines 103-104, 189-190, 241-246

**Current verbose pattern:**
```nim
var bestEnemy: Thing = nil
var bestDist = int.high
```

**Suggested simplification:**
Nim can infer types:
```nim
var bestEnemy: Thing = nil  # Keep - nil needs type hint
var bestDist = int.high     # OK - type inferred
```

**Impact:** Low - current style is acceptable for clarity.

---

### 10. Verbose conditional returns

**File:** `src/scripted/options.nim`

**Locations:** Multiple, e.g., lines 396-400, 410-414, 424-428

**Current verbose pattern:**
```nim
if target.x < 0:
  return 0'u8
if isAdjacent(agent.pos, target):
  return controller.actAt(env, agent, agentId, state, target, 6'u8)
controller.moveTo(env, agent, agentId, state, target)
```

**Suggested simplification:**
This pattern is idiomatic and clear. Could use early return guard clause style but current form is acceptable.

**Impact:** Low - current style is acceptable.

---

### 11. Verbose inventory iteration

**File:** `src/step.nim`

**Locations:** Lines 842-848, 920-931

**Current verbose pattern:**
```nim
var hasItems = false
for _, count in thing.inventory.pairs:
  if count > 0:
    hasItems = true
    break
if not hasItems:
  removeThing(env, thing)
```

**Suggested simplification:**
Use anyIt:
```nim
if not thing.inventory.pairs.toSeq.anyIt(it[1] > 0):
  removeThing(env, thing)
```

Or extract a helper:
```nim
proc hasAnyItems(thing: Thing): bool =
  for _, count in thing.inventory.pairs:
    if count > 0: return true
  false
```

**Impact:** Low - current form is clear.

---

### 12. Repeated dropoff pattern with boolean flags

**File:** `src/scripted/fighter.nim`

**Locations:** Lines 288-293, 303-308, 320-326

**Current verbose pattern:**
```nim
let (didDrop, actDrop) = controller.dropoffCarrying(
  env, agent, agentId, state,
  allowWood = true,
  allowStone = true,
  allowGold = true
)
if didDrop: return actDrop
```

**Suggested simplification:**
The pattern is used consistently. Could add overloads with fewer parameters but current explicit flags improve readability.

**Impact:** Low - explicitness aids maintenance.

---

## Summary Statistics

| Priority | Count | Estimated Lines Saved |
|----------|-------|----------------------|
| High     | 4     | ~100-150 lines       |
| Medium   | 4     | ~50-80 lines         |
| Low      | 4     | ~20-30 lines         |

---

## Recommended Actions

1. **Immediate:** Extract `getBasePos()` helper - used 13+ times
2. **Immediate:** Create `enemyAgents()` iterator - reduces boilerplate significantly
3. **Soon:** Consolidate duplicate `actOrMove` definitions
4. **Soon:** Extract `radiusBounds()` helper - used 6+ times
5. **Later:** Consider `hasWallOrDoor()` helper for wall-checking code
6. **Later:** Review JSON parsing for more idiomatic patterns
