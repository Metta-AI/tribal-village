# AoE2 Design Plan Investigation Report

Date: 2026-01-24
Owner: Engineering / Analysis
Status: Active
Task: tv-vvcz
Investigator: Polecat dag

---

## Executive Summary

Reviewed `docs/aoe2_design_plan.md` against the current codebase implementation. The plan is marked as "In Progress (Civ asymmetry remaining)" which matches reality: **7 of 8 major systems are complete**, with only civilization/team asymmetry explicitly remaining.

---

## 1. Features Planned But Not Yet Implemented

### 1.1 Civilization/Team Asymmetry (Section 6) - **REMAINING**

**Plan states:**
> "Remaining (optional, low-risk): small team modifiers (gather rate, build cost, unit HP/attack offsets). Avoid asymmetric rules that break the shared action/obs interface."

**Current implementation:**
- All 8 teams share identical unit stats, building costs, and gather rates
- No team-specific modifiers exist in `types.nim` or `environment.nim`
- `TeamStockpile` type tracks resources but has no team-specific multipliers

**Actionable improvements:**

| Improvement | Implementation Location | Complexity | Risk |
|-------------|------------------------|------------|------|
| Gather rate modifiers | `src/environment.nim` at `addToStockpile()` | Low | Low |
| Build cost multipliers | `src/registry.nim` at `buildingTrainCosts()` | Low | Low |
| Unit HP/attack offsets | `src/environment.nim` at `applyUnitClass()` | Low | Low |
| Team-specific unit variants | `src/types.nim` add per-team stat arrays | Medium | Medium |

**Suggested implementation approach:**
```nim
# Add to types.nim
type
  TeamModifiers* = object
    gatherRateMultiplier*: float32  # 1.0 = normal
    buildCostMultiplier*: float32   # 1.0 = normal
    unitHpBonus*: array[AgentUnitClass, int]
    unitAttackBonus*: array[AgentUnitClass, int]

# Then apply in relevant procs
```

---

## 2. Interesting Mechanics to Add

Based on AoE2 mechanics that would enhance the current implementation:

### 2.1 High-Value Additions (Low Effort, High Impact)

| Mechanic | AoE2 Reference | Current Gap | Implementation Effort |
|----------|----------------|-------------|----------------------|
| **Relic gold generation** | Relics in Monastery generate gold/min | Relics exist but only drop gold on death | Add tick-based gold to Monastery with Relic |
| **Multiple builder bonus** | 2+ villagers build faster | No construction speed modifier | Track builders per site, scale build time |
| **Blacksmith upgrades** | +1 attack/armor for unit types | No upgrade system | Add team-level upgrade counters |

### 2.2 Medium-Value Additions (Medium Effort)

| Mechanic | AoE2 Reference | Current Gap | Implementation Effort |
|----------|----------------|-------------|----------------------|
| **Garrisoning** | Units enter buildings for protection | No garrison system | Add garrison capacity to buildings |
| **Town bell** | Recall villagers to TC | No recall mechanic | Add special action for TC use |
| **Research at University** | Tech tree progression | University only crafts | Add research queue system |
| **Trade routes** | Market-to-Market gold generation | Market is conversion-only | Add trade cart units |

### 2.3 Lower Priority (High Effort or Lower Impact)

| Mechanic | Notes |
|----------|-------|
| Formations | Complex pathfinding, may not suit RL training |
| Unique units | Requires civ asymmetry first |
| Naval expansion | Boats exist but limited combat |
| Sheep scouting | Would require animal ownership transfer |

---

## 3. Discrepancies Between Plan and Implementation

### 3.1 Minor Discrepancies

| Plan Section | Plan Statement | Actual Implementation | Severity |
|--------------|----------------|----------------------|----------|
| Section 1 | Water is a resource | `StockpileResource` includes `ResourceWater` but rarely used | Low |
| Section 4 | Market converts to food/gold | `DefaultMarketBuyFoodNumerator/Denominator` exists | None - Working |
| Section 8 | Territory scoring at episode end | `scoreTerritory()` in `environment.nim` works correctly | None - Working |

### 3.2 Undocumented Features

The following exist in code but aren't mentioned in the design plan:

1. **Temple/Hybridization system** (`TempleInteraction`, `TempleHybridRequest` in types.nim)
   - Appears to be an evolution/breeding mechanic
   - Not referenced in AoE2 plan (custom mechanic)

2. **Goblin NPC faction** (GoblinHive, GoblinHut, GoblinTotem, UnitGoblin)
   - Complete hostile NPC system
   - Not part of AoE2 inspiration but adds gameplay depth

3. **Tumor/Clippy system** (Spawner, Tumor, frozen tiles)
   - Creep spread mechanic
   - Environmental hazard not in AoE2

4. **Wolf pack and cow herd systems** (pack/herd IDs, drift mechanics)
   - Sophisticated animal AI
   - Exceeds AoE2's simple herdable animals

### 3.3 Potential Plan Updates Needed

The design plan could be updated to document:
- The Goblin faction as a design decision
- The Temple hybridization system purpose
- The Tumor/Clippy mechanic as environmental pressure

---

## 4. Specific Actionable Improvements

### Priority 1: Quick Wins

1. **Add relic gold generation** - When a Relic is in a Monastery's inventory, add gold to team stockpile each tick
   - File: `src/step.nim`
   - Effort: ~20 lines

2. **Document team modifier hooks** - Even without implementing asymmetry, add the data structures
   - File: `src/types.nim`
   - Effort: ~30 lines

### Priority 2: Impactful Features

3. **Blacksmith upgrade system** - Add counters for attack/armor upgrades purchasable at Blacksmith
   - Files: `src/types.nim`, `src/step.nim`, `src/combat.nim`
   - Effort: ~100 lines

4. **Multi-builder construction bonus** - Track villagers at construction sites
   - Files: `src/step.nim`
   - Effort: ~50 lines

### Priority 3: Design Documentation

5. **Update aoe2_design_plan.md** to include:
   - Temple hybridization section
   - Goblin faction section
   - Tumor/Clippy environmental mechanics
   - Current relic functionality

---

## 5. Code Quality Observations

While investigating, noted the following code patterns:

1. **Well-structured registries** - `BuildingRegistry`, `ThingCatalog`, `TerrainCatalog` make adding content easy

2. **Clear separation** - Combat in `combat.nim`, items in `items.nim`, types in `types.nim`

3. **Tunable constants** - Default values at module level (e.g., `DefaultMarketCooldown`, `DefaultTumorBranchChance`)

4. **Ready for asymmetry** - The `teamId` tracking is comprehensive; adding modifiers would be straightforward

---

## Conclusion

The aoe2_design_plan.md is accurate and well-maintained. The single remaining item (civilization asymmetry) is clearly marked and implementation paths are straightforward.

**Recommended next steps:**
1. Create beads for the Priority 1 quick wins
2. Decide on civilization asymmetry direction (symmetric for RL fairness vs. asymmetric for variety)
3. Update design doc with undocumented systems (Temple, Goblin, Tumor)

---

*Report generated by polecat dag*
