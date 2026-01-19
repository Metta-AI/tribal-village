# Codex Command Templates

Date: 2026-01-19
Owner: DevEx / Tools
Status: Draft

This file collects candidate slash-command / skill templates derived from
Codex session analysis. Each entry is a **repeatable ask** with a suggested
command signature and expected artifacts.

## Candidates (tribal-village)

### /update-readme-observations
**Intent:** Reconcile `README.md` with current gameplay and observation space.
**Typical prompt:** "README is out of date with features/observations; update it
based on code."\
**Inputs:** None (source of truth is code).\
**Outputs:** Updated `README.md` sections for features + observation layout.
**Likely files:** `README.md`, `src/types.nim`, `src/environment.nim`, `src/ffi.nim`.

### /run-validation
**Intent:** Run the standard local validation steps for this repo.\
**Typical prompt:** "debug and make sure tests pass" / "run validations".\
**Outputs:** Command results + summarized status.
**Commands:**
- `nim c -d:release tribal_village.nim`
- `timeout 15s nim r -d:release tribal_village.nim`
- `nim r --path:src tests/ai_harness.nim`

### /worldgen-hub-variation
**Intent:** Make the central trading hub feel more organic and busy without
blocking roads.\
**Typical prompt:** "add more buildings around hub, keep roads clear" or
"make walls less boxy".\
**Outputs:** Updated hub placement and wall generation.
**Likely files:** `src/spawn.nim` (tradingHub block).

### /worldgen-river-tune
**Intent:** Adjust river meandering intensity (less/more).\
**Typical prompt:** "rivers are too meandering now; reduce".\
**Outputs:** Tweaked river drift probabilities.
**Likely files:** `src/terrain.nim` (`generateRiver`).

### /spawn-goblin-hives
**Intent:** Ensure a fixed count of goblin nests/hives per map.\
**Typical prompt:** "every map should spawn two goblin nests".\
**Outputs:** Updated spawn logic and spacing checks.
**Likely files:** `src/spawn.nim` (goblin hive block).

### /ai-add-behaviors
**Intent:** Add new behavior options to the AI pool without changing
core gatherer/builder/fighter logic.\
**Typical prompt:** "add behaviors/options for new items or creatures".\
**Outputs:** New `OptionDef`s plus wiring into role option lists.
**Likely files:** `src/scripted/options.nim`, `src/scripted/ai_defaults.nim`.

### /ai-behavior-ideation
**Intent:** Generate a list of new, scoped behaviors aligned to territory
control objectives.\
**Typical prompt:** "outline 25 new behaviors for meta-role system".\
**Outputs:** Behavior list with brief descriptions (no code changes).

### /inline-one-offs
**Intent:** Inline single-use helpers and remove small layers of indirection.\
**Typical prompt:** "audit for verbosity; inline one-use helpers".\
**Outputs:** Small refactors that reduce indirection.
**Likely files:** broad; often `src/step.nim`, `src/spawn.nim`, `src/tileset.nim`,
`src/combat.nim`.

### /cleanup-audit
**Intent:** Audit for cleanup or complexity hotspots and propose targets.\
**Typical prompt:** "audit for cleanup/conciseness" or "overly complex logic".\
**Outputs:** Ranked list of candidates; no code changes unless requested.

### /include-sprawl-map
**Intent:** Map include chains and explain how modules relate.\
**Typical prompt:** "map include sprawl and explain callsites".\
**Outputs:** Clear include graph + callsite notes.
**Likely files:** `src/agent_control.nim`, `src/scripted/*.nim`.

### /ai-chain-modularize-plan
**Intent:** Produce a concrete modularization plan for the AI include chain.\
**Typical prompt:** "how would you modularize ai chain?".\
**Outputs:** Step plan with proposed module boundaries and low-risk sequencing.

### /codex-log-docs
**Intent:** Read Codex logs for this repo and synthesize docs in `docs/`.\
**Typical prompt:** "audit codex sessions and write topic docs".\
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
