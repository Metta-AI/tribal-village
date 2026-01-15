# AoE2-Inspired Dynamics Development Plan (Tribal Village)

Date: 2026-01-13
Owner: Design / Systems
Status: In Progress (Civ asymmetry remaining)

## 0) Scope & Non-Goals

### Current State
- Housing/population exists and is used by the simulation. Houses and Town Centers provide pop cap.
- No age gates or explicit win-by-elimination objectives are required for core gameplay.

### AoE2-Style Meaning
- AoE2 uses housing pressure, age gates, and conquest as major pacing mechanisms. We are **not** adopting those.

### Changes Needed
- **None.** Keep current housing setup exactly as-is. Do not add age gates or conquest win conditions.

---

## 1) Economy & Resource Pressure (Complete)

### Current State
- Resource items: wood, wheat, gold, stone, water, etc. (item inventories). Team stockpiles aggregate wood/stone/gold/water/food.
- Drop-off buildings (Town Center, Granary, Lumber Camp, Quarry, Mining Camp, Dock) add resources to team stockpiles.
- Market exists and can convert stockpile resources to food/gold.

### AoE2-Style Meaning
- AoE2 economy is driven by four core resources (wood/food/gold/stone) with different strategic roles. Gold and stone are high-impact and limited; food/wood are high-volume.
- Resource flow, drop-off placement, and sustainable food vs. early food sources are major macro decisions.

### Changes Needed
- **Done.** Tuned gold/stone scarcity and resource costs to make them strategic constraints.
- **Done.** Emphasized multiple food sources and the transition to sustainable food.
- No further structural changes required unless economy balance goals change.

---

## 2) Unit Classes & Counter System (Complete)

### Current State
- Unit classes: Villager, Man-at-Arms, Archer, Scout, Knight, Monk, Battering Ram, Mangonel.
- Combat includes armor absorption, spear AoE strikes, ranged attack ranges, and healing by monks.
- Bonus damage vs class is implemented via a simple lookup table in `src/combat.nim`.
- Training follows a one-building-per-unit approach:
  - Barracks -> Man-at-Arms
  - Archery Range -> Archer
  - Stable -> Scout
  - Siege Workshop -> Battering Ram
  - Mangonel Workshop -> Mangonel
  - Monastery -> Monk
  - Castle -> Knight

### AoE2-Style Meaning
- AoE2 relies on a readable counter loop (archer > infantry, spear > cavalry, cavalry > archer), with siege as a structural breaker.
- Counters should be decisive at scale, not subtle.

### Changes Needed
- **Done.** Balance tuning complete; counters are decisive without being oppressive.

---

## 3) Siege & Fortification Dynamics (Complete)

### Current State
- Walls, doors, town centers, and other buildings create choke points.
- Siege units exist and are trainable; doors have HP and can be damaged.
- Siege training is split across two buildings (Siege Workshop for rams, Mangonel Workshop for mangonels).

### AoE2-Style Meaning
- Fortifications should shape movement and raid routes; siege should be the efficient solution to hardened defenses.

### Changes Needed
- **Done.** Siege vs. defense balance tuned; defenses remain meaningful without siege.
- No new mechanics required.

---

## 4) Market / Resource Conversion (Complete)

### Current State
- Market exists; it converts carried stockpile resources into team stockpiles of food/gold using configurable rates and a cooldown.

### AoE2-Style Meaning
- Markets enable late-game pivots and mitigate gold scarcity while preserving a cost/tax.

### Changes Needed
- **Done.** Conversion rates/cooldown tuned to match scarcity goals.
- No new systems required.

---

## 5) Map Control & Territory Feel (Complete)

### Current State
- Tint system reflects team influence (agents, lanterns) and tumor influence; frozen tiles are non-interactable.
- Lanterns are a primary tool for spreading team tint.

### AoE2-Style Meaning
- Map control should feel valuable even without explicit age gates: forward control means better access, safer economy, and stronger staging.

### Changes Needed
- **Done.** Tint influence and incentives tuned to promote forward control.

---

## 6) Civilization / Team Asymmetry (Remaining)

### Current State
- Teams currently share the same unit access and costs.

### AoE2-Style Meaning
- AoE2 civs feel distinct via tech tree differences and small systemic bonuses.

### Changes Needed
- **Remaining (optional, low-risk)**: small team modifiers (gather rate, build cost, unit HP/attack offsets).
- Avoid asymmetric rules that break the shared action/obs interface.

---

## 7) UI / Readability (Complete)

### Current State
- Tile tint shows influence; action tints show combat/heal flashes.
- Rendering provides full-map RGB and ANSI.

### AoE2-Style Meaning
- AoE2 communicates control and counters visually; players quickly read map control and combat outcomes.

### Changes Needed
- **Done.** Tint contrast/legend cues tuned while preserving RL readability.

---

## 8) Scoring / End-of-Episode Metric (Tint Territory) (Complete)

### Current State
- Territory scoring exists and is run at the episode horizon.
- Tint data exists per tile in `computedTintColors`; tumor tint is distinct (Clippy).
- Frozen tiles are determined by proximity to Clippy tint and currently score like any other tile.

### AoE2-Style Meaning
- AoE2 rewards territorial control indirectly through eco and pressure. For TV, we can make territory explicit via end-of-episode scoring without changing core mechanics.

### Goal (Definition)
At episode end (`env.config.maxSteps`), compute a **territory score** for each team based on the number of tiles whose tint is closest to that team’s tint color, with tumors/clippies treated as an NPC team.

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

### Parameters (Current)
- `DefaultScoreNeutralThreshold = 0.05`
- `DefaultScoreIncludeWater = false`
- Score mode: `FinalState` only (computed at episode end).
- Score horizon: `env.config.maxSteps`

### Implementation Notes
- Use `computedTintColors` (not `combinedTileTint`) to avoid bias from base biome colors.
- Ignore `actionTint` overlays; these are visual feedback, not territory.
- Clippy is treated as a distinct “team” in scoring but does not need an agent ID.

### Implementation (Complete)
- `proc scoreTerritory*(env: Environment): TerritoryScore` is in `src/environment.nim`.
- Called at episode end in `src/step.nim` and stored on the environment.
- Scores are available on `env.territoryScore` for logging/FFI when needed.

### Validation / Sanity Checks
- If no tints present, all tiles should be neutral.
- If a single team tint dominates, that team should score nearly all tiles.
- Clippy should capture tiles if tumor tint dominates or frozen areas spread.

### Changes Needed
- **Done.** Scoring parameters tuned as needed.
- **No change** to housing, ages, or win-by-elimination rules.

---

## Summary of Proposed Changes
- **Complete**: unit counters, siege/fortification dynamics, market conversion tuning, map control readability, UI readability, territory scoring.
- **Remaining (optional)**: civ-style asymmetry.
- **Non-goals**: housing changes, age gates, conquest win condition.
