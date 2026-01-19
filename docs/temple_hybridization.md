# Temple Hybridization

## What the Temple Does
The Temple allows two adjacent villagers to "recombine" into a new villager,
creating a hybrid role from the parents' behavior priorities. The new role is
registered into the role catalog for later use.

## Asset + Placement
- Asset: `data/assets/temple.png`
- Prompt source: `data/prompts/assets.tsv`
- Placement: `spawn.nim` runs `placeTemple` during map generation.

## Hybrid Trigger (Current Runtime)
Each step, the engine checks every Temple:
1) Find two adjacent living, non-goblin agents on the same team.
2) Ensure team pop cap is not full.
3) Ensure the parents' home altar has at least one heart.
4) Consume one heart, spawn a dormant villager near the temple, and enqueue
   a `TempleHybridRequest`.

Temple spawns have a short cooldown to prevent rapid chaining.

## Role Recombination (Scripted AI)
`processTempleHybridRequests` handles queued hybrids:
- Recombine parent roles via `recombineRoles`.
- Optionally mutate or inject a random behavior.
- Register the new role with `origin = "temple"`.

By default, hybrid roles are saved but **not automatically assigned** to the
new agent unless `ScriptedTempleAssignEnabled` is enabled.

## Notes / Future Hooks
- `BehaviorTempleFusion` exists as an option for explicit temple use, but the
  current hybrid spawn is adjacency-based (no explicit action needed).
- The hybrid system is ready for experimentation once scripted roles are
  enabled in the agent assignment path.
