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

This makes counter hits visually identifiable in the renderer (a "critical hit" signal) and emits a specific `TintLayer` code for bonus hits.

## Action Tint Observation Codes
The action tint layer now exposes more detail so agents can tell what kind of event occurred:
- Per-unit attack codes (villager, man-at-arms, archer, scout, knight, monk, battering ram, mangonel, boat)
- Tower and castle attack codes
- Heal codes (monk heal vs bread heal)
- Shield code for armor band flashes
- Bonus/critical hit code
- Mixed code when multiple events overlap on the same tile

## Why This Change
- AoE-like gameplay relies on clear, readable counters.
- Bonus damage makes the counter loop deterministic and consistent across combat scales.
- The overlay provides immediate feedback without adding new UI systems.

## Future Improvements (Optional)
- Class-specific overlays (different tint per counter type).
- Stronger feedback on siege vs buildings.
- Particle/sound hooks in the renderer for critical hits.
- Balance pass once training costs and resource scarcity are tuned.
