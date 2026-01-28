# Unit Production, Garrisoning, and Control

Date: 2026-01-28
Owner: Docs / Systems
Status: Draft

## Overview
AoE2-style production system with training queues, rally points, garrisoning,
control groups, and idle villager detection.

Key files:
- `src/types.nim` (queue structs, garrison fields, constants)
- `src/step.nim` (queue processing, garrison logic, rally points)
- `src/registry.nim` (per-unit training times)
- `src/agent_control.nim` (attack-move, patrol API)

## Production Queues
Buildings with training capability maintain a production queue (max 10 units):
- Standard click queues 1 unit, Shift-click queues 5, Ctrl-click queues 10.
- Each step, the building decrements `remainingSteps` for the front item.
- When countdown reaches 0, the unit spawns at the nearest empty tile.
- Resources are consumed when the unit is enqueued, not when it spawns.

### Training Times
Per-unit training durations (in steps):

| Unit | Steps |
|------|-------|
| Villager | 50 |
| Man-at-Arms | 40 |
| Archer | 35 |
| Scout | 30 |
| Knight | 60 |
| Monk | 51 |
| Battering Ram | 65 |
| Mangonel | 70 |
| Trebuchet | 80 |
| Boat | 45 |
| Trade Cog | 40 |

## Rally Points
Buildings can have a rally point that newly trained units auto-move toward:
- Action 10 (`SET_RALLY_POINT`) sets a rally point on an adjacent friendly building.
- The agent's current position becomes the rally destination.
- Newly spawned units receive the rally point as a movement target.

## Garrisoning
Four building types support unit garrisoning:

| Building | Capacity |
|----------|----------|
| Town Center | 15 |
| Castle | 20 |
| Guard Tower | 5 |
| House | 5 |

Mechanics:
- Garrisoned units are removed from the grid (position set to -1,-1).
- Each garrisoned unit adds `GarrisonArrowBonus` (1) extra arrow to building attacks.
- USE action argument 9 ungarrisons all units to adjacent empty tiles.
- **Town Bell** (USE argument 10): recalls all team villagers within range into the
  Town Center for one step.
- Monks can garrison relics in Monasteries, generating gold over time.

## Trade Cogs
Water-based trade unit trained at Docks for gold generation:
1. Trade Cog stores its origin dock position on spawn.
2. When it reaches a different friendly dock, gold = max(1, manhattan_distance / 10).
3. Home dock flips to current dock for return trip.
4. Trade Cogs cannot attack and never disembark from water.

## Control Groups
10 control groups (0-9) for unit selection via keyboard:
- Ctrl+N assigns current selection to group N.
- Press N to recall the group.
- Double-tap N centers camera on the group.
- Groups persist across steps, cleared on environment reset.

## Idle Villager Detection
Agents are marked idle when their action verb is NOOP (0) or ORIENT (9). The
`isIdle` flag appears in the `AgentIdleLayer` observation channel. No automatic
reassignment occurs -- external systems query this state.

## Stance Modes
Four combat stances control auto-attack behavior:
- **Aggressive**: chase enemies, attack anything in sight.
- **Defensive**: attack in range, return to position.
- **Stand Ground**: don't move, only attack in range.
- **No Attack**: never auto-attack (useful for scouts/trade units).

## Attack-Move and Patrol
External API for controlling unit movement with combat:
- `setAgentAttackMoveTarget(agentId, target)`: move to target, engaging enemies
  encountered en route.
- Patrol behavior cycles units between waypoints, attacking enemies in range.
- Both accessible via the Python FFI layer in `src/agent_control.nim`.

## Trebuchet Pack/Unpack
Trebuchets toggle between packed (mobile, can't attack) and unpacked (stationary,
can attack) states:
- USE action argument 8 initiates the transition.
- `TrebuchetPackDuration` (15 steps) cooldown during transition.
- Movement and attacks blocked while transitioning.
- Purple tint displays during the packing animation.
