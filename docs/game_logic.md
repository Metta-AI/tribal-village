# Game Logic Overview

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document describes how the Tribal Village simulation behaves each step, what agents can do,
what systems update automatically, and how the episode ends. It is a code-aligned summary of the
current gameplay rules.

Key implementation files:
- `src/step.nim` (per-step simulation)
- `src/spawn.nim` (map + initial entity placement)
- `src/types.nim` (constants, config, core data types)
- `src/items.nim` (item catalog)
- `src/colors.nim` (clippy tint + frozen tiles)

## Core Loop (per step)
The main loop is `proc step*(env, actions)` in `src/step.nim`.

Order of operations (high level):
1. Decay short-lived effects (combat/heal tints, shields).
2. Remove agents already at 0 HP so they cannot act this step.
3. Apply each alive agent action in ID order.
4. Update world objects (building cooldowns, tower/castle attacks, spawners, wildlife movement).
5. Process tumor branching/spawning.
6. Resolve adjacency deaths for agents/predators touching tumors.
7. Apply tank auras, monk healing auras, and their tints.
8. Remove any agents killed during the step.
9. Respawn dead agents at their altar if hearts and pop-cap allow it; process temple hybrid spawns.
10. Apply per-step survival penalty.
11. Recompute tint overlays (lanterns, tumors, etc.).
12. End episode if max steps reached or all agents are done.

## Map and Terrain
- Map size is derived from `MapWidth`/`MapHeight` in `src/types.nim`.
- Procedural terrain includes rivers/bridges, cliffs/ramps, biomes, and resource clusters.
- Roads can speed movement; fertile tiles enable planting/growth.
- Frozen tiles: a tile is frozen when its combined tint matches the clippy color threshold
  (`src/colors.nim`). Frozen tiles and things on them are non-interactable.

## Teams and Agents
- 8 teams, 125 agent slots each (1000 total). Only 6 are active per team at spawn; the rest
  start dormant and can respawn later.
- Each agent has: position, orientation, HP/max HP, unit class, inventory, and home altar.
- Unit classes include villager, man-at-arms, archer, scout, knight, monk, battering ram,
  mangonel, boat, and goblin.

## Inventory and Stockpiles
- Each agent carries a small inventory (see `MapObjectAgentMaxInventory`).
- Team stockpiles track shared resources: food, wood, stone, gold, water.
- Resources are gathered from nodes (trees, wheat, stone, gold, fish, plants, etc.).
- Corpses and skeletons can store loot and be harvested.

## Actions
Action space is discrete: `verb * 25 + argument`.

Verbs:
- **noop**: do nothing.
- **move**: step in a direction; blocked by water, cliffs, doors, or occupied tiles.
  Roads and cavalry classes can move 2 tiles if space allows.
- **attack**: directional attack with class-specific patterns and ranges.
  - Archers are ranged; scouts/rams have short range; mangonel has AoE.
  - Spears extend melee attacks and consume spear charges.
  - Monks heal allies; against enemies they can convert if pop-cap allows.
- **use/craft**: interact with the tile or thing in front (harvest resources, craft at stations,
  heal with bread, smelt bars at magma, trade at market, etc.).
- **swap**: exchange positions with adjacent teammate.
- **give**: pass items to adjacent teammate.
- **plant lantern**: place a lantern that provides friendly tint and territory control.
- **plant resource**: plant wheat/tree (requires inputs).
- **build**: place structures from recipes, spending inventory or stockpile resources.
- **orient**: change facing without moving.

## Buildings and Production
- Town centers, houses, and other buildings provide population cap.
- Production buildings (oven, loom, blacksmith, etc.) craft items from inputs.
- Markets convert carried goods into team stockpiles using configured ratios.
- Altars store hearts; bars can be converted into hearts at altars.
- Guard towers and castles auto-attack nearby enemies and tumors.
- Mills periodically fertilize nearby tiles.

## Population and Respawning
- Dead agents can respawn near their home altar if the altar has hearts and the team is under
  its population cap.
- Temples can spawn a new villager if two adjacent teammates are present and a heart is spent.

## Threats and NPCs
- **Tumors (clippy):** spawned by spawners; they branch and spread clippy tint, freezing tiles.
  Agents or predators adjacent to tumors can die with a probability.
- **Wildlife:** bears and wolves roam and attack; cows wander in herds and can be harvested.
- **Goblins:** spawn from hives and act as a hostile faction.

## Victory Conditions
Five victory conditions determine episode end (see `docs/victory_conditions.md`):
- **Conquest**: destroy all enemy agents and buildings.
- **Wonder**: build a Wonder and survive 600-step countdown.
- **Relic**: hold all 18 relics in Monasteries for 200 consecutive steps.
- **Regicide**: each team has a King; team eliminated when King dies.
- **King of the Hill**: control central point for 300 consecutive steps.

Set via `VictoryCondition` enum; `VictoryAll` enables any condition.

## Unit Production and Garrisoning
- Buildings maintain production queues (max 10 units) with per-unit training times.
- Rally points direct newly trained units to a target position.
- Units can garrison in Town Centers, Castles, Guard Towers, and Houses for
  protection and bonus arrows.
- See `docs/unit_production.md` for details.

## Tech Trees
- Blacksmith upgrades (5 lines x 3 tiers) for attack and armor bonuses.
- University research (9 techs) for advanced mechanics.
- Castle unique technologies per civilization.
- Unit promotion chains (Man-at-Arms, Scout, Archer lines).
- See `docs/tech_trees.md` for details.

## Control Groups and Idle Detection
- 10 control groups (Ctrl+N to assign, N to recall).
- Idle villager tracking via `isIdle` flag when action is NOOP or ORIENT.

## Rewards and Episode End
- Rewards are configured in `EnvironmentConfig` (`src/types.nim`): ore, bar, heart, tumor kill,
  survival penalty, death penalty, etc.
- Episode ends at `maxSteps`, victory condition trigger, or if all agents are terminated/truncated.
- At episode end, territory scoring and altar rewards are applied.

## Reference Pointers
- Per-step behavior: `src/step.nim`
- Spawn rules: `src/spawn.nim`
- Combat overlays and bonuses: `src/combat.nim`
- Items/inventory: `src/items.nim`
- Terrain/biomes: `src/terrain.nim` and `src/biome.nim`
