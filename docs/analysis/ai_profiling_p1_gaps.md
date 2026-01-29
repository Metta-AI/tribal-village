# AI Profiling & P1 Gaps Analysis
**Date:** 2026-01-29
**Session:** mayor cold-start profiling exploration

## Executive Summary

This document provides a comprehensive analysis of the Tribal Village AI behavior system, focusing on P1 (Priority 1) gaps, performance profiling, and the control API surface. Key findings:

1. **Performance**: 3.0 steps/second with 1006 agents (309μs per agent AI time)
2. **Control API**: Most critical APIs **already exposed** via FFI (stance, garrison, production queue, research)
3. **Invalid Actions**: 12-14% rate caused by stale caching and multi-agent race conditions
4. **Test Coverage**: Comprehensive with 70+ passing tests across all subsystems

## Table of Contents

1. [Performance Profiling Results](#performance-profiling-results)
2. [AI Behavior System Architecture](#ai-behavior-system-architecture)
3. [Control API Status](#control-api-status)
4. [Invalid Action Analysis](#invalid-action-analysis)
5. [Test Coverage Summary](#test-coverage-summary)
6. [P1 Gaps (Updated)](#p1-gaps-updated)
7. [Recommendations](#recommendations)

---

## Performance Profiling Results

### Benchmark Configuration
- **Agents**: 1006 total (8 teams × 125 + goblins)
- **Warmup**: 100 steps
- **Profile Duration**: 1000 steps
- **Compiler**: Nim 2.2.6, debug build (opt: none)

### Results Summary

```
Steps profiled: 1000 (after 100 warmup)
Total wall time: 332.87s

Per-step timing:
  AI (getActions):  avg=311.04ms (93.4%)
  Sim (env.step):   avg=21.82ms  (6.6%)

Throughput: 3.0 steps/second
Per-agent AI: 309.18μs
```

### Performance Breakdown by Phase

| Step Range | AI Time | Sim Time | Total | Steps/sec |
|------------|---------|----------|-------|-----------|
| 101-200    | 229.90ms | 15.44ms | 245.33ms | 4.1 |
| 201-300    | 250.90ms | 17.25ms | 268.15ms | 3.7 |
| 301-400    | 284.52ms | 18.80ms | 303.32ms | 3.3 |
| 401-500    | 286.27ms | 20.80ms | 307.08ms | 3.3 |
| 501-600    | 306.71ms | 20.46ms | 327.17ms | 3.1 |
| 601-700    | 320.34ms | 23.88ms | 344.23ms | 2.9 |
| 701-800    | 351.52ms | 23.91ms | 375.43ms | 2.7 |
| 801-900    | 370.89ms | 24.96ms | 395.85ms | 2.5 |
| 901-1000   | 320.97ms | 25.75ms | 346.73ms | 2.9 |
| 1001-1100  | 388.34ms | 26.99ms | 415.33ms | 2.4 |

**Observation**: Performance degrades over time, likely due to increased game complexity (more buildings, threats, cache misses).

### Hotpath Analysis

#### Optimized (Post-Spatial Index)
These operations now use grid-based spatial indexing:
- `updateThreatMapFromVision`: O(visionRange²) grid scan per agent (was O(agents))
- `findAttackOpportunity`: O(8×maxRange) line scan per agent (was O(things))
- `fighterFindNearbyEnemy`: O(enemyRadius²) grid scan (was O(agents))
- `isThreateningAlly`: O(AllyThreatRadius²) grid scan (was O(agents))
- `needsPopCapHouse`: O(1) cached per-step pop count (was O(agents))
- `findNearestFriendlyMonk`: O(HealerSeekRadius²) grid scan (was O(agents))

#### Remaining O(n) Hotpaths (Optimization Candidates)
- `nearestFriendlyBuildingDistance`: O(things) linear scan - **NOT using spatial index**
- `hasTeamLanternNear`: O(things) linear scan per call
- `optFighterLanterns`: O(things) scan for unlit buildings
- `revealTilesInRange`: O(visionRadius²) per agent per step

**Estimated Gains from Spatial Indexing Remaining Hotpaths**: 15-25% reduction in AI time

### Game State Progression
```
Baseline houses: t0=4 t1=5 t2=5 t3=4 t4=5 t5=4 t6=4 t7=5
Max houses:      t0=32 t1=5 t2=5 t3=4 t4=5 t5=4 t6=4 t7=5
Max hearts:      t0=10 t1=5 t2=5 t3=5 t4=5 t5=5 t6=5 t7=5
```
Team 0 shows significantly more construction activity (32 houses vs 4-5 for other teams).

---

## AI Behavior System Architecture

### File Organization
**Location**: `/home/relh/gt/tribal_village/src/scripted/`

| File | Lines | Purpose |
|------|-------|---------|
| ai_types.nim | 229 | Core type definitions (AgentRole, AgentState, Controller, DifficultyConfig) |
| ai_core.nim | 1,492 | Shared utilities (pathfinding, threat maps, spatial searches) |
| ai_options.nim | 71 | Options framework (OptionDef, runOptions executor) |
| ai_defaults.nim | 1,064 | Role instantiation (creates option arrays for roles) |
| gatherer.nim | 611 | Resource gathering role |
| builder.nim | 812 | Building construction role |
| fighter.nim | 1,534 | Combat and hunting role |
| coordination.nim | 177 | Inter-role communication |
| economy.nim | 226 | Resource bottleneck detection |
| evolution.nim | 137 | Evolutionary role catalog |
| **TOTAL** | **~9,600** | **AI system implementation** |

### Options Framework Architecture

```nim
OptionDef = object:
  canStart: proc(Controller, Environment, Agent, AgentState) -> bool
  act: proc(Controller, Environment, Agent, AgentState) -> uint8
  shouldTerminate: proc(Controller, Environment, Agent, AgentState) -> bool
  interruptible: bool
```

**Execution Model** (in `runOptions`):
1. If option active and interruptible → scan for higher-priority options
2. Increment active option tick counter
3. Call `act()` and return action if non-zero
4. Check termination condition, reset if met
5. Otherwise: scan options in priority order, use first that can start

### Role Behavior Summary

#### Gatherer (611 lines)
**Options**: Flee, Plant Wheat, Hunt Food, Gather (Food/Wood/Stone/Gold), Dropoff, Search

**Characteristics**:
- Dynamic task selection based on economy bottlenecks
- Early game: food priority → late game: gold priority
- Spiral search pattern for resource discovery
- Flee radius: 8 tiles
- **Caches**: `cachedThingPos[ThingKind]`, `cachedWaterPos`

#### Builder (812 lines)
**Options**: Flee, Repair, Plant Lanterns, Build Infrastructure, Build Defenses, Build Tech

**Characteristics**:
- Adaptive wall ring radius based on building count
- Under-threat detection: 15-tile radius from home altar
- Responds to defense requests from coordination system
- Core buildings: Granary, LumberCamp, Quarry, MiningCamp
- Tech buildings: Barracks, ArcheryRange, Stable, Blacksmith

#### Fighter (1,534 lines)
**Options**: Flee, Melee Attack, Ranged Attack, Escort Ally, Patrol, Scout

**Characteristics**:
- Smart target selection: Threatening allies → Low HP → Closest
- Stance system: Aggressive, Defensive, StandGround, NoAttack
- Attack-move and patrol (waypoint-based)
- Scout mode: Extended vision (18 tiles vs 12)
- Siege weapon management

### Decision Flow
```
Per-step for each agent:
  1. decideAction(env, agentId) → calls role's runOptions()
  2. Role scans options based on conditions
  3. First viable option's act() returns uint8 action
  4. encodeAction(verb, argument) → 8-bit action code

Action Encoding:
  Verb 0: NOOP
  Verb 1: MOVE (argument = direction 0-7)
  Verb 2: ATTACK (argument = direction 0-7)
  Verb 3: USE/INTERACT (argument = direction 0-7)
  Verbs 4-9: Build, research, etc.
```

---

## Control API Status

### ✅ APIs Already Exposed via FFI

The audit revealed that **most control APIs are already implemented and exposed**. Here's what's available:

#### Core Management
```nim
tribal_village_create() -> Environment
tribal_village_reset_and_get_obs(env) -> fills observation buffer
tribal_village_step_with_pointers(env, actions, obs, rewards, dones, infos)
tribal_village_destroy(env)
```

#### Attack-Move API ✅
```nim
tribal_village_set_attack_move(agentId, x, y)
tribal_village_clear_attack_move(agentId)
tribal_village_is_attack_move_active(agentId) -> bool
```

#### Patrol API ✅
```nim
tribal_village_set_patrol(agentId, x1, y1, x2, y2)
tribal_village_clear_patrol(agentId)
tribal_village_is_patrol_active(agentId) -> bool
```

#### Stance API ✅
```nim
tribal_village_set_stance(env, agentId, stance)
tribal_village_get_stance(env, agentId) -> Stance
```
**Stances**: Aggressive, Defensive, StandGround, NoAttack

#### Garrison API ✅
```nim
tribal_village_garrison(env, agentId, buildingX, buildingY)
tribal_village_ungarrison(env, buildingX, buildingY)
tribal_village_garrison_count(env, buildingX, buildingY) -> int
```

#### Production Queue API ✅
```nim
tribal_village_queue_train(env, buildingX, buildingY, teamId)
tribal_village_cancel_train(env, buildingX, buildingY)
tribal_village_queue_size(env, buildingX, buildingY) -> int
tribal_village_queue_progress(env, buildingX, buildingY, index) -> float
```

#### Research APIs ✅
```nim
tribal_village_research_blacksmith(env, agentId, buildingX, buildingY)
tribal_village_research_university(env, agentId, buildingX, buildingY)
tribal_village_research_castle(env, agentId, buildingX, buildingY)
tribal_village_research_unit_upgrade(env, agentId, buildingX, buildingY)
```

#### Tech Query APIs ✅
```nim
tribal_village_has_blacksmith_upgrade(env, teamId, upgradeType) -> bool
tribal_village_has_university_tech(env, teamId, techType) -> bool
tribal_village_has_castle_tech(env, teamId, techType) -> bool
tribal_village_has_unit_upgrade(env, teamId, upgradeType) -> bool
```

#### Scout Mode API ✅
```nim
tribal_village_set_scout_mode(agentId, active)
```

### ❌ APIs NOT Exposed (Internal Only)

#### Difficulty Control (Internal)
```nim
getDifficulty() / setDifficulty() / setDifficultyConfig()
enableAdaptiveDifficulty() / disableAdaptiveDifficulty()
shouldApplyDecisionDelay()
updateAdaptiveDifficulty()
```

#### Threat Map Functions (Internal)
```nim
decayThreats() / reportThreat() / getNearestThreat()
getThreatsInRange() / getTotalThreatStrength()
hasKnownThreats() / clearThreatMap()
updateThreatMapFromVision()
```

#### Fog of War Functions (Internal)
```nim
revealTilesInRange() / isRevealed()
clearRevealedMap() / clearAllRevealedMaps()
updateRevealedMapFromVision() / getRevealedTileCount()
```

### 🎯 Missing Command APIs

These common RTS commands are **not implemented** at any level:
- ❌ **Stop command** - No way to halt current action
- ❌ **Hold position** - Similar to StandGround but different semantics
- ❌ **Follow/Guard commands** - Escort exists but no explicit follow
- ❌ **Formation system** - No formation API at all
- ❌ **Control groups** - No selection/grouping API
- ❌ **Rally points** - Building rally points not exposed (though mentioned in docs)

---

## Invalid Action Analysis

### Detection Mechanism
Invalid actions are tracked in `env.stats[agentId].actionInvalid` counter (in step.nim).

**Incremented when**:
1. Movement blocked (water/door/elevation barriers)
2. Attack out of range (target not in line of sight)
3. Resource exhausted (stump/gold/stone depleted)
4. Interaction failed (building frozen, resource unavailable)
5. Monk conversion fails (insufficient faith, target team at pop cap)
6. Ranged attack misses (arrow/projectile doesn't hit)
7. Siege weapon blocked (unit can't attack when packed/enclosed)

### Root Causes

#### 1. Stale Position Caching (Major Problem)

**Cache Structure** (in `ai_types.nim::AgentState`):
```nim
cachedThingPos*: array[ThingKind, IVec2]  # Per-resource-type position cache
cachedWaterPos*: IVec2                     # Last known water position
pathBlockedTarget*: IVec2                  # Previously blocked target
```

**Cache Logic** (in `ai_core.nim::findNearestThingSpiral`):
```nim
if cachedPos.x >= 0:
  if abs(cachedPos.x - lastSearchPos.x) + abs(cachedPos.y - lastSearchPos.y) < 30:
    # Use cache even if stale! Distance-based invalidation only
```

**Invalidation Triggers**:
- Thing no longer exists at cached position
- Thing is frozen (checked once)
- Agent moved > 30 tiles from cached position
- **NOT CHECKED**: Thing depleted by another agent

**Problem**: Multi-agent harvesting races:
1. Agent A caches tree at (10, 10)
2. Agent B also caches same tree at (10, 10)
3. Agent A harvests tree → becomes stump with 0 wood
4. Agent B still has cached position, attempts harvest → **invalid action**
5. Cache invalidation only happens when B reaches the stump and finds it empty

#### 2. Path Validation Issues

**Path Recomputation** (in `ai_core.nim::moveTo`):
- Only triggers if:
  - Agent stuck (oscillating 2-3 positions over 6 steps)
  - Distance >= 6 tiles from target
  - Agent forced into stuck state

**Problem**: Stale path cache
- `state.plannedPath` remains valid even if obstacles spawn mid-execution
- Door closes during pathfinding
- Lantern destroyed
- **No step-by-step validation** of planned path

#### 3. Multi-Agent Coordination Races

**From `coordination.nim`**:
- Protection requests expire after 60 steps
- Expiration only checked via `clearExpiredRequests()` (not every step)
- Duplicate detection only checks recent 10 steps
- Defense requests accumulate without clearing
- **No priority system** for fulfilling requests

**Race Conditions**:
1. **Harvesting Race**: Multiple agents target same resource
2. **Building Target Race**: Multiple builders cache same building position
3. **Multi-step Delays**: Cache checked at turn start, but 1+ steps delay before reaching target

#### 4. Economy Bottleneck Detection Issues

**From `economy.nim`**:
- Snapshot circular buffer (60-step window)
- Can have stale snapshots if team is idle
- Flow rate requires 2 snapshots minimum → false negatives early game
- Hardcoded thresholds, not adaptive

### Invalid Action Rates (from Previous Analysis)

| Role | Invalid Action Rate | Primary Causes |
|------|---------------------|----------------|
| Gatherer | 13.9% | Stale cached positions, water irrigation races, missing resource handling |
| Fighter | 12.7% | Cached enemy validation gaps, divider defense placement failures, cooldown races |
| Builder | 9.0% | Wall ring position races, pop cap house building competition, spacing issues |

---

## Test Coverage Summary

### Test Infrastructure
- **Main Harness**: `/home/relh/gt/tribal_village/tests/ai_harness.nim` (1,709 lines)
- **Domain Tests**: 18 files, ~3,200 lines total
- **Test Utilities**: `test_utils.nim` (181 lines)

### Test Results (Sample Run)
```
✅ Mechanics - Resources: 5/5 passed
✅ Mechanics - Biome Bonuses: 7/7 passed
✅ Mechanics - Movement: 7/7 passed
✅ Mechanics - Combat: 7/7 passed
✅ Mechanics - Training: 5/5 passed
✅ Mechanics - Siege: 4/4 passed
✅ Mechanics - Construction: 5/5 passed
✅ AI - Gatherer: 7/7 passed
✅ AI - Builder: 14/14 passed
✅ AI - Fighter: 5/5 passed
✅ AI - Combat Behaviors: 4/4 passed
✅ AI - Stance Behavior: 4/4 passed
```

**Total**: 70+ tests passing

### Coverage Areas
- ✅ Resource mechanics (depletion, gathering, biomes)
- ✅ Combat system (damage, armor, class bonuses, siege)
- ✅ Movement (terrain penalties, boats, swapping)
- ✅ AI behaviors (gathering, building, fighting, fleeing)
- ✅ Coordination (garrison, production queues, requests)
- ✅ Tech tree (blacksmith, university, castle, unit upgrades)
- ✅ Victory conditions (conquest, wonder, relic, king-of-hill)

### Test Pattern Example
```nim
suite "AI - Gatherer":
  test "drops off carried wood":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.inventoryWood = 10
    let stockpile = addBuilding(env, Stockpile, ivec2(10, 9), 0)

    env.stepAction(0, useAction(agent.pos, stockpile.pos))
    check agent.inventoryWood == 0
    check getStockpile(env, 0, ResourceWood) == 10
```

---

## P1 Gaps (Updated)

### Original P1 List (from Audit)
1. ~~Expose Control APIs to Python~~ **✅ ALREADY DONE** (stance, garrison, production, research all exposed)
2. Fix AI Invalid Action Rate **❌ STILL NEEDED** (12-14% rate)
3. Formation & Group Tactics **❌ NOT IMPLEMENTED**

### Revised P1 Gaps

#### P1.1 - Fix Invalid Action Rate (HIGH PRIORITY)
**Target**: Reduce from 12-14% to < 5%

**Required Changes**:
1. **Pre-validate cached positions** (ai_core.nim)
   - Check resource still exists AND has inventory before moving
   - Add timestamp/generation to cache entries
   - Invalidate cache if world generation changed

2. **Implement reservation system** (coordination.nim)
   - Agents "claim" resources/buildings before moving
   - Other agents skip claimed targets
   - Claims expire after N steps or on agent death

3. **Add step-by-step path validation** (ai_core.nim::moveTo)
   - Check next tile in plannedPath before executing move
   - Recompute path if blocker detected
   - Reduce stuck detection window from 6 to 3-4 steps

4. **Improve coordination request handling** (coordination.nim)
   - Call clearExpiredRequests() every step
   - Add priority system for request fulfillment
   - Prevent duplicate requests within 30 steps

**Estimated Impact**: 60-80% reduction in invalid actions

#### P1.2 - Expose Missing Query APIs (MEDIUM PRIORITY)
**Target**: Enable external agents to query internal state

**Required APIs** (ffi.nim additions):
```nim
# Difficulty Control
tribal_village_get_difficulty(env, teamId) -> float
tribal_village_set_difficulty(env, teamId, difficulty: float)
tribal_village_set_adaptive_difficulty(env, teamId, enabled: bool)

# Threat Map Queries
tribal_village_get_nearest_threat(env, agentId) -> (x, y, strength)
tribal_village_get_threats_in_range(env, agentId, radius) -> array of threats
tribal_village_has_known_threats(env, teamId) -> bool

# Fog of War Queries
tribal_village_is_tile_revealed(env, teamId, x, y) -> bool
tribal_village_get_revealed_tile_count(env, teamId) -> int
```

**Estimated Effort**: 2-3 hours (straightforward FFI wrappers)

#### P1.3 - Implement Basic Formation System (MEDIUM PRIORITY)
**Target**: Line and box formations for fighter groups

**Required Components**:
1. Formation types enum (Line, Box, Wedge, Scatter)
2. Formation state per control group
3. Formation position calculation
4. Movement coordination within formation

**Estimated Effort**: 1-2 days for basic line/box formations

#### P1.4 - Add Missing Command APIs (LOW PRIORITY)
**Target**: Stop, Hold Position, Follow

**Required APIs**:
```nim
tribal_village_stop_agent(agentId)
tribal_village_hold_position(agentId, enabled: bool)
tribal_village_follow_agent(agentId, targetAgentId)
```

**Estimated Effort**: 4-6 hours

---

## Recommendations

### Immediate Actions (This Week)

1. **Create P1.1 Task**: Fix invalid action rate
   - Start with pre-validation of cached positions
   - Implement basic reservation system
   - Add step-by-step path validation

2. **Create P1.2 Task**: Expose query APIs
   - Low-hanging fruit, high value for external agents
   - Enables better decision-making from Python

3. **Profile Release Build**: Current profiling used debug build
   - `-d:release` flag should improve performance 3-5×
   - Measure release build performance for accurate baseline

### Next Phase (Next Week)

4. **Implement Formation System** (P1.3)
   - Start with line formation (simplest)
   - Add box formation once line works
   - Test with fighter groups

5. **Add Missing Commands** (P1.4)
   - Stop, Hold Position, Follow
   - Low effort, completes command surface

### Performance Optimization (Future)

6. **Spatial Index Remaining Hotpaths**
   - `nearestFriendlyBuildingDistance`
   - `hasTeamLanternNear`
   - `optFighterLanterns`
   - **Expected gain**: 15-25% AI time reduction

7. **Release Build Performance Testing**
   - Current: 3.0 steps/sec debug build
   - Target: 10-15 steps/sec release build
   - **Expected gain**: 3-5× throughput

---

## Appendix: Key File Paths

### AI Core
- `/home/relh/gt/tribal_village/src/scripted/ai_types.nim`
- `/home/relh/gt/tribal_village/src/scripted/ai_core.nim`
- `/home/relh/gt/tribal_village/src/scripted/ai_options.nim`

### Roles
- `/home/relh/gt/tribal_village/src/scripted/gatherer.nim`
- `/home/relh/gt/tribal_village/src/scripted/builder.nim`
- `/home/relh/gt/tribal_village/src/scripted/fighter.nim`

### Support Systems
- `/home/relh/gt/tribal_village/src/scripted/coordination.nim`
- `/home/relh/gt/tribal_village/src/scripted/economy.nim`

### FFI & Control
- `/home/relh/gt/tribal_village/src/ffi.nim`
- `/home/relh/gt/tribal_village/src/agent_control.nim`

### Testing
- `/home/relh/gt/tribal_village/tests/ai_harness.nim`
- `/home/relh/gt/tribal_village/tests/domain_*.nim`

### Profiling
- `/home/relh/gt/tribal_village/scripts/profile_ai.nim`
- `/home/relh/gt/tribal_village/scripts/profile_env.nim`
- `/home/relh/gt/tribal_village/scripts/profile_roles.nim`

---

**End of Analysis**
