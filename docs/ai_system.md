# AI System Overview

Date: 2026-01-19
Owner: Engineering / AI
Status: Draft

## Overview
The built-in AI lives under `src/scripted/` and is wired in through
`src/agent_control.nim`. The system is intentionally lightweight: agents select
from a prioritized list of **behaviors (OptionDef)** rather than running a large
monolithic policy. The gatherer/builder/fighter roles are the current stable
baselines; a separate scripted/evolutionary path exists for future role
synthesis.

## Current AI wiring (include chain)
This is the current include-based chain (flat scope):
- `src/agent_control.nim`
  - includes `src/scripted/ai_core.nim`
  - includes `src/scripted/ai_defaults.nim`
- `src/scripted/ai_defaults.nim`
  - includes `src/scripted/options.nim`
  - includes `src/scripted/gatherer.nim`
  - includes `src/scripted/builder.nim`
  - includes `src/scripted/fighter.nim`
  - includes `src/scripted/roles.nim`
  - includes `src/scripted/evolution.nim`

This structure is the “include sprawl” discussed in recent sessions. It works
but makes ownership and symbol boundaries hard to reason about.

## Roles and controller state
- `AgentRole` (in `src/scripted/ai_core.nim`): `Gatherer`, `Builder`, `Fighter`,
  `Scripted`.
- `Controller` owns per-agent `AgentState` (spiral search state, cached
  resource positions, active option tracking, path hints).
- `agent_control.getActions()` delegates to the controller for BuiltinAI.

## Default role assignment
By default, each team spawns six active agents with fixed roles:
- Slot 0-1: Gatherer
- Slot 2-3: Builder
- Slot 4-5: Fighter

This mapping is defined in `decideAction()` in `src/scripted/ai_defaults.nim`.

## Role highlights (behavior intent)
These are high-level intent summaries; the exact option ordering lives in the
role option lists.

- **Gatherer**: selects a task based on stockpiles and altar hearts; gathers
  food/wood/stone/gold, plants on fertile tiles, and builds small camps near
  dense resources. Uses markets and stockpiles to drop off when carrying.
- **Builder**: focuses on pop-cap houses, core infrastructure and tech
  buildings, mills near fertile clusters, and defensive rings (walls/doors/
  outposts) around the altar.
- **Fighter**: defends against nearby enemies, retreats on low HP, breaks out
  of enclosures, hunts wildlife, and supports monk/relic behaviors when
  applicable.

## The behavior (OptionDef) system
`src/scripted/options.nim` defines the minimal behavior contract:

- `OptionDef` fields:
  - `name`
  - `canStart(controller, env, agent, agentId, state)`
  - `shouldTerminate(controller, env, agent, agentId, state)`
  - `act(controller, env, agent, agentId, state) -> uint8`
  - `interruptible`

`runOptions()` applies these rules:
1) If an active option exists, it may be pre-empted by a higher-priority option
   **only if** the active option is `interruptible`.
2) The active option’s `act()` is called. If it returns 0 or
   `shouldTerminate()` is true, the active option is cleared.
3) Otherwise, options are scanned in priority order; the first option that both
   `canStart()` and returns a non-zero action wins that tick.

This means options should **return 0** when they cannot act, so the scan can
continue.

## Where behaviors live
- **Behavior pool:** `src/scripted/options.nim`
- **Role composition:** `src/scripted/gatherer.nim`, `builder.nim`,
  `fighter.nim`, plus defaults in `ai_defaults.nim`
- **Scripted/evolutionary roles:** `src/scripted/roles.nim` and
  `src/scripted/evolution.nim` (see `docs/evolution.md`)

## Adding a new behavior (recommended pattern)
1) Implement `canStart` (fast, side-effect free).
2) Implement `act` (moves or uses an action; return 0 when you can’t act).
3) Decide termination:
   - stateless behaviors can use `optionsAlwaysTerminate`.
   - long-running behaviors should implement `shouldTerminate`.
4) Add an `OptionDef` to the appropriate role list, near similar priority.
5) Keep the behavior **focused** (one goal) so future meta-roles can re-order
   it safely.

## Modularization plan (documented intent)
If/when we refactor the include chain, a minimal, low-risk modularization is:
- `ai_types.nim`: shared types (`AgentRole`, `AgentState`, `Controller`).
- `ai_options.nim`: `OptionDef`, `runOptions`, and helper procs.
- `ai_roles.nim`: role assembly (gatherer/builder/fighter lists).
- `ai_controller.nim`: `decideAction`, controller update logic.

Goal: replace `include` with explicit `import` to reduce accidental coupling
without changing behavior.

## Debugging & profiling hooks
- `scripts/profile_ai.nim`: quick AI profiling entrypoint.
- `scripts/run_all_tests.nim`: run the full Nim test sequence.

These are the fastest paths for AI iteration when you don’t need a full
rendered run.
