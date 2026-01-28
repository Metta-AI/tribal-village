# Siege Fortifications Plan Investigation Report

**Issue:** tv-snmi
**Date:** 2026-01-24
**Investigator:** polecat/ace

## Executive Summary

The siege_fortifications_plan.md design document is **largely implemented**. All core mechanics (destructible walls, siege damage multiplier, guard towers, castle auto-attack) are working. However, one key gap exists: **battering rams don't prioritize walls** as intended by the design.

## Planned vs Implemented Status

| Feature | Plan | Status | Notes |
|---------|------|--------|-------|
| Wall HP = 10 | Yes | **Implemented** | `types.nim:61` |
| Siege x3 vs buildings | Yes | **Implemented** | `combat.nim:44-48` |
| Guard Tower range = 4 | Yes | **Implemented** | `types.nim:68` |
| Castle range = 6 | Yes | **Implemented** | `types.nim:69` |
| Siege Workshop -> Ram | Yes | **Implemented** | `registry.nim:352` |
| Mangonel Workshop -> Mango | Yes | **Implemented** | `registry.nim:353` |
| Guard Tower auto-attack | Yes | **Implemented** | `step.nim:1395-1396` |
| Castle auto-attack | Yes | **Implemented** | `step.nim:1397-1398` |
| Walls destructible | Yes | **Implemented** | `combat.nim:52-56` |
| Ram "move forward, attack blocker" | Yes | **Partial** | See gap below |
| Mangonel prioritizes structures | Yes | **Implemented** | `ai_core.nim:398-400` |

## Critical Gap: Battering Ram Targeting

### Plan Says
> "If blocked by any thing (unit/building/wall/door), attack that target."

Battering rams should **prioritize structures** like mangonels do.

### Implementation Reality (ai_core.nim:397-412)

```nim
proc targetPriority(kind: ThingKind): int =
  if agent.unitClass == UnitMangonel:
    if kind in AttackableStructures: return 0  # Mangonels prioritize structures
    # ...
  else:  # ALL other units including BatteringRam
    case kind
    of Tumor: 0
    of Spawner: 1
    of Agent: 2
    else:
      if kind in AttackableStructures: 3 else: 4  # Structures are LAST priority
```

**Problem:** Battering rams use the same priority as regular fighters (Tumor > Spawner > Agent > Structure). This means a battering ram will attack a nearby enemy villager instead of the wall it's supposed to break through.

### Recommended Fix

In `src/scripted/ai_core.nim:397-412`, add a condition for `UnitBatteringRam`:

```nim
proc targetPriority(kind: ThingKind): int =
  if agent.unitClass in {UnitMangonel, UnitBatteringRam}:  # Add BatteringRam
    if kind in AttackableStructures: return 0
    # ... rest of structure-priority logic
```

**Impact:** Low risk, localized change. Makes rams behave as the design intended.

## Other Identified Gaps (Not in Original Plan)

These gaps were identified in `docs/building_siege_analysis.md` and may warrant future consideration:

| Gap | Description | Priority |
|-----|-------------|----------|
| No repair mechanic | Buildings cannot be healed once damaged | Low |
| No garrison mechanic | Units cannot shelter inside buildings | Low |
| Siege training visibility | Requires seeing enemy structure to train siege | Design intent |

## Asset Coverage

All required assets from the plan exist in `data/prompts/assets.tsv`:
- `battering_ram.png` (line 69)
- `mangonel.png` (line 70)
- `guard_tower.png` (line 56)
- `siege_workshop.png` (line 63)
- `mangonel_workshop.png` (line 64)
- Oriented sprites for ram and mangonel (lines 94-95)

## Recommendations

### Immediate (P2)
1. **Fix battering ram targeting priority** to prioritize structures like mangonels do

### Future Consideration (P3)
2. Add building repair mechanic (villagers can repair damaged structures)
3. Consider garrison mechanic for defensive play

## Files to Modify

For the battering ram fix:
- `src/scripted/ai_core.nim:397-412` - Add `UnitBatteringRam` to structure-priority condition

## Test Coverage

Existing tests in `tests/ai_harness.nim`:
- Line 201: "siege workshop trains battering ram" - verifies training works
- Line 251: "siege damage multiplier applies vs walls" - verifies x3 damage
- Line 278: "siege prefers attacking blocking wall" - **tests action execution, not AI priority**

**Clarification on line 278:** This test uses `env.stepAction()` to directly issue an attack command at a wall. It verifies walls take damage correctly when attacked, but does NOT test the AI's autonomous target selection. The gap in `targetPriority()` means the scripted AI may choose wrong targets, even though manual attacks work correctly.

**Recommended test addition:** A test that places a ram adjacent to both a wall and an enemy agent, then calls `decideAction()` to verify the AI chooses to attack the wall.

---

**Conclusion:** The siege_fortifications_plan.md is well-implemented with one notable exception: battering rams should prioritize wall targets but currently don't. A single-line code change can fix this alignment issue.
