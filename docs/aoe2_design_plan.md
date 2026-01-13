# AoE2-Inspired Dynamics Development Plan (Tribal Village)

Date: 2026-01-13
Owner: Design / Systems
Status: Draft

## 0) Scope & Non-Goals

### Current State
- Housing/population exists and is used by the simulation. Houses and Town Centers provide pop cap.
- No age gates or explicit win-by-elimination objectives are required for core gameplay.

### AoE2-Style Meaning
- AoE2 uses housing pressure, age gates, and conquest as major pacing mechanisms. We are **not** adopting those.

### Changes Needed
- **None.** Keep current housing setup exactly as-is. Do not add age gates or conquest win conditions.

---

## 1) Economy & Resource Pressure

### Current State
- Resource items: wood, wheat, gold, stone, water, etc. (item inventories). Team stockpiles aggregate wood/stone/gold/water/food.
- Drop-off buildings (Town Center, Granary, Lumber Camp, Quarry, Mining Camp, Dock) add resources to team stockpiles.
- Market exists and can convert stockpile resources to food/gold.

### AoE2-Style Meaning
- AoE2 economy is driven by four core resources (wood/food/gold/stone) with different strategic roles. Gold and stone are high-impact and limited; food/wood are high-volume.
- Resource flow, drop-off placement, and sustainable food vs. early food sources are major macro decisions.

### Changes Needed
- **Tune** gold/stone scarcity and resource costs to make them strategic constraints.
- **Emphasize** multiple food sources and the transition to sustainable food (already present via wheat/bread/meat/plant).
- **No structural changes required**; focus on tuning costs/weights and potentially spawn distributions.

---

## 2) Unit Classes & Counter System

### Current State
- Unit classes: Villager, Man-at-Arms, Archer, Scout, Knight, Monk, Siege.
- Combat includes armor absorption, spear AoE strikes, ranged attack ranges, and healing by monks.

### AoE2-Style Meaning
- AoE2 relies on a readable counter loop (archer > infantry, spear > cavalry, cavalry > archer), with siege as a structural breaker.
- Counters should be decisive at scale, not subtle.

### Changes Needed
- **Balance tuning** only: clarify counter outcomes (damage/armor/range adjustments).
- Consider explicit bonus damage modifiers per class matchup (optional, if needed for clarity).

---

## 3) Siege & Fortification Dynamics

### Current State
- Walls, doors, town centers, and other buildings create choke points.
- Siege units exist and are trainable; doors have HP and can be damaged.

### AoE2-Style Meaning
- Fortifications should shape movement and raid routes; siege should be the efficient solution to hardened defenses.

### Changes Needed
- **Balance tuning** so siege clearly outperforms regular units at breaking defenses.
- Ensure defenses are meaningful without siege (slow to break, strong HP).
- No new mechanics required.

---

## 4) Market / Resource Conversion

### Current State
- Market exists; it converts stockpiled resources into food/gold with inefficiency.

### AoE2-Style Meaning
- Markets enable late-game pivots and mitigate gold scarcity while preserving a cost/tax.

### Changes Needed
- **Tune** conversion rates to match desired scarcity (avoid infinite gold via perfect conversion).
- No new systems required.

---

## 5) Map Control & Territory Feel

### Current State
- Tint system reflects team influence (agents, lanterns) and tumor influence; frozen tiles are non-interactable.
- Lanterns are a primary tool for spreading team tint.

### AoE2-Style Meaning
- Map control should feel valuable even without explicit age gates: forward control means better access, safer economy, and stronger staging.

### Changes Needed
- **Optional**: adjust tint influence radius/strength for clearer territory control.
- **Optional**: align resource spawns or incentives to promote forward outposts.

---

## 6) Civilization / Team Asymmetry

### Current State
- Teams currently share the same unit access and costs.

### AoE2-Style Meaning
- AoE2 civs feel distinct via tech tree differences and small systemic bonuses.

### Changes Needed
- **Optional, low-risk**: small team modifiers (gather rate, build cost, unit HP/attack offsets).
- Avoid asymmetric rules that break the shared action/obs interface.

---

## 7) UI / Readability

### Current State
- Tile tint shows influence; action tints show combat/heal flashes.
- Rendering provides full-map RGB and ANSI.

### AoE2-Style Meaning
- AoE2 communicates control and counters visually; players quickly read map control and combat outcomes.

### Changes Needed
- **Optional**: strengthen tint contrast or add legend cues in render overlay.
- Maintain readability for RL agents (avoid noisy overlays in observation layers).

---

## 8) Scoring / End-of-Episode Metric (Tint Territory)

### Current State
- No explicit score-based win condition tied to map control.
- Tint data exists per tile in `computedTintColors` and tumor tint is distinct (Clippy).

### AoE2-Style Meaning
- AoE2 often rewards territorial control indirectly via resources and pressure. For TV, we can make territory explicit without changing core mechanics.

### Changes Needed
- **Add** a scoring function at a fixed horizon (e.g., step ~5000) that:
  - Scores tiles by nearest tint color to each team and Clippy.
  - Uses `computedTintColors` only (ignore base biome and action tints).
  - Ignores water/blocked tiles if desired.
- Variants: final-state only, rolling average (last N steps), or area-under-curve.

---

## Summary of Proposed Changes
- **Must-have**: doc clarity + scoring metric spec for tint-territory.
- **Should-have**: tuning for resource scarcity and unit counters.
- **Nice-to-have**: civ-style asymmetry, improved territory readability.
- **Non-goals**: housing changes, age gates, conquest win condition.
