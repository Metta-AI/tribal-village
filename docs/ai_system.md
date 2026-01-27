# AI System Overview

Date: 2026-01-19
Owner: Engineering / AI
Status: Draft

## Overview
The built-in AI lives under `src/scripted/` and is wired in through
`src/agent_control.nim`. The system is intentionally lightweight: agents select
from a prioritized list of **behaviors (OptionDef)** rather than running a large
monolithic policy. The gatherer/builder/fighter roles are the current stable
baselines; a separate scripted/evolutionary path exists for generated roles.

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

This structure is the "include sprawl" discussed in recent sessions. It works
but makes ownership and symbol boundaries hard to reason about.

## Understanding the include pattern

### Nim's `include` vs `import`

Nim has two mechanisms for code organization:

| Mechanism | Behavior | Use Case |
|-----------|----------|----------|
| `import` | Loads a module with its own namespace | Standard modular code, clear dependencies |
| `include` | Textually inserts file contents at that point | Code splitting within a single compilation unit |

**`include` merges files into one scope.** All symbols from included files become
part of the including file's namespace, as if you had written one large file.

### Why the AI uses `include`

The scripted AI system uses `include` for historical and practical reasons:

1. **Shared state access**: All behavior procs need access to `Environment`,
   `Controller`, `AgentState`, and helper functions. With `include`, these
   are automatically in scope without explicit imports or circular dependency
   issues.

2. **Compile-time behavior registration**: The `OptionDef` arrays (e.g.,
   `GathererOptions`, `BuilderOptions`) are static arrays that must be known
   at compile time. `include` makes it easy to compose these without forward
   declarations.

3. **Incremental growth**: The system started small and grew by adding files.
   `include` was the path of least resistance.

### Implications for developers

**What works:**
- Adding new procs that use existing types and helpers
- Adding new `OptionDef` entries to role arrays
- Calling any proc defined anywhere in the include chain

**What to watch for:**
- **Implicit dependencies**: A file may use symbols defined elsewhere in the
  chain without any visible import statement. Check the include order if you
  see "undeclared identifier" errors.
- **Order matters**: Files are processed top-to-bottom. A proc in `fighter.nim`
  can call procs from `ai_core.nim` (included earlier), but not vice versa
  without forward declarations.
- **No namespace isolation**: Name collisions between files are real. Prefix
  role-specific helpers (e.g., `gathererFindResource`, `builderSelectSite`).

### The complete include graph

```
src/agent_control.nim
├── includes src/scripted/ai_core.nim
│   ├── imports std/[tables, sets, algorithm]
│   ├── imports ../entropy, vmath, ../environment, ../common, ../terrain
│   └── defines: AgentRole, AgentState, Controller, PathfindingCache, helpers
│
└── includes src/scripted/ai_defaults.nim
    ├── defines: tryBuildAction, goToAdjacentAndBuild, decideAction, etc.
    │
    ├── includes src/scripted/options.nim
    │   └── defines: OptionDef, runOptions, MetaBehaviorOptions
    │
    ├── includes src/scripted/gatherer.nim
    │   └── defines: GathererOptions array
    │
    ├── includes src/scripted/builder.nim
    │   └── defines: BuilderOptions array
    │
    ├── includes src/scripted/fighter.nim
    │   └── defines: FighterOptions array
    │
    ├── includes src/scripted/roles.nim
    │   └── defines: RoleDef, RoleCatalog, materializeRoleOptions
    │
    └── includes src/scripted/evolution.nim
        └── defines: generateRandomRole, applyScriptedScoring
```

### Adding new code

**To add a new behavior:**
1. Define `canStart*` and `opt*` procs in the appropriate role file
2. Add an `OptionDef` entry to that role's options array
3. The `*` export marker is optional (everything is in scope anyway) but helps
   indicate public API intent

**To add a new role file:**
1. Create `src/scripted/newrole.nim`
2. Add `include "newrole"` in `ai_defaults.nim` after dependencies
3. Define your options array and register it in `seedDefaultBehaviorCatalog`

**Best practice**: Each file should have a header comment like:
```nim
# This file is included by src/agent_control.nim
```
This helps developers understand the context when viewing the file in isolation.

## Roles and controller state
- `AgentRole` (in `src/scripted/ai_core.nim`): `Gatherer`, `Builder`, `Fighter`,
  `Scripted`.
- `Controller` owns per-agent `AgentState` (spiral search state, cached
  resource positions, active option tracking, path hints).
- `agent_control.getActions()` delegates to the controller for BuiltinAI.

## Role model and catalog
Scripted roles use a lightweight catalog model (`src/scripted/roles.nim`):
- **RoleDef**: `tiers`, `origin`, `kind` (Gatherer/Builder/Fighter/Scripted).
- **RoleTier**: ordered behavior IDs with a selection mode:
  - fixed (keep order)
  - shuffle (randomize each materialization)
  - weighted (weighted shuffle)
- **RoleCatalog**: maps behavior names to OptionDefs and holds all roles.

Roles are materialized into an ordered OptionDef list using
`materializeRoleOptions`, then executed via `runOptions`.

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
- **Role catalog + evolution:** `src/scripted/roles.nim`,
  `src/scripted/evolution.nim`

## Runtime assignment
`initScriptedState` seeds the catalog from default behaviors and sets up the
core roles. When compiled with `-d:enableEvolution`, it also loads history,
creates sampled roles, and builds the weighted role pool.

At assignment time:
- Core roles use their RoleDef entries.
- Scripted roles are selected from the role pool (weighted by fitness).
- Exploration can force a newly generated role.

## Evolution toggle and persistence
Evolution is gated behind `-d:enableEvolution`:
- Disabled: only core roles are used; no role history is loaded.
- Enabled: role history is loaded and updated; generated roles enter the pool.

Role and behavior fitness are saved to `data/role_history.json` after scoring
(default: step 5000). This file is intended to be committed so role genomes
are easy to diff and audit.

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

## Debugging and profiling hooks
- `scripts/profile_ai.nim`: quick AI profiling entrypoint.
- `scripts/run_all_tests.nim`: run the full Nim test sequence.

These are the fastest paths for AI iteration when you don’t need a full
rendered run.
