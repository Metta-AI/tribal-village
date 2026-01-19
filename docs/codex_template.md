# Codex Command Templates

Date: 2026-01-19
Owner: DevEx / Tools
Status: Draft

This file collects candidate slash-command / skill templates derived from Codex
session analysis. Each entry is a repeatable ask with a suggested command
signature and expected artifacts.

---

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
**Likely files:** broad; often `src/step.nim`, `src/spawn.nim`, `src/tileset.nim`, `src/combat.nim`.

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
**Intent:** Produce a concrete modularization plan for the AI include chain.
**Typical prompt:** "how would you modularize ai chain?".
**Outputs:** Step plan with proposed module boundaries and low-risk sequencing.

### /codex-log-docs
**Intent:** Read Codex logs for this repo and synthesize docs in `docs/`.
**Typical prompt:** "audit codex sessions and write topic docs".
**Outputs:** New or updated docs (AI, worldgen, observation space, etc.).
**Likely files:** `docs/*.md`.

### /roles-evolution-plan
**Intent:** Outline or revise the scripted/evolutionary role system.
**Typical prompt:** "outline how roles evolve and integrate with AI".
**Inputs:** goals + constraints (core roles kept, scoring step, etc).
**Outputs:** plan + checklist for `docs/evolution.md`.
**Notes:** pairs well with `/scripted-refactor` and `/role-homogenize`.

### /scripted-refactor
**Intent:** Move AI logic into `src/scripted/` modules.
**Typical prompt:** "move AI code into scripted folder".
**Inputs:** source files + target module boundaries.
**Outputs:** updated includes and file layout.
**Notes:** keep gatherer/builder/fighter intact; avoid breaking tests.

### /role-homogenize
**Intent:** Make core roles share the same RoleDef/tier pipeline as evolved roles.
**Typical prompt:** "homogenize roles and options across core + evolution".
**Inputs:** roles to map (default: gatherer/builder/fighter).
**Outputs:** unified role materialization and decision routing.
**Notes:** preserve role tags for heuristics (gatherer tasks, pop-cap logic).

### /temple-asset
**Intent:** Create or update temple artwork.
**Typical prompt:** "generate a distinct temple asset".
**Inputs:** prompt edits + asset filename.
**Outputs:** updated `data/prompts/assets.tsv`, regenerated `temple.png`, preview.
**Notes:** runs `scripts/generate_assets.py`.

### /temple-hybrid-hookup
**Intent:** Wire temple adjacency to hybrid role generation.
**Typical prompt:** "if two agents stand near temple, spawn hybrid".
**Inputs:** trigger rules, costs (heart), cooldown.
**Outputs:** spawn logic + hybrid request enqueue + role recombination.
**Notes:** keep assignment toggles so experimentation is opt-in.

### /training-smoke
**Intent:** Validate training pipeline or metta integration.
**Typical prompt:** "run a small training job and log outputs".
**Inputs:** local vs metta, steps/envs/workers, logging.
**Outputs:** successful training run or actionable fixes.
**Notes:** may touch `pyproject.toml` optional deps.

### /repo-history-slim
**Intent:** Identify large blobs and propose history cleanup.
**Typical prompt:** "clone is huge; prune history".
**Inputs:** size thresholds and target branches.
**Outputs:** largest-blob report + filter-repo commands + coordination steps.
**Notes:** must warn about force-push + re-clone requirements.

### /terrain-cliff-audit
**Intent:** Audit cliff overlays and precedence vs walls/background layers.
**Typical prompt:** "cliffs should be the only overlay on a tile".
**Inputs:** overlay precedence rules.
**Outputs:** audit summary + fixes in placement/spawn/renderer.

### /combat-visuals-palette
**Intent:** Define combat overlays (auras, crits, counters, healing zones).
**Typical prompt:** "give unit types distinct combat visuals".
**Inputs:** unit types + visual language.
**Outputs:** palette recommendations and overlay behavior specs.

---

## CLI/Workflow Templates (tribal-village)

### /tv-play-smoke
**Purpose:** Verify the game runs locally (GUI or ANSI) after code changes.

**Inputs:**
- `render` = `gui|ansi` (default `gui`)
- `timeout_s` (default `15`)
- `ansi_steps` (default `128`)

**Template:**
```
# compile
nim c -d:release tribal_village.nim

# quick run (GUI)
# macOS: timeout 15s nim r -d:release tribal_village.nim
# if ANSI:
tribal-village play --render ansi --steps 128
```

**Notes:** Use ANSI mode when GUI hang is suspected. Capture output from
`Loading tribal assets...`.

### /tv-asset-orient
**Purpose:** Regenerate oriented unit sprites from prompts with consistent postprocess.

**Inputs:**
- `only` = `oriented/<name>.{dir}.png` (optional)
- `size` (default `200`)
- `tol` (default `35`)
- `purple_bg` = `true|false`

**Template:**
```
python scripts/generate_assets.py \
  --oriented \
  --postprocess \
  --postprocess-purple-bg \
  --size 200 \
  --postprocess-tol 35 \
  --only oriented/<name>.{dir}.png
```

**Notes:** Use `--postprocess-only` to iterate on tolerance without regenerating.

### /tv-asset-fix
**Purpose:** Fix an asset file (resize, transparency, or background keying).

**Inputs:**
- `path` = `data/<name>.png`
- `size` (default `200` or `256`)
- `transparent` = `true|false`

**Template:**
```
# Identify size and alpha first, then fix
python scripts/render_asset_preview.py --only <path>
# (apply resize or background keying using the existing postprocess pipeline)
```

**Notes:** Common asks: make 256x256, add transparency, remove purple background.

### /tv-cleanup-audit
**Purpose:** Audit Nim code for conciseness and remove one-off helpers.

**Inputs:**
- `targets` = `src/*.nim` or specific file list
- `style` = `reduce_lines_no_indirection`

**Template:**
```
# pick a target file and identify:
# - dead code
# - duplicate logic
# - one-use helpers to inline
# Then edit and run the standard validation sequence.
```

**Notes:** This matches repeated “simplify/inline/clean up” requests.

### /tv-worldgen-debug
**Purpose:** Tweak terrain/biomes/elevation/ramps and revalidate connectivity.

**Inputs:**
- `feature` = `swamp|snow|cliffs|ramps|river|trading_hub`
- `constraints` = key-value notes (elevation, placement, density)

**Template:**
```
# Update terrain/spawn rules
# - src/terrain.nim (biomes, rivers, swamp water)
# - src/spawn.nim (elevation, cliffs, hub)
# - src/connectivity.nim (connectivity pass)
# Then run play smoke test.
```

**Notes:** Sessions repeatedly request swamp elevation = -1, ramps every N cliffs,
trading hub placement tweaks, and river flow adjustments.

### /tv-training-smoke
**Purpose:** Verify the Python training CLI or metta wrapper still runs.

**Inputs:**
- `mode` = `tribal-village|cogames|metta`
- `steps` (default `100000`)

**Template:**
```
# tribal-village CLI (requires extras)
tribal-village train --steps 100000 --parallel-envs 4 --num-workers 2 --log-outputs

# metta wrapper
scripts/train_metta.sh --steps 100000 --parallel-envs 4 --num-workers 2 --log-outputs
```

**Notes:** Common failures include missing extras or wrong package resolution in metta.

### /tv-install-debug
**Purpose:** Debug install/toolchain errors (nimby, nim, pip/uv).

**Inputs:**
- `toolchain` = `nimby|pip|uv`

**Template:**
```
# Nim toolchain
nimby use 2.2.6
nimby sync -g nimby.lock

# Python package
pip install -e .
```

**Notes:** Typical errors include missing `nim`, missing `nimble`, or broken venvs.

### /tv-ai-behavior-audit
**Purpose:** Validate scripted AI roles and behavior ordering.

**Inputs:**
- `role` = `gatherer|builder|fighter` (or all)
- `behavior` = specific option names to check

**Template:**
```
# Inspect src/scripted/*.nim for behavior order and gating
# Run tests: nim r --path:src tests/ai_harness.nim
```

**Notes:** Recurring asks: reorder planting vs crafting, enforce bread-eating,
fix role regressions.

### /tv-replay-enable
**Purpose:** Turn on Nim replay output for a run.

**Inputs:**
- `dir` = output directory
- `label` = optional label

**Template:**
```
TV_REPLAY_DIR=/path/to/replays \
TV_REPLAY_LABEL="Tribal Village Replay" \
tribal-village play
```

**Notes:** Uses `src/replay_writer.nim` (ReplayVersion 3).
