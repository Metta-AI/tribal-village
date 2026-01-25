# Building Interaction & Siege Mechanics Analysis

## Executive Summary

The siege transformation mechanic **IS implemented** but has significant conditions. Villagers will train at siege workshops to become battering rams or mangonels, but only when they see enemy structures, the workshop exists, and resources are available.

## Key Question: Do fighters transform into siege engines when they see enemy walls?

**YES, but with conditions:**
1. Must be a `UnitVillager` (trained units cannot retrain)
2. Must see enemy structure within `ObservationRadius` (5 tiles)
3. `SiegeWorkshop` or `MangonelWorkshop` must exist on their team
4. Team must have required resources (3 Wood + 2 Stone for ram, 4 Wood + 3 Stone for mangonel)

The transformation happens via `FighterTrain` option in `src/scripted/fighter.nim:441-472`.

---

## Siege Units

| Unit | Building | Cost | HP | Damage | Special |
|------|----------|------|-----|--------|---------|
| Battering Ram | SiegeWorkshop | 3 Wood + 2 Stone | 18 | 2 | 3x vs structures |
| Mangonel | MangonelWorkshop | 4 Wood + 3 Stone | 12 | 2 | 3x vs structures, AoE, prioritizes structures |

## How Agents Use Buildings

### Finding Buildings
- Uses `findNearestFriendlyThingSpiral()` - spiral search from agent position
- Buildings found by type (e.g., `TownCenter`, `Barracks`, etc.)

### Retreat/Shelter (Injured Agents)
**Trigger:** HP below 33% (`hp * 3 <= maxHp`)

**Implementation:** `optFighterRetreat()` in `src/scripted/fighter.nim:137-150`

**Safe positions sought (in order):**
1. Outpost
2. Barracks
3. TownCenter
4. Monastery

### Building Repair
**NOT IMPLEMENTED** - Buildings cannot be repaired once damaged.

---

## Enemy Structure Detection

`fighterSeesEnemyStructure()` in `src/scripted/fighter.nim:50-61`:
- Checks for enemy things that are buildings
- Must be in `AttackableStructures` = {Wall, Door, Outpost, GuardTower, Castle, TownCenter}
- Within `ObservationRadius` (5 tiles)

---

## Attack Target Prioritization

### Mangonels (Structure-focused)
| Priority | Target Type |
|----------|-------------|
| 0 (highest) | AttackableStructures |
| 1 | Tumor |
| 2 | Spawner |
| 3 | Agent |

### Other Units (Agent-focused)
| Priority | Target Type |
|----------|-------------|
| 0 (highest) | Tumor |
| 1 | Spawner |
| 2 | Agent |
| 3 | AttackableStructures |

Note: Battering rams follow "Other Units" priority - they do NOT specifically target walls first.

---

## Siege Damage Multiplier

`SiegeStructureMultiplier = 3` defined in `src/types.nim:70`

Applied in `src/combat.nim:41-56`:
```nim
if attacker.unitClass in {UnitBatteringRam, UnitMangonel}:
  damage += damage * (SiegeStructureMultiplier - 1)  # 3x total
```

---

## Code Flow: Siege Transformation

1. Fighter AI runs through options (fighter.nim)
2. `canStartFighterTrain()` checks:
   - Is villager?
   - Does siege building exist?
   - Are resources available?
   - (For siege buildings) Does agent see enemy structure?
3. `optFighterTrain()` moves to building and uses interact action (verb 3)
4. `step.nim` handles training, changes `unitClass`, applies stats via `applyUnitClass()`

---

## Test Coverage

Tests in `tests/ai_harness.nim`:
- Line 201: "siege workshop trains battering ram"
- Line 251: "siege damage multiplier applies vs walls"
- Line 278: "siege prefers attacking blocking wall"
- Line 421: "builds siege workshop after stable"

---

## Identified Gaps

1. **No repair mechanic** - Buildings cannot be healed
2. **Transformation delay** - Requires building + resources + visibility, may not happen fast enough in active combat
3. **Battering rams don't prioritize walls** - They use default target priority (Tumor > Spawner > Agent > Structure), unlike mangonels which prioritize structures
4. **No shelter inside buildings** - Retreat moves toward buildings but doesn't provide additional protection

---

## Recommendations for Improvement

1. **Add repair mechanic** - Allow villagers to repair damaged friendly structures
2. **Battering ram wall priority** - Make battering rams prioritize walls like mangonels do
3. **Emergency siege training** - Lower the visibility threshold or add panic-mode training when base is under attack
4. **Garrison mechanic** - Allow units to enter buildings for protection

---

## Key Files

- `src/scripted/fighter.nim` - Fighter AI including siege training
- `src/scripted/builder.nim` - Builder AI for constructing buildings
- `src/combat.nim` - Damage calculation including siege multiplier
- `src/types.nim` - Constants like SiegeStructureMultiplier
- `src/registry.nim` - Building costs and training costs
- `tests/ai_harness.nim` - Test cases for siege mechanics
