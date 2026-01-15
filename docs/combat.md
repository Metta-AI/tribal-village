# Combat System Notes

Date: 2026-01-13
Owner: Design / Systems
Status: Draft

## Overview
We introduced AoE-style class counters using explicit bonus damage by unit class, plus per-unit combat overlays and distinct bonus-hit flashes. This improves readability and makes the counter system visible while also emitting richer action tint observation codes for agents.

## Counter Bonuses (Class vs Class)
The counter system lives in `src/combat.nim` as a lookup table:
- `BonusDamageByClass[attacker][target]`

Current intent:
- **Archer > Infantry** (UnitArcher gets bonus vs UnitManAtArms)
- **Infantry > Cavalry** (UnitManAtArms gets bonus vs UnitScout / UnitKnight)
- **Cavalry > Archer** (UnitScout / UnitKnight get bonus vs UnitArcher)

Villagers, monks, and siege currently have no class bonus.

To tune counters:
- Adjust values in `BonusDamageByClass`.
- Keep bonuses small but decisive (e.g., +1 or +2) to preserve readable outcomes without making fights one-sided.

## Structure Bonus (Siege vs Buildings)
Structure bonus damage is handled in `applyStructureDamage` using `SiegeStructureMultiplier`.
- Only siege units receive the multiplier.
- The bonus uses the same critical-hit overlay as class counters.

## Critical-Hit Overlay
When a bonus applies (class counters or siege-vs-structure), the target tile receives a distinct action tint:
- `BonusDamageTint` in `src/combat.nim`
- Applied via `env.applyActionTint` when bonus damage > 0

This makes counter hits visually identifiable in the renderer (a "critical hit" signal) and emits a specific `TintLayer` code for bonus hits. Bonus flashes now use **per‑attacker colors** so you can tell which unit type scored the critical hit.

## Action Tint Observation Codes
The action tint layer now exposes more detail so agents can tell what kind of event occurred:
- Per-unit attack codes (villager, man-at-arms, archer, scout, knight, monk, battering ram, mangonel, boat)
- Tower and castle attack codes
- Heal codes (monk heal vs bread heal)
- Shield code for armor band flashes
- Bonus/critical hit code
- Mixed code when multiple events overlap on the same tile

## Tank Auras (Defensive)
- **Man-at-Arms**: 3x3 defensive aura (gold tint).
- **Knight**: 5x5 defensive aura (gold tint).
- Allies standing inside the aura take **half damage** (rounded up, minimum 1 before armor).
- Overlapping tank auras do not stack; the strongest defensive aura applies.

## Monk Healing Aura
- If any ally within a monk’s 5x5 area is injured, the monk emits a green healing aura.
- Allies in the 5x5 heal **1 HP per step** (no stacking across multiple monks).
- The aura is visible as a 5x5 green tint; healing occurs only when needed.

## DPS Attack Patterns (Visual + Damage)
- **Archer**: line shot to range (stops on first hit).
- **Scout**: short jab (2-tile line, stops on first hit).
- **Battering Ram**: 2-tile line strike (stops on first hit).
- **Mangonel**: widened area strike (5-wide line over its range).
- **Boat**: 3-wide forward band (broadside).

## Cavalry Movement
- **Scouts** and **Knights** attempt to move 2 tiles per step; if blocked, they stop before the obstacle.

## Why This Change
- AoE-like gameplay relies on clear, readable counters.
- Bonus damage makes the counter loop deterministic and consistent across combat scales.
- The overlay provides immediate feedback without adding new UI systems.

## Future Improvements (Optional)
- Class-specific overlays (different tint per counter type).
- Stronger feedback on siege vs buildings.
- Particle/sound hooks in the renderer for critical hits.
- Balance pass once training costs and resource scarcity are tuned.
