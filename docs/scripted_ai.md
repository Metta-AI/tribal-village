# Scripted AI and Roles

## Overview
The scripted AI system lets agents run prioritized behavior queues (OptionDef lists)
while keeping the classic gatherer/builder/fighter roles available for debugging.
Generated roles share the same runtime pipeline as the core roles, so evolution and
temple hybrids operate on the same RoleDef data model.

## File Layout
- `src/scripted/ai_core.nim`: AgentState, controller, and core navigation helpers.
- `src/scripted/options.nim`: OptionDef definitions and runOptions().
- `src/scripted/gatherer.nim`, `builder.nim`, `fighter.nim`: behavior implementations.
- `src/scripted/roles.nim`: RoleDef/RoleTier/RoleCatalog and serialization helpers.
- `src/scripted/evolution.nim`: sampling, recombination, mutation, scoring helpers.
- `src/scripted/ai_defaults.nim`: initialization, role assignment, scoring, wiring.

## Role Model
- **RoleDef** holds `tiers`, `origin`, and `kind` (Gatherer/Builder/Fighter/Scripted).
- **RoleTier** is an ordered set of behavior IDs with a selection mode:
  - fixed (keep order)
  - shuffle (randomize each materialization)
  - weighted (weighted shuffle)
- **RoleCatalog** maps behavior names to OptionDefs and holds all roles.

Roles are materialized into an ordered OptionDef list at runtime using
`materializeRoleOptions`, then passed through `runOptions`.

## Core Roles (Debuggable Baselines)
Core roles are built from the standard option lists:
- Gatherer -> GathererOptions
- Builder -> BuilderOptions
- Fighter -> FighterOptions

They are stored as RoleDefs with `origin = "core"` and keep their `kind` so the
shared decision path can still apply role-specific heuristics (for example,
gatherer task selection and pop-cap checks).

## Runtime Assignment
`initScriptedState` seeds the catalog from default behaviors and sets up the
core roles. When compiled with `-d:enableEvolution`, it also loads history,
creates sampled roles, and builds the weighted role pool.

At assignment time:
- Core roles use their RoleDef entries.
- Scripted roles are selected from the role pool (weighted by fitness).
- Exploration can force a newly generated role.

## Evolution Toggle
Evolution is gated behind `-d:enableEvolution`:
- Disabled: only core roles are used, no role history is loaded.
- Enabled: role history is loaded and updated, and generated roles enter the pool.

## Persistence
Role and behavior fitness are saved to `data/role_history.json` after scoring
(default: step 5000). This file is intended to be committed so role genomes
are easy to diff and audit.

## Debugging Notes
- Role execution always flows through `runOptions`, so behavior ordering is
  inspectable by looking at materialized tiers.
- Core roles remain intact for deterministic debugging.
- The `kind` field preserves gatherer/builder/fighter tags even when roles are
  generated or recombined.
