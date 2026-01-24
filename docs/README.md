# Docs Index

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

This index lists the canonical docs for the Tribal Village repo.

## Getting Started
- `docs/quickstart.md`: prerequisites, building, running, testing, and environment variables.

## Core Gameplay and Systems
- `docs/game_logic.md`: high-level step loop, actions, entities, and episode end rules.
- `docs/combat.md`: combat rules, counters, and damage interactions.
- `docs/combat_visuals.md`: combat tint/visual feedback specifics.
- `docs/economy_respawn.md`: inventory vs stockpile, markets, hearts, respawns.
- `docs/population_and_housing.md`: pop-cap and housing details.
- `docs/clippy_tint_freeze.md`: territory tinting, tumors, and frozen tiles.
- `docs/observation_space.md`: observation tensor layout and tint codes.

## AI
- `docs/ai_system.md`: AI wiring, roles, OptionDef behavior model, evolution toggle.
- `docs/ai_profiling.md`: profiling entrypoints and evolution compile-time flag.

## Worldgen and Spawning
- `docs/world_generation.md`: trading hub, rivers, goblin hives, tuning notes.
- `docs/spawn_pipeline.md`: spawn order, placement helpers, and connectivity pass.
- `docs/terrain_biomes.md`: biome masks, elevation, cliffs, ramps, connectivity.
- `docs/wildlife_predators.md`: wildlife spawn and behavior rules.

## Tooling and Pipelines
- `docs/cli_and_debugging.md`: CLI usage, debugging flags, common failure modes.
- `docs/training_and_replays.md`: training entrypoints and replay writer setup.
- `docs/asset_pipeline.md`: asset generation and wiring guidance.

## Design and Planning
- `docs/aoe2_design_plan.md`: AoE2-inspired design notes and constraints.
- `docs/siege_fortifications_plan.md`: siege and defenses design plan.
- `docs/temple_hybridization.md`: temple-based hybrid spawn notes.

## Analysis and Reviews
- `docs/ai_behavior_analysis.md`: AI behavior invalid action root causes.
- `docs/game_mechanics_analysis.md`: game mechanics action failure analysis.
- `docs/performance_analysis.md`: performance optimization opportunities.
- `docs/code_review_verbosity.md`: code verbosity patterns review.
- `docs/code_review_indirection.md`: helper function indirection review.
- `docs/code_review_dead_code.md`: dead code analysis.
- `docs/ai_profile_3000_steps.md`: profile results from 3000 step run.

## Repo and Process
- `docs/repo_history_cleanup.md`: repository history cleanup notes.
- `docs/codex_template.md`: candidate Codex command templates.
