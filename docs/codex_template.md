# Codex Template Commands (Tribal Village)

This file collects candidate slash commands/skills based on repeated Codex
requests in this repo. Each entry includes a short intent, inputs, and expected
outputs so it can be turned into a reusable skill.

## /roles-evolution-plan
**Use when:** designing or revisiting the scripted/evolutionary role system.
**Inputs:** desired goals + constraints (core roles kept, scoring step, etc).
**Outputs:** a short plan and a checklist for `docs/evolution.md`.
**Notes:** pairs with `/scripted-refactor` and `/role-homogenize`.

## /scripted-refactor
**Use when:** moving AI logic into `src/scripted/`.
**Inputs:** source files to move and any new module boundaries.
**Outputs:** updated file layout, includes, and updated references.
**Notes:** keep gatherer/builder/fighter intact; avoid breaking tests.

## /role-homogenize
**Use when:** making core roles use the same RoleDef/tier pipeline as evolved roles.
**Inputs:** which core roles to map (default: gatherer/builder/fighter).
**Outputs:** unified role materialization and decision routing.
**Notes:** preserve role tags for heuristics (gatherer tasks, pop-cap logic).

## /temple-asset
**Use when:** creating or updating temple artwork.
**Inputs:** asset prompt changes (e.g., “distinct from monastery”).
**Outputs:** updated `data/prompts/assets.tsv`, regenerated `temple.png`, preview.
**Notes:** runs `scripts/generate_assets.py` and verifies output.

## /temple-hybrid-hookup
**Use when:** wiring temple adjacency to hybrid role generation.
**Inputs:** trigger rules (adjacency vs explicit use), costs (heart), cooldown.
**Outputs:** spawn logic, hybrid request enqueue, role recombination/mutation.
**Notes:** keep assignment toggles so experimentation is opt-in.

## /training-smoke
**Use when:** validating training pipeline or metta integration.
**Inputs:** local vs metta, steps/envs/workers, log outputs.
**Outputs:** successful `tribal-village train` or `scripts/train_metta.sh` run
and any fixes required for pyproject/optional deps.

## /repo-history-slim
**Use when:** clone size is high due to historical blobs.
**Inputs:** size thresholds and target branches.
**Outputs:** list of largest blobs, filter-repo commands, coordination checklist.
**Notes:** must warn about force-push + re-clone requirements.

## /terrain-cliff-audit
**Use when:** cliffs or overlays conflict with walls/background layers.
**Inputs:** target overlay rules and precedence.
**Outputs:** audit summary + fixes in placement/spawn/renderer.
**Notes:** cliffs should typically “own” their tile overlays.

## /combat-visuals-palette
**Use when:** defining combat overlays (auras, crits, counters, healing zones).
**Inputs:** unit types + desired visual language.
**Outputs:** palette recommendations and overlay behavior specs.

