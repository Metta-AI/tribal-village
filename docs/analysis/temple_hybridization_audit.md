# Temple Hybridization Audit Report

**Issue:** tv-ej6n
**Date:** 2026-01-24
**Investigator:** cheedo

## Executive Summary

The temple hybridization system is **fully implemented** but **partially enabled**. The core mechanics work correctly: temples spawn hybrid children when two villagers are adjacent, and hybrid roles are created via genetic crossover. However, the `ScriptedTempleAssignEnabled` flag is hardcoded to `false`, meaning hybrid roles are generated but **not assigned** to the spawned children.

## 1. How Temple Hybridization Works

### Trigger Mechanism (Automatic)
- **Location:** `src/step.nim` lines 1963-2034
- Each game step, every temple is checked for adjacent villagers
- Requirements for spawn:
  - Two different living, non-goblin agents within 8 adjacent tiles
  - Both agents on the same team
  - Team has room under population cap
  - Parents' home altar has at least 1 heart
- Consumes 1 heart from altar, spawns dormant child, enqueues `TempleHybridRequest`
- Temple cooldown: 25 steps between spawns

### Role Recombination
- **Location:** `src/scripted/ai_defaults.nim` lines 603-627
- `processTempleHybridRequests` handles queued spawns
- `recombineRoles` performs crossover of parent role tiers
- 35% chance to inject random behavior
- Optional mutation based on `ScriptedRoleMutationChance`
- New role registered with `origin = "temple"`

### Role Assignment (Currently Disabled)
- `ScriptedTempleAssignEnabled = false` (line 401 in ai_defaults.nim)
- When false: hybrid role is created and added to pool, but child gets default assignment
- When true: would reset `agentsInitialized[childId]` to force hybrid role assignment

## 2. Implementation vs. Documentation

| Aspect | Documented | Implemented | Status |
|--------|-----------|-------------|--------|
| Temple placement | placeTemple in spawn.nim | Correct | ACCURATE |
| Adjacency detection | Two adjacent agents | 8-tile radius | ACCURATE |
| Team requirement | Same team | Same team | ACCURATE |
| Heart cost | One heart from altar | Uses MapObjectAltarRespawnCost | ACCURATE |
| Spawn cooldown | "Short cooldown" | 25 steps | ACCURATE |
| Role recombination | Via recombineRoles | Crossover of tiers | ACCURATE |
| Auto-assignment | "Not assigned by default" | ScriptedTempleAssignEnabled=false | ACCURATE |
| BehaviorTempleFusion | "No explicit action needed" | Exists but unused | ACCURATE |

**Conclusion:** Documentation accurately reflects implementation state.

## 3. Actionable Improvements

### HIGH PRIORITY

#### 3.1 Enable Hybrid Role Assignment
**Issue:** Children don't get their hybrid roles
```nim
# Current (ai_defaults.nim:401)
const ScriptedTempleAssignEnabled = false

# Recommended: Make configurable
var ScriptedTempleAssignEnabled* = true
```
**Rationale:** This is the entire point of hybridization - without assignment, hybrids just get default roles. Since "we recently enabled temple hybrids", this should be the first fix.

#### 3.2 Add Temple Assignment Analytics
**Issue:** No visibility into hybrid success
```nim
# Add to processTempleHybridRequests
logHybridCreation(parentARole, parentBRole, hybridRole, childId)
```
Track:
- Hybrid roles created per game
- Parent role combinations
- Hybrid survival rates vs. baseline

### MEDIUM PRIORITY

#### 3.3 Balance Heart Cost
**Issue:** Currently uses `MapObjectAltarRespawnCost` (likely 1)
Consider:
- Increase cost for stronger parents
- Scale by hybrid generation (g2, g3 hybrids cost more)
- Award hearts for hybrid achievements

#### 3.4 Expose BehaviorTempleFusion
**Issue:** 1% random trigger is too rare
```nim
# Current (options.nim:784)
randChance(controller.rng, 0.01)  # 1% chance

# Consider: skill-based approach
randChance(controller.rng, 0.10) or agent.hasPartner()
```
**Rationale:** Let agents actively seek reproduction, not rely on random wandering.

#### 3.5 Parent Selection Heuristics
**Issue:** First two adjacent agents become parents (arbitrary)
Consider:
- Prefer agents with complementary roles
- Prefer experienced/older agents
- Avoid recently-spawned agents as parents

### LOW PRIORITY / FUTURE

#### 3.6 Temple Upgrades
- Multiple temples per map (currently 1)
- Temple tiers with different effects
- Team-controlled temples

#### 3.7 Hybrid Visibility
- Visual indicator for hybrid villagers
- Display hybrid lineage/generation
- Hybrid-specific behaviors (e.g., temple affinity)

#### 3.8 Genetic Diversity Protection
- Track inbreeding coefficient
- Prevent parent-child / sibling breeding
- Bonus for diverse gene pools

## 4. Code Locations Reference

| Component | File | Lines |
|-----------|------|-------|
| Temple placement | src/spawn.nim | 656-683 |
| Hybrid trigger | src/step.nim | 1963-2034 |
| Request processing | src/scripted/ai_defaults.nim | 603-627 |
| Role recombination | src/scripted/evolution.nim | 69-88 |
| Assignment flag | src/scripted/ai_defaults.nim | 401 |
| BehaviorTempleFusion | src/scripted/options.nim | 783-793, 985-991 |
| TempleHybridRequest type | src/types.nim | 411-416 |

## 5. Recommended Next Steps

1. **Immediate:** Enable `ScriptedTempleAssignEnabled` and test hybrid role assignment
2. **Short-term:** Add analytics to measure hybrid effectiveness
3. **Medium-term:** Balance heart costs and parent selection
4. **Long-term:** Consider temple upgrades and genetic diversity mechanics

---
*Report generated as part of tv-ej6n investigation*
