# AI Coordination & Agent Control Surface: Gap Analysis

Date: 2026-01-28
Owner: Engineering / AI
Status: Active

## Current State

### Existing Coordination Commands (Fully Implemented)

| Command | API Location | Internal Implementation | GUI/FFI Exposed |
|---------|-------------|------------------------|-----------------|
| Attack-Move | `agent_control.nim:91-117` | `fighter.nim` optFighterAttackMove | Nim API only |
| Patrol | `agent_control.nim:123-150` | `ai_core.nim:1423-1459`, `fighter.nim` optFighterPatrol | Nim API only |
| Scout | `ai_core.nim:1462-1492` | `fighter.nim` optScoutExplore, auto-enabled for UnitScout | Internal only |
| Rally Point | `ai_defaults.nim` | Applied to newly trained units via `agent.rallyTarget` | Internal only |

### Existing Coordination System (`coordination.nim`)

| Request Type | Requestor | Responder | Mechanism |
|-------------|-----------|-----------|-----------|
| RequestProtection | Gatherer (flee) | Fighter (escort) | `fighterShouldEscort()` |
| RequestDefense | Fighter (threat) | Builder (walls/towers) | `builderShouldPrioritizeDefense()` |
| RequestSiegeBuild | Fighter (structures) | Builder (siege workshop) | `hasSiegeBuildRequest()` |

### Existing Infrastructure (Not Exposed as Control API)

| Feature | Engine Location | State |
|---------|----------------|-------|
| Stance types | `types.nim:388-392` (AggressiveDefensiveStandGround/NoAttack) | Defined, used in fighter.nim, **no setter API** |
| Garrison | `step.nim:242-307` | Implemented, available via action arg 9, **no high-level API** |
| Production Queue | `environment.nim:960-1096` | Fully functional, **no external API** |
| Research (Blacksmith) | `environment.nim:1034` | Implemented, **AI-driven only** |
| Research (University) | `environment.nim:1070-1096` | Implemented, **AI-driven only** |
| Selection/Control Groups | `types.nim:997-1008` | Variables exist, **no programmatic API** |
| Difficulty System | `ai_core.nim:28-124` | Fully implemented per-team with adaptive mode |

## Gap Analysis

### Category 1: Missing Control APIs (High Priority)

These features exist internally but lack an external control surface:

1. **Stance Control API** - Stance types exist and affect behavior (`stanceAllowsChase`, `stanceAllowsMovementToAttack`, `stanceAllowsAutoAttack`). Default stances are assigned per unit class via `defaultStanceForClass()` in `environment.nim` (military units default to `StanceDefensive`, villagers/monks to `StanceNoAttack`). Fighter role enforces `StanceDefensive` in `ai_defaults.nim`. However, there is no public function to dynamically set stance on a unit at runtime. Users/Python cannot change unit aggression behavior.

2. **Garrison Control API** - Garrison/ungarrison logic exists in `step.nim` but only via raw action encoding (argument 9). No high-level `garrisonUnit(agentId, buildingPos)` or `ungarrisonAll(buildingPos)` API.

3. **Production Queue Control API** - `queueTrainUnit`, `cancelLastQueued`, `tryBatchQueueTrain` exist but are only called by AI builder/fighter options. No external API to queue unit training from user input.

4. **Research Queue Control API** - `tryResearchBlacksmithUpgrade` and `tryResearchUniversityTech` exist but are AI-internal. No external API to initiate research.

5. **Scout Control API** - `setScoutMode` and `clearScoutMode` exist in `ai_core.nim` but are not exposed in `agent_control.nim` like attack-move and patrol are.

6. **Rally Point Control API** - Rally points are used internally for newly trained units but there's no API to set/get/clear rally points on buildings.

### Category 2: Missing Features (Medium Priority)

These features don't exist yet:

7. **Formation System** - No formation commands exist. Units move individually. Missing: line, box, staggered, wedge formations for military units.

8. **Stop Command** - No explicit "stop all activity" command. Units always follow their AI role. A stop command should clear patrol, attack-move, and current task.

9. **Hold Position Command** - Different from StanceStandGround. Should anchor unit at current position and engage nearby enemies without moving.

10. **Follow Command** - No ability to make one unit follow another unit.

11. **Guard Command** - No ability to assign a military unit to guard a specific building or economic unit (distinct from the coordination-based escort).

### Category 3: FFI/GUI Integration Gaps (High Priority)

12. **FFI Layer Missing Control Exports** - `ffi.nim` only exports environment creation, config, step, and rendering. None of the high-level control APIs (attack-move, patrol, stance, garrison, production) are exported to Python.

13. **Selection System API** - Selection and control group infrastructure exists (`types.nim:997-1008`) but has no programmatic API for selecting units, creating control groups, or issuing commands to selections.

### Category 4: AI Behavior Gaps (Lower Priority)

14. **Waypoint Paths** - Patrol only supports 2 waypoints. No multi-waypoint patrol or custom movement paths.

15. **Economy Priority Override** - No API to force gatherers to prioritize specific resources (override the automatic task selection system).

16. **Aggressive Stance for Non-Fighters** - Gatherers/builders can only flee from threats. No option for them to fight back when cornered.

## Recommendations

### Immediate (beads to create):
- Stance control API + FFI export
- Garrison control API + FFI export
- Production queue control API + FFI export
- Research control API + FFI export
- Scout mode API in agent_control.nim
- Rally point API in agent_control.nim
- Stop command API
- Formation system (basic: line, box)
- FFI export layer for all control APIs
- Selection/command API for programmatic unit control

### Future consideration:
- Follow/guard commands
- Multi-waypoint patrol
- Economy priority override API
- Hold position command
