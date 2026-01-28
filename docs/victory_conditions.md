# Victory Conditions

Date: 2026-01-28
Owner: Docs / Systems
Status: Draft

## Overview
Five victory conditions determine how games end, controlled by the `VictoryCondition`
enum in `src/types.nim`. Set via environment config; `VictoryAll` enables any condition
to trigger.

Key files:
- `src/types.nim` (enums, constants)
- `src/step.nim` (victory checking logic)
- `src/spawn.nim` (King spawning, control point placement)

## Conquest
The default mode. A team wins by destroying all enemy agents and buildings. Checked
each step after combat resolution.

## Wonder Victory
Build a Wonder building and survive a countdown:
1. Wonder is placed like other buildings (high resource cost).
2. Countdown starts when the Wonder is **completed** (not when placed).
3. Team must defend the Wonder for `WonderVictoryCountdown` (600) steps.
4. If the Wonder is destroyed, the countdown resets.
5. First team to complete the countdown wins.

## Relic Victory
Collect and hold relics in Monasteries:
1. Map spawns `RelicCount` (18) neutral relics.
2. Monks pick up relics via USE action and garrison them in Monasteries.
3. A team must hold **all** relics in their Monasteries for `RelicVictoryHoldTime`
   (200) consecutive steps.
4. Each garrisoned relic also generates 1 gold per `RelicGoldInterval` (20) steps.
5. If a Monastery is destroyed, garrisoned relics drop to the ground.

## Regicide
Each team spawns a King unit (agent slot 0) with elevated HP. A team is eliminated
when its King dies. Last team with a living King wins.

## King of the Hill
A neutral `ControlPoint` is placed at the map center:
1. Control is determined by which team has the most units within radius 5.
2. A team must maintain continuous control for `KOTHVictoryHoldTime` (300) steps.
3. Control counter resets if another team takes majority.
4. First team to reach the hold time wins.

## Configuration
Victory condition is set in `EnvironmentConfig`. The `VictoryAll` option enables
all conditions simultaneously -- whichever triggers first wins.
