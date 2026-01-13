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
- Bonus damage vs class is implemented via a simple lookup table in `src/combat.nim`.

### AoE2-Style Meaning
- AoE2 relies on a readable counter loop (archer > infantry, spear > cavalry, cavalry > archer), with siege as a structural breaker.
- Counters should be decisive at scale, not subtle.

### Changes Needed
- **Balance tuning** only: adjust the bonus damage table and baseline stats to make counters decisive but not oppressive.

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
- Tint data exists per tile in `computedTintColors`; tumor tint is distinct (Clippy).
- Frozen tiles are determined by proximity to Clippy tint but are not currently scored.

### AoE2-Style Meaning
- AoE2 rewards territorial control indirectly through eco and pressure. For TV, we can make territory explicit via end-of-episode scoring without changing core mechanics.

### Goal (Definition)
At step ~10000 (or `maxSteps`), compute a **territory score** for each team based on the number of tiles whose tint is closest to that team’s tint color, with tumors/clippies treated as an NPC team.

### Data Inputs
- `computedTintColors` per tile (dynamic influence only).
- Team tint colors: `env.teamColors`.
- Clippy tint color: `ClippyTint`.
- Terrain grid (to optionally exclude water/blocked tiles).

### Scoring Algorithm (Deterministic)
1. For each tile (x, y):
   - Skip if `terrain == Water` (optional).
   - Read tint color `C = computedTintColors[x][y]`.
   - If `C.intensity < NeutralThreshold`, count as neutral and continue.
2. Compute color distance for all teams and clippy:
   - `dist(team) = (C.r - team.r)^2 + (C.g - team.g)^2 + (C.b - team.b)^2`
   - `dist(clippy) = (C - ClippyTint)^2`
3. Assign tile ownership to the **minimum distance** entry.
4. Increment that owner’s territory count.

### Outputs
- `territory_score[teamId]` for each team.
- `territory_score_clippy` for NPC tumors.
- Optional derived metrics:
  - `territory_share = score / total_scored_tiles`
  - `neutral_tiles` count

### Parameters (Tunable)
- `NeutralThreshold` (float): minimum tint intensity to count a tile.
- `ScoreWaterTiles` (bool): whether water tiles are included.
- `ScoreMode` (enum):
  - `FinalState`: compute only at episode end.
  - `RollingAverage`: average over last N steps.
  - `AreaUnderCurve`: sum per-step scores across the episode.
- `ScoreHorizonSteps` (int): default ~10000 (or mirror `maxSteps`).

### Implementation Notes
- Use `computedTintColors` (not `combinedTileTint`) to avoid bias from base biome colors.
- Ignore `actionTint` overlays; these are visual feedback, not territory.
- Clippy is treated as a distinct “team” in scoring but does not need an agent ID.

### Minimal Implementation Plan
1. Add a scoring function in `environment.nim` (or a dedicated scoring module):
   - `proc scoreTerritory*(env: Environment): TerritoryScore`
2. Call it when `currentStep >= ScoreHorizonSteps` (or `maxSteps`) and store results on the environment.
3. Expose scores through the FFI layer (optional; for Python logging).
4. Log summary on episode end for debugging.

### Validation / Sanity Checks
- If no tints present, all tiles should be neutral.
- If a single team tint dominates, that team should score nearly all tiles.
- Clippy should capture tiles if tumor tint dominates or frozen areas spread.

### Changes Needed
- **Add** scoring function and minimal config fields (threshold, horizon, mode).
- **No change** to housing, ages, or win-by-elimination rules.

---

## Summary of Proposed Changes
- **Must-have**: doc clarity + scoring metric spec for tint-territory.
- **Should-have**: tuning for resource scarcity and unit counters.
- **Nice-to-have**: civ-style asymmetry, improved territory readability.
- **Non-goals**: housing changes, age gates, conquest win condition.
