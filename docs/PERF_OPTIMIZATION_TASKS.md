# tribal_village Performance Optimization Tasks

> Generated: 2026-02-02
> Status: 1/7 complete, 6 remaining
> Goal: Improve from ~2.25 steps/sec to 7-10+ steps/sec

## Completed

### tv-1za43: Spatial Utilities Consolidation ✅
Added new utilities to `src/spatial_index.nim`:
- `findNearestThingOfKindsSpatial()` - multi-kind queries (Agent OR Tumor)
- `collectThingsInRangeSpatial()` - generic collection by kind
- `collectAgentsByClassInRange()` - unit-class filtering (tanks, monks)

---

## Remaining Tasks (6)

### 1. CRITICAL: Replace Predator Targeting with Spatial Queries
**Bead ID:** tv-8zpne | **Priority:** P1

**Problem:**
`findNearestPredatorTarget()` at `src/step.nim:2768-2801` scans 225 grid positions (15x15 for wolves, 13x13 for bears) per predator pack using O(radius²) grid iteration.

**Fix:**
Replace grid scans at lines 2864 and 2932 with existing spatial utilities:
```nim
# BEFORE: O(radius²) grid scan
let huntTarget = findNearestPredatorTarget(center, WolfPackAggroRadius)

# AFTER: Use spatial index
let nearestAgent = findNearestEnemyAgentSpatial(env, center, -1, WolfPackAggroRadius)
let nearestTumor = findNearestThingSpatial(env, center, Tumor, WolfPackAggroRadius)
# Or use findNearestThingOfKindsSpatial() for combined search
```

**Files:**
- `src/step.nim:2768-2801` (findNearestPredatorTarget definition)
- `src/step.nim:2864` (wolf pack targeting call)
- `src/step.nim:2932` (bear targeting call)

**Expected Speedup:** 5-10x for predator AI subsystem

---

### 2. CRITICAL: Optimize Aura Processing
**Bead ID:** tv-5p1h6 | **Priority:** P1

**Problem:**
`stepApplyTankAuras()` at `src/step.nim:475-497` iterates ALL 1000 agents to find ~20 tanks.
`stepApplyMonkAuras()` at `src/step.nim:499-557` iterates ALL agents to find ~20 monks.

**Fix Options:**
1. Maintain `env.tankUnits` and `env.monkUnits` collections, updated on spawn/death/class-change
2. Or use `collectAgentsByClassInRange()` from spatial_index.nim

```nim
# BEFORE: O(n) scan of all agents
for agent in env.agents:
  if agent.unitClass notin {UnitManAtArms, UnitKnight}: continue
  # Apply aura...

# AFTER: Maintain typed collection
for tank in env.tankUnits:
  # Apply aura...
```

**Files:**
- `src/step.nim:475-497` (stepApplyTankAuras)
- `src/step.nim:499-557` (stepApplyMonkAuras)
- `src/types.nim` (add tankUnits, monkUnits to Environment)
- `src/spawn.nim` (update collections on spawn)
- `src/combat.nim` (update on death)

**Expected Speedup:** 10-50x for aura subsystem

---

### 3. HIGH: Replace Spawner Tumor Scan with Spatial Query
**Bead ID:** tv-z6sib | **Priority:** P1

**Problem:**
At `src/step.nim:2653-2680`, spawners scan 11x11 grid (121 lookups) to count nearby tumors.

**Fix:**
```nim
# BEFORE: 121 grid lookups per spawner
for offset in spawnerScanOffsets:
  let checkPos = thing.pos + offset
  let other = env.getThing(checkPos)
  if other.kind == Tumor: ...

# AFTER: Spatial query
let nearbyTumors = collectThingsInRangeSpatial(env, spawner.pos, Tumor, 5)
```

**Files:**
- `src/step.nim:2653-2680` (spawner tumor scan)

**Expected Speedup:** 10x for spawner subsystem

---

### 4. CRITICAL: Stagger AI Threat Map Updates
**Bead ID:** tv-5zkfl | **Priority:** P1

**Problem:**
`updateThreatMapFromVision()` called at `src/scripted/ai_defaults.nim:809-812` for ALL 1000 agents EVERY tick. Each call scans spatial index cells within vision radius.

**Fix:**
Stagger updates - only update 1/5 (or 1/N) of agents per step:
```nim
# BEFORE: Every agent every step
controller.updateThreatMapFromVision(env, agent, currentStep)

# AFTER: Stagger by agent ID
if agent.agentId mod 5 == currentStep mod 5:
  controller.updateThreatMapFromVision(env, agent, currentStep)
```

**Files:**
- `src/scripted/ai_core.nim:367-430` (updateThreatMapFromVision)
- `src/scripted/ai_defaults.nim:809-812` (call site)

**Expected Speedup:** 5x for threat map subsystem

---

### 5. HIGH: Optimize Fighter Target Re-evaluation
**Bead ID:** tv-eemdy | **Priority:** P2

**Problem:**
`fighterFindNearbyEnemy()` at `src/scripted/fighter.nim:93-158` re-evaluates targets every 10 steps.
`scoreEnemy()` calls `isThreateningAlly()` which does another spatial scan.
With 333 fighters, ~33 nested spatial scans per step.

**Fix:**
1. Increase `TargetSwapInterval` from 10 to 20-30 steps
2. Cache `isThreateningAlly()` results per enemy per step (shared lookup table)
3. Or pre-compute 'under_threat' flag for all agents once per step

```nim
# In constants.nim
const TargetSwapInterval* = 20  # Was 10

# Cache threatening status
var threateningCache: Table[int, bool]
proc isThreateningAllyCached(env: Environment, enemy: Thing, teamId: int): bool =
  if enemy.agentId in threateningCache:
    return threateningCache[enemy.agentId]
  result = isThreateningAlly(env, enemy, teamId)
  threateningCache[enemy.agentId] = result
```

**Files:**
- `src/scripted/fighter.nim:93-158` (fighterFindNearbyEnemy)
- `src/scripted/fighter.nim:54-91` (scoreEnemy)
- `src/constants.nim:287` (TargetSwapInterval)

**Expected Speedup:** 2-3x for fighter AI

---

### 6. CRITICAL: Use Spatial Query for Combat Aura Damage Check
**Bead ID:** tv-53xww | **Priority:** P1

**Problem:**
At `src/combat.nim:325-332`, damage calculation scans ALL 1000 agents to find nearby tanks for damage reduction aura.

**Fix:**
```nim
# BEFORE: O(n) scan of all agents during damage
for agent in env.agents:
  if not isAgentAlive(env, agent) or getTeamId(agent) != teamId: continue
  if agent.unitClass notin {UnitManAtArms, UnitKnight}: continue
  if chebyshevDist(agent.pos, enemy.pos) <= AllyThreatRadius:
    # Apply damage reduction

# AFTER: Spatial query
let nearbyTanks = collectAgentsByClassInRange(env, enemy.pos, teamId,
                                               {UnitManAtArms, UnitKnight},
                                               AllyThreatRadius)
if nearbyTanks.len > 0:
  # Apply damage reduction
```

**Files:**
- `src/combat.nim:325-332` (aura damage check)

**Expected Speedup:** 100-1000x in dense combat scenarios

---

## Summary Table

| Task | File(s) | Complexity | Expected Gain |
|------|---------|------------|---------------|
| Predator targeting | step.nim | Medium | 5-10x |
| Aura processing | step.nim, types.nim, spawn.nim | Medium | 10-50x |
| Spawner tumor scan | step.nim | Easy | 10x |
| Threat map stagger | ai_defaults.nim, ai_core.nim | Easy | 5x |
| Fighter target cache | fighter.nim, constants.nim | Medium | 2-3x |
| Combat aura check | combat.nim | Easy | 100-1000x |

## Testing

After each fix, run:
```bash
cd tribal_village/mayor/rig
nim c -r -d:release scripts/perf_baseline.nim --steps 1000
nim c -r tests/integration_behaviors.nim
```

Baseline: ~2.25 steps/sec
Target: 7-10+ steps/sec

## Key Insight

The spatial index infrastructure (`src/spatial_index.nim`) is well-designed and already has the utilities needed. The main issue is that many hot paths **bypass it** and do O(n) or O(n²) scans instead. The fixes are mostly about using existing spatial query functions.
