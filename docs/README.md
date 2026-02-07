# Docs Index

Date: 2026-02-06
Owner: Docs / Systems
Status: Active

This index lists the canonical docs for the Tribal Village repo.

## Getting Started
- `quickstart.md`: prerequisites, building, running, testing, and environment variables.

## Architecture and Configuration
- `architecture.md`: high-level codebase architecture and module layout.
- `configuration.md`: tunable constants and configuration reference.
- `action_space.md`: action encoding, verbs, and argument layout.
- `observation_space.md`: observation tensor layout and tint codes.

## Core Gameplay and Systems
- `game_logic.md`: step loop, actions, entities, victory conditions, production queues, tech trees, unit commands.
- `combat.md`: combat rules, counters, siege, trebuchets, attack-move, patrol, unit stances, cliff fall damage.
- `combat_visuals.md`: combat tint/visual feedback specifics.
- `economy_respawn.md`: inventory, stockpiles, markets, AoE2 trade, Trade Cogs, biome bonuses, hearts, respawns.
- `population_and_housing.md`: pop-cap and housing details.
- `clippy_tint_freeze.md`: territory tinting, tumors, and frozen tiles.

## AI
- `ai_system.md`: AI roles, inter-role coordination, shared threat maps, adaptive difficulty, economy management, scout exploration, OptionDef behavior model, evolution toggle.
- `ai_profiling.md`: profiling entrypoints and evolution compile-time flag.

## Worldgen and Spawning
- `world_generation.md`: trading hub, rivers, goblin hives, tuning notes.
- `spawn_pipeline.md`: spawn order, placement helpers, and connectivity pass.
- `terrain_biomes.md`: biome masks, elevation, cliffs, ramps, mud, water depth, movement speed modifiers, biome resource bonuses, connectivity.
- `wildlife_predators.md`: wildlife spawn and behavior rules.

## Tooling and Pipelines
- `cli_and_debugging.md`: CLI usage, debugging flags, common failure modes.
- `training_and_replays.md`: training entrypoints and replay writer setup.
- `asset_pipeline.md`: asset generation and wiring guidance.

## Design and Planning
- `aoe2_design_plan.md`: AoE2-inspired design notes and constraints.
- `siege_fortifications_plan.md`: siege and defenses design plan.
- `temple_hybridization.md`: temple-based hybrid spawn notes.
- `ui_overhaul_design.md`: AoE2-style UI design (partially implemented).
- `recently-merged-features.md`: recently merged feature documentation.

## Analysis and Reviews (`analysis/`)
All analysis, audit, investigation, and code review files live in `docs/analysis/`:
- `analysis/ai_behavior_analysis.md`: AI behavior invalid action root causes.
- `analysis/ai_profile_3000_steps.md`: profile results from 3000 step run.
- `analysis/ai_profiling_p1_gaps.md`: P1 profiling gaps analysis and recommendations.
- `analysis/aoe2_design_investigation.md`: AoE2 design investigation notes.
- `analysis/building_siege_analysis.md`: building and siege mechanic analysis.
- `analysis/codebase_audit.md`: full codebase audit.
- `analysis/codebase-beads-status.md`: codebase beads status tracking.
- `analysis/code_review_dead_code.md`: dead code analysis.
- `analysis/code_review_indirection.md`: helper function indirection review.
- `analysis/code_review_verbosity.md`: code verbosity patterns review.
- `analysis/entity_interaction_analysis.md`: entity interaction analysis.
- `analysis/game_mechanics_analysis.md`: game mechanics action failure analysis.
- `analysis/perf-improvements.md`: performance improvement notes.
- `analysis/performance_analysis.md`: performance optimization opportunities.
- `analysis/performance_scaling_1000_agents.md`: scaling analysis for 1000 agents.
- `analysis/role_audit_report.md`: AI role audit report.
- `analysis/siege_fortifications_investigation_report.md`: siege fortifications investigation.
- `analysis/temple_hybridization_audit.md`: temple hybridization audit.
- `analysis/terrain_biomes_audit.md`: terrain and biomes audit.

## Repo and Process
- `repo_history_cleanup.md`: repository history cleanup notes.
- `codex_template.md`: candidate Codex command templates.
