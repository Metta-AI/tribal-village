# Scripted AI Options and Roles

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document explains the options-based scripted AI used by gatherer, builder, and fighter roles,
and how to extend or debug the behavior system.

Key implementation files:
- `src/scripted/options.nim`
- `src/scripted/ai_core.nim`
- `src/scripted/gatherer.nim`
- `src/scripted/builder.nim`
- `src/scripted/fighter.nim`
- `src/scripted/roles.nim`
- `src/scripted/ai_defaults.nim`
- `src/agent_control.nim`

## Core Concepts
- **Controller**: per-episode AI state (RNG, per-agent AgentState, building counts, role catalog).
- **AgentState**: per-agent memory (active option, cached targets, spiral search state, build targets).
- **OptionDef**: a behavior with `canStart`, `act`, `shouldTerminate`, and `interruptible`.

## Option Lifecycle (runOptions)
Options are evaluated in priority order each step.

1. If the agent already has an active option:
   - If that option is interruptible, higher-priority options can preempt it.
   - The active option runs `act`. If it returns an action (non-zero), the action is used.
   - If `shouldTerminate` returns true, the active option is cleared.
2. If no active option produced an action, the system scans options in order and uses the first
   option that both `canStart` and returns a non-zero action.
3. Returning `0` means “no action,” so the system will try the next option.

The result is a reactive, priority-driven loop that avoids long-lived state unless needed.

## Role Assignment and Catalog
- Default roles are assigned per-team by agent slot: **2 gatherers, 2 builders, 2 fighters**.
- `ai_defaults.nim` builds a role catalog from the core option lists and materializes scripted roles.
- `roles.nim` supports tiered role definitions (fixed, shuffled, or weighted behavior tiers).

## Role Highlights (High-Level)
- **Gatherer**:
  - Chooses a task based on stockpiles and altar hearts.
  - Gathers food/wood/stone/gold, plants on fertile tiles, builds small camps near dense resources.
  - Drops off to town centers/stockpiles or trades at markets when appropriate.
- **Builder**:
  - Maintains population cap (houses), builds core infrastructure and tech buildings.
  - Places mills near fertile clusters, builds camps when resource density is high.
  - Builds defensive rings (walls, doors, outposts) around the altar.
- **Fighter**:
  - Defends against nearby enemies, retreats when low on HP, and breaks out of enclosures.
  - Hunts wildlife, attacks enemy structures, and supports monk/relic behaviors.

## Adding a New Option
1. Implement `canStart`, `act`, and `shouldTerminate` in the appropriate role file.
2. Add the OptionDef to the role’s option list in `src/scripted/ai_defaults.nim`.
3. If the behavior should preempt others, set `interruptible = true` and place it earlier.
4. Use controller helpers (`moveTo`, `actAt`, `tryBuild...`, `tryMoveToKnownResource`) to keep
   behavior consistent with existing movement and targeting logic.

## Debugging Tips
- Use `tests/ai_harness.nim` to validate behavior paths and avoid regressions.
- Inspect AgentState fields (activeOptionId, cached positions, build targets) when actions
  oscillate or stall.
