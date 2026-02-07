# AI Decision Making Performance Audit

**Date:** 2026-02-04
**Auditor:** polecat/slit
**Issue:** tv-wisp-wem25h
**Target:** <1ms per agent per tick

## Executive Summary

The AI decision-making system is well-optimized with extensive per-agent per-step caching, spatial index utilization, and bitwise team comparisons. The target of <1ms per agent per tick appears achievable. A few minor optimization opportunities exist.

## Architecture Overview

The AI system uses an **options-based framework** (`src/scripted/options.nim`) where:
1. Each role (Gatherer, Builder, Fighter, Scripted) has a priority-ordered list of `OptionDef` behaviors
2. `runOptions` evaluates options by priority, calling `canStart` to check eligibility
3. Active options can be preempted by higher-priority options if `interruptible=true`
4. Each option has `canStart`, `shouldTerminate`, and `act` procs

## Existing Optimizations (Good)

### 1. Per-Agent Per-Step Caching (`ai_core.nim:70-111`)

```nim
type PerAgentCache*[T] = object
  cacheStep*: int
  cache*: array[MapAgents, T]
  valid*: array[MapAgents, bool]
```

Used for expensive lookups to avoid redundant spatial scans when `canStart`/`shouldTerminate`/`act` all call the same function:

| Cache Variable | Location | Purpose |
|----------------|----------|---------|
| `meleeEnemyCache` | fighter.nim:17 | Nearest melee enemy for kiting |
| `siegeEnemyCache` | fighter.nim:18 | Nearest siege enemy for anti-siege |
| `friendlyMonkCache` | fighter.nim:19 | Nearest monk for healing seek |
| `scoutEnemyCache` | fighter.nim:20 | Enemies for scout flee |
| `seesEnemyStructureCache` | fighter.nim:21 | Enemy structure visibility |

### 2. Spatial Index (`spatial_index.nim`)

All nearest-neighbor queries use O(1) cell-based lookups:
- `findNearestThingSpatial` - nearest of one kind
- `findNearestFriendlyThingSpatial` - nearest team building
- `findNearestEnemyAgentSpatial` - nearest enemy agent
- `collectAlliesInRangeSpatial` - all allies in range

Pre-computed lookup tables (`distToCellRadius16`) eliminate runtime division.

### 3. Bitwise Team Comparisons

O(1) team checks via `getTeamMask()` throughout:
```nim
if (getTeamMask(other) and teamMask) != 0:
  continue  # Same team
```

### 4. Enemy Target Caching (`fighter.nim:149-214`)

`fighterFindNearbyEnemy` caches selected target for `TargetSwapInterval` ticks to avoid re-evaluation overhead:
```nim
let shouldReevaluate = (env.currentStep - state.fighterEnemyStep) >= TargetSwapInterval
if not shouldReevaluate and state.fighterEnemyAgentId >= 0:
  # Return cached target if still valid
```

### 5. Building Count Caching (`ai_core.nim:654-667`)

```nim
proc getBuildingCount*(controller: Controller, env: Environment, teamId: int, kind: ThingKind): int =
  if controller.buildingCountsStep != env.currentStep:
    # Recompute and cache
```

### 6. isThreateningAlly Two-Level Cache (`fighter.nim:11-108`)

Per-step cache in both module-level `Table[int, bool]` and `controller.allyThreatCache` array.

### 7. Threat Map Staggering (`ai_core.nim`)

```nim
ThreatMapStaggerInterval* = 5  # Only 1/5 of agents update threat map per step
```

## Potential Optimization Opportunities (Minor)

### 1. optFighterLanterns Building Iteration (`fighter.nim:574-588`)

**Current:** Iterates ~26 building kinds, each calling `hasTeamLanternNear`:
```nim
const LanternBuildingKinds = [Outpost, GuardTower, TownCenter, House, ...]
for kind in LanternBuildingKinds:
  for thing in env.thingsByKind[kind]:
    if hasTeamLanternNear(env, teamId, thing.pos):  # Spatial query
```

**Impact:** Low-medium. Only triggers for Fighter role with lantern/villager.

**Recommendation:** Consider caching unlit building positions per-step.

### 2. FighterAggressive Ally Checks (`fighter.nim:1115-1141`)

**Current:** `canStart` and `shouldTerminate` both call `collectAlliesInRangeSpatial`:
```nim
proc canStartFighterAggressive(...): bool =
  var allies: seq[Thing] = @[]
  collectAlliesInRangeSpatial(env, agent.pos, getTeamId(agent), 4, allies)
```

**Impact:** Low. Only affects Fighter role's aggressive option.

**Recommendation:** Use PerAgentCache for ally presence.

### 3. optScoutExplore Candidate Evaluation (`fighter.nim:1471-1502`)

**Current:** 16 candidates checked, each with threat lookup and revealed checks:
```nim
for _ in 0 ..< 16:
  let candidate = getNextSpiralPoint(state)
  let threatStrength = controller.getTotalThreatStrength(...)
  if not env.isRevealed(teamId, candidate): ...
```

**Impact:** Low. Only affects Scout units in scout mode.

**Recommendation:** Reduce candidates or add early-exit on good candidate found.

### 4. Formation Check Redundancy (`fighter.nim:1255-1328`)

**Current:** Multiple expensive calls in `canStartFighterFormation`:
```nim
let groupIdx = findAgentControlGroup(agentId)
if groupIdx < 0: return false
if not isFormationActive(groupIdx): return false
let groupSize = aliveGroupSize(groupIdx, env)
let myIndex = agentIndexInGroup(groupIdx, agentId, env)
let center = calcGroupCenter(groupIdx, env)
let targetPos = getFormationTargetForAgent(...)
```

**Impact:** Low. Only affects agents in formations.

**Recommendation:** Cache formation state per-step.

## Radius Limits Analysis

| Constant | Value | Location | Usage |
|----------|-------|----------|-------|
| `SearchRadius` | 50 | ai_core.nim:62 | Resource/building search |
| `ObservationRadius` | ~25 | types.nim | Vision range |
| `enemyRadius` | ObservationRadius*2 | fighter.nim:156 | Enemy search |
| `KiteTriggerDistance` | config | fighter.nim | Archer kiting |
| `AntiSiegeDetectionRadius` | config | fighter.nim | Siege response |
| `ScoutFleeRadius` | config | fighter.nim | Scout flee |

All radius limits appear appropriate and bounded.

## canStart/shouldTerminate Proc Costs

**Low Cost (O(1) or cached):**
- `canStartFighterMonk` - unitClass check
- `canStartFighterBreakout` - 8-direction passability check
- `canStartFighterRetreat` - HP ratio check
- `canStartFighterKite` - cached melee enemy lookup
- `canStartFighterAntiSiege` - cached siege enemy lookup
- `canStartFighterPatrol` - state flag check
- `canStartFighterHoldPosition` - state flag check
- `canStartFighterFollow` - state + alive check

**Medium Cost (spatial query, cached):**
- `canStartFighterSeekHealer` - cached monk lookup
- `canStartFighterTrain` - building count lookup (cached)
- `canStartFighterBecomeSiege` - building count + seesEnemyStructure (cached)

**Higher Cost (uncached):**
- `canStartFighterAggressive` - ally collection (seq allocation)
- `canStartFighterFormation` - multiple formation lookups

## Redundant State Lookups

No significant redundant state lookups found. The codebase consistently uses:
1. `PerAgentCache` for expensive lookups
2. Per-step invalidation for caches
3. Early-exit patterns when result already found

## Recommendations Summary

| Priority | Item | Estimated Impact |
|----------|------|------------------|
| Low | Cache ally presence for FighterAggressive | ~0.01ms/agent |
| Low | Reduce scout explore candidate count | ~0.01ms/scout |
| Low | Cache formation state per-step | ~0.01ms/formation member |
| Low | Cache unlit buildings for lantern placement | ~0.02ms/lantern agent |

## Conclusion

The AI system is well-optimized for the <1ms per agent per tick target. The identified optimizations are minor and primarily affect edge cases (scouts, formations, lantern placement). The existing caching infrastructure handles the main performance-critical paths effectively.

For profiling, compile with:
- `-d:aiAudit` + `TV_AI_LOG=1` for decision summary
- `-d:spatialStats` + `TV_SPATIAL_STATS_INTERVAL=100` for spatial query stats
- `-d:stepTiming` for per-subsystem step timing breakdown
- `-d:perfRegression` for regression detection (see `make benchmark`)
- `-d:actionFreqCounter` for action distribution by unit type
