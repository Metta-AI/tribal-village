# Evolutionary Roles Plan

## Goals
- Keep core debugging roles (gatherer, builder, fighter) intact and always available.
- Add a meta-role system that builds new roles from prioritized behavior queues.
- Evolve roles over time so high-performing villages upweight their custom roles.
- Preserve reproducibility (seeded sampling) and debuggability (inspectable tiers).

## Core Concepts
- **Behavior**: a single OptionDef (initiation + act + termination) that already exists in gatherer/builder/fighter.
- **Tier**: an ordered or randomized list of behaviors with shared priority.
- **Role**: a stack of tiers evaluated top-down. First behavior that can act wins.
- **Catalog**: registry of behaviors + generated roles + fitness metadata.

## Role Definition
- **RoleDef** fields (conceptual):
  - id, name, tiers, origin, lockedName, fitness, games, wins
- **RoleTier** fields:
  - behaviorIds, weights (optional), selection mode (fixed/shuffle/weighted)

## Behavior Catalog
- Seed from the default options in gatherer/builder/fighter.
- Behavior IDs are stable within a run; names match OptionDef.name.
- New roles only reference behavior IDs, not raw procs, so we can serialize.

## Role Sampling
- Sample N tiers, then sample M behaviors per tier.
- Ensure constraints (no duplicates, at least one survival behavior if needed).
- Tier order defines priority. Tier selection can be:
  - Fixed order
  - Shuffle each materialization
  - Weighted shuffle
- Assign a generated name based on top-tier behaviors (plus numeric suffix).

## Execution Model
- At runtime, materialize a role into a linear OptionDef list by resolving tiers.
- Pass that list into the existing runOptions() logic.
- Default roles remain hard-coded; meta roles are opt-in.

## Fitness and Scoring
- Each role tracks games, wins, and an exponential moving average fitness.
- Fitness updates after a village simulation (or batch of episodes).
- Roles above a threshold can lock their name and become hall-of-fame candidates.

## Evolution Loop
1) **Select parents** (top-K or weighted by fitness).
2) **Recombine** tiers (prefix from one parent, suffix from the other).
3) **Mutate** (swap behaviors, shuffle tier order, adjust selection mode).
4) **Register** new roles and sample them into future runs.

## Recombination (Hybrid Roles)
- Crossover at tier boundaries to preserve coherent behavior groups.
- Fallback if either parent has no tiers.
- Optional: bias toward higher-fitness parent for the top tier.

## Mutation
- Replace a behavior with a random one from the catalog.
- Flip a tier selection mode (Fixed <-> Shuffle).
- Optional: insert/delete tier with low probability.

## Persistence
- Save/Load RoleCatalog with roles + fitness to a JSON file.
- Store hall-of-fame roles separately for reproducibility.

## Debugging & Observability
- Print role name + tier listing in debug mode.
- Log per-agent role assignment and top-tier behavior decisions.
- Keep the 3 core roles for deterministic debugging and baseline tests.

## Integration Notes
- Keep new scripted AI code in a dedicated module folder (see `src/scripted/`).
- Wire role sampling into decideAction() as an optional mode.
- Ensure test harnesses can still force default roles.
