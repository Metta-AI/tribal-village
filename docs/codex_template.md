# Codex Template Commands (Draft)

Date: 2026-01-19
Owner: Tools / Workflow
Status: Draft

This file collects candidate skill / slash-command templates derived from Codex session
logs for this repo. Each entry describes a canonical ask, its inputs, and expected output.

## /cleanup-sweep
**Purpose**: audit a target set of Nim files for conciseness/cleanup without adding
new abstraction layers; optionally apply selected edits.

**Inputs**:
- `targets`: glob or list (default: `src/*.nim`)
- `apply`: `true|false` (default: `false`)
- `max_edits`: integer limit for applied changes

**Steps**:
1) Scan for single-use helpers, duplicated branches, verbose loops, redundant checks.
2) Propose ranked edits (best ROI first).
3) If `apply=true`, implement top `max_edits` changes and rerun tests.

**Output**:
- Ranked list of edits with file references.
- Optional patch + quick rationale.

## /biome-plateau-audit
**Purpose**: verify snow/swamp elevation and cliff boundaries; check for mask holes
and ensure plateau intent is met.

**Inputs**:
- `biomes`: list (default: `snow,swamp`)
- `run_preview`: `true|false` (headless/quick run)

**Steps**:
1) Inspect biome mask application in `src/terrain.nim` / `src/biome.nim`.
2) Inspect elevation assignment and cliff placement in `src/spawn.nim`.
3) Optionally run a short headless run and dump a terrain log.

**Output**:
- Findings on mask continuity and elevation correctness.
- Suggested adjustments if plateau edges are leaky.

## /profile-pop-growth
**Purpose**: run multi-trial headless profiling (3k+ steps) and summarize village
population growth, constraints, and resource bottlenecks.

**Inputs**:
- `steps`: integer (default: 3000)
- `trials`: integer (default: 3)
- `seeds`: list (optional override)

**Steps**:
1) Run `scripts/profile_ai.nim` for each seed.
2) Capture max houses, max hearts, and population counts.
3) Summarize limiting factors (materials, attacks, AI flow).

**Output**:
- Table of trials + max population metrics.
- Short analysis of growth blockers.

## /popcap-audit
**Purpose**: explain and validate population cap mechanics; update naming/terms if
refactors are requested (house vs village vs team).

**Inputs**:
- `rename_policy`: `none|audit|apply`
- `terms`: map of old->new (e.g., `house->village`)

**Steps**:
1) Trace pop cap calculation through `buildingPopCap` and `step.nim`.
2) Identify caps beyond `MapAgentsPerTeam`.
3) If `rename_policy=apply`, execute mechanical renames and update comments.

**Output**:
- Explanation of current cap logic.
- Rename impact list or applied patch.

## /wildlife-extend
**Purpose**: add or adjust roaming wildlife (cows/bears/wolves) and ensure
behavior fits the existing Thing model.

**Inputs**:
- `add`: list of new wildlife kinds
- `tuning`: stats overrides (hp, damage, aggro radius)
- `spawn`: counts and pack/herd sizes

**Steps**:
1) Extend `ThingKind`, registry, and observation layers.
2) Add spawn rules in `src/spawn.nim`.
3) Add movement/attack logic in `src/step.nim`.
4) Update AI predator-cull behaviors (optional).

**Output**:
- Summary of wiring points + tests to run.

## /terrain-river-tweak
**Purpose**: adjust river generation to be more organic while preserving bridges
and tributaries.

**Inputs**:
- `meander`: float tuning (default from constants)
- `tributaries`: integer count

**Steps**:
1) Review `generateRiver` in `src/terrain.nim`.
2) Propose parameter tweaks or pathing changes.
3) Apply and run a quick terrain-generation sanity check.

**Output**:
- Description of changes + expected visual effect.

## /terminology-audit
**Purpose**: audit naming consistency (team vs tribe vs village vs house) and
provide an actionable rename plan.

**Inputs**:
- `preferred`: list of canonical terms
- `apply`: `true|false`

**Steps**:
1) Search code/comments/docs for ambiguous or legacy terms.
2) Produce a change map with file references.
3) Optionally apply mechanical renames.

**Output**:
- Rename plan (and patch if applied).
