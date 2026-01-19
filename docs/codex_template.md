# Codex Command Templates

Date: 2026-01-19
Owner: DevEx / Tools
Status: Draft

This file collects candidate slash-command / skill templates derived from Codex
session analysis. Each entry is a repeatable ask with a suggested command
signature and expected artifacts.

## Candidates (tribal-village)

### /run-validation (alias: /tv-validate)
**Intent:** Run the standard local validation steps for this repo.
**Typical prompt:** "debug and make sure tests pass" / "run validations".
**Outputs:** Command results + summarized status.
**Commands:**
- `nim c -d:release tribal_village.nim`
- `timeout 15s nim r -d:release tribal_village.nim` (or `gtimeout` on macOS)
- `nim r --path:src tests/ai_harness.nim`

### /tv-spelunk <pattern>
**Intent:** Fast codebase search + open likely files for a mechanic.
**Typical prompt:** "find where X is handled" / "show me the code for X".
**Outputs:** File excerpts for top hits.
**Commands:**
- `rg -n "<pattern>" src` (include `docs` if needed)
- `sed -n '1,240p' <file>` for the top 2–3 hits.

### /tv-terrain-elevation
**Intent:** Investigate cliffs, ramps, and elevation traversal.
**Typical prompt:** "how do cliffs/ramps work" / "why is movement blocked".
**Outputs:** Code excerpts + short explanation.
**Commands:**
- `rg -n "applyBiomeElevation|applyCliffRamps|applyCliffs" src/spawn.nim`
- `sed -n '120,260p' src/spawn.nim`
- `rg -n "canTraverseElevation" src/environment.nim`
- `sed -n '400,460p' src/environment.nim`
- `rg -n "RampUp|RampDown|Cliff" src/terrain.nim src/types.nim src/registry.nim`

### /tv-tint-freeze
**Intent:** Investigate clippy tint, action tints, and frozen tiles.
**Typical prompt:** "why are tiles frozen" / "how does tint layer work".
**Outputs:** Code excerpts + short explanation.
**Commands:**
- `rg -n "Tint|tint|Clippy|frozen" src/tint.nim src/colors.nim src/step.nim src/renderer.nim`
- `sed -n '1,200p' src/tint.nim`
- `sed -n '1,160p' src/colors.nim`
- `rg -n "TintLayer" src/environment.nim`

### /tv-game-loop
**Intent:** Open the main step loop and action handlers.
**Typical prompt:** "how does the step loop work" / "where is action X".
**Outputs:** Code excerpts + short explanation.
**Commands:**
- `sed -n '1,220p' src/step.nim`
- `rg -n "case verb|attackAction|useAction|buildAction" src/step.nim`
- `sed -n '220,900p' src/step.nim`

### /tv-observation
**Intent:** Inspect observation space and inventory encoding.
**Typical prompt:** "what is in the observation layers" / "why is item X missing".
**Outputs:** Code excerpts + short explanation.
**Commands:**
- `rg -n "ObservationName|ObservationLayers|TintLayer" src/types.nim`
- `sed -n '150,260p' src/types.nim`
- `rg -n "updateObservations|updateAgentInventoryObs" src/environment.nim`
- `sed -n '1,200p' src/environment.nim`

### /tv-economy-respawn
**Intent:** Inspect inventory/stockpile rules, altars/hearts, and respawn logic.
**Typical prompt:** "how do hearts/altars work" / "why aren’t agents respawning".
**Outputs:** Code excerpts + short explanation.
**Commands:**
- `rg -n "altar|hearts|respawn" src/step.nim src/items.nim src/types.nim`
- `sed -n '1800,2100p' src/step.nim`
- `sed -n '1,200p' src/items.nim`

### /tv-git-scan
**Intent:** Quick state + history check before/after changes.
**Typical prompt:** "what changed?" / "show me recent commits".
**Outputs:** Short status summary.
**Commands:**
- `git status -sb`
- `git diff --stat`
- `git log --oneline -n 20`

### /update-readme-observations
**Intent:** Reconcile `README.md` with current gameplay and observation space.
**Typical prompt:** "README is out of date with features/observations; update it".
**Outputs:** Updated README sections for features + observation layout.
**Likely files:** `README.md`, `src/types.nim`, `src/environment.nim`, `src/ffi.nim`.

### /worldgen-hub-variation
**Intent:** Make the central trading hub feel more organic and busy without blocking roads.
**Typical prompt:** "add more buildings around hub, keep roads clear" or "make walls less boxy".
**Outputs:** Updated hub placement and wall generation.
**Likely files:** `src/spawn.nim` (trading hub block).

### /worldgen-river-tune
**Intent:** Adjust river meandering intensity (less/more).
**Typical prompt:** "rivers are too meandering now; reduce".
**Outputs:** Tweaked river drift probabilities.
**Likely files:** `src/terrain.nim` (`generateRiver`).

### /spawn-goblin-hives
**Intent:** Ensure a fixed count of goblin nests/hives per map.
**Typical prompt:** "every map should spawn two goblin nests".
**Outputs:** Updated spawn logic and spacing checks.
**Likely files:** `src/spawn.nim` (goblin hive block).

### /ai-add-behaviors
**Intent:** Add new behavior options to the AI pool without changing core gatherer/builder/fighter logic.
**Typical prompt:** "add behaviors/options for new items or creatures".
**Outputs:** New `OptionDef`s plus wiring into role option lists.
**Likely files:** `src/scripted/options.nim`, `src/scripted/ai_defaults.nim`.

### /ai-behavior-ideation
**Intent:** Generate a list of new, scoped behaviors aligned to territory control objectives.
**Typical prompt:** "outline 25 new behaviors for meta-role system".
**Outputs:** Behavior list with brief descriptions (no code changes).

### /inline-one-offs
**Intent:** Inline single-use helpers and remove small layers of indirection.
**Typical prompt:** "audit for verbosity; inline one-use helpers".
**Outputs:** Small refactors that reduce indirection.
**Likely files:** broad; often `src/step.nim`, `src/spawn.nim`, `src/tileset.nim`,
`src/combat.nim`.

### /cleanup-audit
**Intent:** Audit for cleanup or complexity hotspots and propose targets.
**Typical prompt:** "audit for cleanup/conciseness" or "overly complex logic".
**Outputs:** Ranked list of candidates; no code changes unless requested.

### /include-sprawl-map
**Intent:** Map include chains and explain how modules relate.
**Typical prompt:** "map include sprawl and explain callsites".
**Outputs:** Clear include graph + callsite notes.
**Likely files:** `src/agent_control.nim`, `src/scripted/*.nim`.

### /ai-chain-modularize-plan
**Intent:** Produce a modularization plan for the AI include chain.
**Typical prompt:** "how would you modularize ai chain?".
**Outputs:** Step plan with proposed module boundaries and low-risk sequencing.

### /codex-log-docs
**Intent:** Read Codex logs for this repo and synthesize docs in `docs/`.
**Typical prompt:** "audit codex sessions and write topic docs".
**Outputs:** New or updated docs (AI, worldgen, observation space, etc.).
**Likely files:** `docs/*.md`.

### /roles-evolution-plan
**Intent:** Outline or revise the scripted/evolutionary role system.\
**Typical prompt:** "outline how roles evolve and integrate with AI".\
**Inputs:** goals + constraints (core roles kept, scoring step, etc).\
**Outputs:** plan + checklist for `docs/evolution.md`.\
**Notes:** pairs well with `/scripted-refactor` and `/role-homogenize`.

### /scripted-refactor
**Intent:** Move AI logic into `src/scripted/` modules.\
**Typical prompt:** "move AI code into scripted folder".\
**Inputs:** source files + target module boundaries.\
**Outputs:** updated includes and file layout.\
**Notes:** keep gatherer/builder/fighter intact; avoid breaking tests.

### /role-homogenize
**Intent:** Make core roles share the same RoleDef/tier pipeline as evolved roles.\
**Typical prompt:** "homogenize roles and options across core + evolution".\
**Inputs:** roles to map (default: gatherer/builder/fighter).\
**Outputs:** unified role materialization and decision routing.\
**Notes:** preserve role tags for heuristics (gatherer tasks, pop-cap logic).

### /temple-asset
**Intent:** Create or update temple artwork.\
**Typical prompt:** "generate a distinct temple asset".\
**Inputs:** prompt edits + asset filename.\
**Outputs:** updated `data/prompts/assets.tsv`, regenerated `temple.png`, preview.\
**Notes:** runs `scripts/generate_assets.py`.

### /temple-hybrid-hookup
**Intent:** Wire temple adjacency to hybrid role generation.\
**Typical prompt:** "if two agents stand near temple, spawn hybrid".\
**Inputs:** trigger rules, costs (heart), cooldown.\
**Outputs:** spawn logic + hybrid request enqueue + role recombination.\
**Notes:** keep assignment toggles so experimentation is opt-in.

### /training-smoke
**Intent:** Validate training pipeline or metta integration.\
**Typical prompt:** "run a small training job and log outputs".\
**Inputs:** local vs metta, steps/envs/workers, logging.\
**Outputs:** successful training run or actionable fixes.\
**Notes:** may touch `pyproject.toml` optional deps.

### /repo-history-slim
**Intent:** Identify large blobs and propose history cleanup.\
**Typical prompt:** "clone is huge; prune history".\
**Inputs:** size thresholds and target branches.\
**Outputs:** largest-blob report + filter-repo commands + coordination steps.\
**Notes:** must warn about force-push + re-clone requirements.

### /terrain-cliff-audit
**Intent:** Audit cliff overlays and precedence vs walls/background layers.\
**Typical prompt:** "cliffs should be the only overlay on a tile".\
**Inputs:** overlay precedence rules.\
**Outputs:** audit summary + fixes in placement/spawn/renderer.

### /combat-visuals-palette
**Intent:** Define combat overlays (auras, crits, counters, healing zones).\
**Typical prompt:** "give unit types distinct combat visuals".\
**Inputs:** unit types + visual language.\
**Outputs:** palette recommendations and overlay behavior specs.

## Candidate Additions (log-derived)

### /cleanup-sweep
**Purpose:** Audit a target set of Nim files for conciseness/cleanup without adding
new abstraction layers; optionally apply selected edits.

**Inputs:**
- `targets`: glob or list (default: `src/*.nim`)
- `apply`: `true|false` (default: `false`)
- `max_edits`: integer limit for applied changes

**Steps:**
1) Scan for single-use helpers, duplicated branches, verbose loops, redundant checks.
2) Propose ranked edits (best ROI first).
3) If `apply=true`, implement top `max_edits` changes and rerun tests.

**Output:**
- Ranked list of edits with file references.
- Optional patch + quick rationale.

### /biome-plateau-audit
**Purpose:** Verify snow/swamp elevation and cliff boundaries; check for mask holes
and ensure plateau intent is met.

**Inputs:**
- `biomes`: list (default: `snow,swamp`)
- `run_preview`: `true|false` (headless/quick run)

**Steps:**
1) Inspect biome mask application in `src/terrain.nim` / `src/biome.nim`.
2) Inspect elevation assignment and cliff placement in `src/spawn.nim`.
3) Optionally run a short headless run and dump a terrain log.

**Output:**
- Findings on mask continuity and elevation correctness.
- Suggested adjustments if plateau edges are leaky.

### /profile-pop-growth
**Purpose:** Run multi-trial headless profiling (3k+ steps) and summarize village
population growth, constraints, and resource bottlenecks.

**Inputs:**
- `steps`: integer (default: 3000)
- `trials`: integer (default: 3)
- `seeds`: list (optional override)

**Steps:**
1) Run `scripts/profile_ai.nim` for each seed.
2) Capture max houses, max hearts, and population counts.
3) Summarize limiting factors (materials, attacks, AI flow).

**Output:**
- Table of trials + max population metrics.
- Short analysis of growth blockers.

### /popcap-audit
**Purpose:** Explain and validate population cap mechanics; update naming/terms if
refactors are requested (house vs village vs team).

**Inputs:**
- `rename_policy`: `none|audit|apply`
- `terms`: map of old->new (e.g., `house->village`)

**Steps:**
1) Trace pop cap calculation through `buildingPopCap` and `step.nim`.
2) Identify caps beyond `MapAgentsPerTeam`.
3) If `rename_policy=apply`, execute mechanical renames and update comments.

**Output:**
- Explanation of current cap logic.
- Rename impact list or applied patch.

### /wildlife-extend
**Purpose:** Add or adjust roaming wildlife (cows/bears/wolves) and ensure
behavior fits the existing Thing model.

**Inputs:**
- `add`: list of new wildlife kinds
- `tuning`: stats overrides (hp, damage, aggro radius)
- `spawn`: counts and pack/herd sizes

**Steps:**
1) Extend `ThingKind`, registry, and observation layers.
2) Add spawn rules in `src/spawn.nim`.
3) Add movement/attack logic in `src/step.nim`.
4) Update AI predator-cull behaviors (optional).

**Output:**
- Summary of wiring points + tests to run.

### /terrain-river-tweak
**Purpose:** Adjust river generation to be more organic while preserving bridges
and tributaries.

**Inputs:**
- `meander`: float tuning (default from constants)
- `tributaries`: integer count

**Steps:**
1) Review `generateRiver` in `src/terrain.nim`.
2) Propose parameter tweaks or pathing changes.
3) Apply and run a quick terrain-generation sanity check.

**Output:**
- Description of changes + expected visual effect.

### /terminology-audit
**Purpose:** Audit naming consistency (team vs tribe vs village vs house) and
provide an actionable rename plan.

**Inputs:**
- `preferred`: list of canonical terms
- `apply`: `true|false`

**Steps:**
1) Search code/comments/docs for ambiguous or legacy terms.
2) Produce a change map with file references.
3) Optionally apply mechanical renames.

**Output:**
- Rename plan (and patch if applied).
