# Tech Trees and Unit Upgrades

Date: 2026-01-28
Owner: Docs / Systems
Status: Draft

## Overview
Three technology systems provide progressive upgrades: Blacksmith upgrades for
stat bonuses, University research for advanced mechanics, and Castle unique
technologies per civilization. Additionally, unit promotion chains allow military
units to upgrade through tiers.

Key files:
- `src/types.nim` (upgrade enums, costs, constants)
- `src/environment.nim` (research and upgrade procs)
- `src/step.nim` (tech effects applied during simulation)
- `src/registry.nim` (training definitions)

## Blacksmith Upgrades
Five upgrade lines with 3 tiers each, researched at Blacksmith buildings:

| Line | Tier 1 | Tier 2 | Tier 3 |
|------|--------|--------|--------|
| Melee Attack | Forging | Iron Casting | Blast Furnace |
| Archer Attack | Fletching | Bodkin Arrow | Bracer |
| Infantry Armor | Scale Mail | Chain Mail | Plate Mail |
| Cavalry Armor | Scale Barding | Chain Barding | Plate Barding |
| Archer Armor | Padded Archer | Leather Archer | Ring Archer |

Each tier grants +1 to the relevant stat (attack or armor). Costs increase per
tier. Research is cumulative -- tier 2 requires tier 1 to be completed first.

## University Research
Nine technologies researched at University buildings:

| Tech | Effect |
|------|--------|
| Ballistics | Improved ranged accuracy |
| Murder Holes | Removes tower minimum attack range |
| Masonry | +10% building HP |
| Architecture | +10% building HP (stacks with Masonry) |
| Siege Engineers | +1 siege range, +20% siege damage |
| Chemistry | +1 ranged attack |
| Heated Shot | Towers deal bonus damage to ships |
| Arrowslits | +1 tower attack |
| Treadmill Crane | +20% building construction speed |

## Castle Unique Technologies
Each team has 2 unique technologies (Castle Age and Imperial Age), providing
civilization-specific bonuses. 16 total technologies across 8 teams. Examples:
- **Yeomen** (Team 0, Castle): +1 archer range, +2 tower attack
- **Kataparuto** (Team 0, Imperial): +3 trebuchet attack

Researched at Castle buildings. Each team can only research their own unique techs.

## Unit Promotion Chains
Three promotion chains upgrade all existing units of a type when researched:

| Building | Tier 1 | Tier 2 | Tier 3 |
|----------|--------|--------|--------|
| Barracks | Man-at-Arms | Long Swordsman | Champion |
| Stable | Scout | Light Cavalry | Hussar |
| Archery Range | Archer | Crossbowman | Arbalester |

Research costs: Tier 2 = 3 food + 2 gold, Tier 3 = 6 food + 4 gold.

When an upgrade is researched:
1. All existing units of that type automatically upgrade (HP ratio preserved).
2. Future production creates the upgraded version via `effectiveTrainUnit()`.
3. Stats (HP, attack, armor) increase with each tier.
