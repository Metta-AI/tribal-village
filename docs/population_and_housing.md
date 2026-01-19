# Population Caps and Housing

Date: 2026-01-19
Owner: Design / Systems
Status: Draft

## Team and Agent Limits
Core scale constants in `src/types.nim`:
- `MapRoomObjectsTeams = 8`
- `MapAgentsPerTeam = 125`
- Total agent slots = `MapRoomObjectsTeams * MapAgentsPerTeam` (+ goblins)

This means the environment targets ~1000 agents plus a small goblin set.

## Population Cap Formula
Population cap is computed each step in `src/step.nim` by summing building
pop caps per team:
- `buildingPopCap(House) = HousePopCap` (currently 4)
- `buildingPopCap(TownCenter) = TownCenterPopCap` (currently 0)
- Other buildings return 0

The total is clamped to `MapAgentsPerTeam`, so the effective cap is:

`min(MapAgentsPerTeam, house_count * HousePopCap)`

There is no separate hard cap beyond `MapAgentsPerTeam`.

## Where the Cap Is Enforced
Population cap is consulted in the main step loop:
- Agents are prevented from training/spawning if `teamPopCounts >= teamPopCaps`.
- The cap is recomputed every step from the current building list.

## Builder AI: When to Add Houses
The scripted builder logic checks for cap pressure in
`src/scripted/ai_defaults.nim`:
- `needsPopCapHouse` compares current pop count + buffer against the cap.
- When needed, builders try to place `House` near the base position.

## Practical Notes
- Houses are the sole pop-cap building right now.
- Town Centers are important for other mechanics (training and hearth focus),
  but do not add cap.
- Tuning `HousePopCap` or `MapAgentsPerTeam` changes growth dynamics quickly.
