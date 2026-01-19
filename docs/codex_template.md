# Codex Command Templates

Date: 2026-01-19
Owner: DevEx / Tools
Status: Draft

This file collects candidate slash-command / skill templates derived from
Codex session analysis. Each entry is a **repeatable ask** with a suggested
command signature and expected artifacts.

## Candidates (tribal-village)

### /run-validation
**Intent:** Run the standard local validation steps for this repo.\
**Typical prompt:** "debug and make sure tests pass" / "run validations".\
**Outputs:** Command results + summarized status.\
**Commands:**
- `nim c -d:release tribal_village.nim`
- `timeout 15s nim r -d:release tribal_village.nim`
- `nim r --path:src tests/ai_harness.nim`

### /update-readme-observations
**Intent:** Reconcile `README.md` with current gameplay and observation space.\
**Typical prompt:** "README is out of date with features/observations; update it based on code."\
**Inputs:** None (source of truth is code).\
**Outputs:** Updated `README.md` sections for features + observation layout.\
**Likely files:** `README.md`, `src/types.nim`, `src/environment.nim`, `src/ffi.nim`.

### /assets:normalize
**Intent:** Normalize sprite assets (transparency + size) in batch.\
**Typical prompt:** "make all PNGs 256x256 and true transparent".\
**Inputs:** Target folders, target size, skip rules.\
**Outputs:** Updated PNGs + summary of changed files.\
**Likely files:** `data/*.png`, `data/oriented/*.png`.

### /assets:split_quadrants
**Intent:** Split a 2x2 sprite sheet into four standalone PNGs.\
**Typical prompt:** "split this image into 4 items (quadrants)".\
**Inputs:** Source image, quadrant mapping, output paths.\
**Outputs:** Four new PNGs, ready for registry mapping.

### /assets:oriented_generate
**Intent:** Generate or regenerate oriented sprites using prompts.\
**Typical prompt:** "regenerate oriented sprites with purple background".\
**Inputs:** Prompt rows, orientation set, optional `--only` filter.\
**Outputs:** New oriented sprites + optional preview sheet.\
**Likely files:** `data/prompts/assets.tsv`, `scripts/generate_assets.py`, `data/oriented/*.png`.

### /assets:wire_sprites
**Intent:** Hook newly added sprites into the registry and code.\
**Typical prompt:** "wire the new PNGs to the correct ThingKinds".\
**Inputs:** ThingKind / ItemKey list, target sprite paths, fallback rules.\
**Outputs:** Code changes to map new assets correctly.\
**Likely files:** `src/registry.nim`, `src/tileset.nim`.

### /worldgen-hub-variation
**Intent:** Make the central trading hub feel more organic and busy without blocking roads.\
**Typical prompt:** "add more buildings around hub, keep roads clear" / "make walls less boxy".\
**Outputs:** Updated hub placement and wall generation.\
**Likely files:** `src/spawn.nim` (tradingHub block).

### /worldgen-river-tune
**Intent:** Adjust river meandering intensity (less/more).\
**Typical prompt:** "rivers are too meandering now; reduce".\
**Outputs:** Tweaked river drift probabilities.\
**Likely files:** `src/terrain.nim` (`generateRiver`).

### /worldgen:biome_tune
**Intent:** Adjust biome or terrain distribution parameters.\
**Typical prompt:** "make biomes 2x larger" / "change snow biome density".\
**Inputs:** Target biome(s), desired size/count/density changes.\
**Outputs:** Updated worldgen parameters + short summary.

### /worldgen:resource_clusters
**Intent:** Rebalance resource clustering and wildlife spawns.\
**Typical prompt:** "increase cow herds and resource clumps".\
**Inputs:** Resource types, cluster size/density goals.\
**Outputs:** Updated cluster logic + placement summary.\
**Likely files:** `src/spawn.nim`.

### /spawn-goblin-hives
**Intent:** Ensure a fixed count of goblin nests/hives per map.\
**Typical prompt:** "every map should spawn two goblin nests".\
**Outputs:** Updated spawn logic and spacing checks.\
**Likely files:** `src/spawn.nim` (goblin hive block).

### /ai:role_audit
**Intent:** Audit scripted roles and summarize behavior coverage.\
**Typical prompt:** "audit AI roles and note interesting/uninteresting ones".\
**Inputs:** Scope (core roles, scripted roles, or both).\
**Outputs:** Short audit report + optional suggestion list.

### /ai-add-behaviors
**Intent:** Add new behavior options to the AI pool without changing core role plumbing.\
**Typical prompt:** "add behaviors/options for new items or creatures".\
**Outputs:** New `OptionDef`s plus wiring into role option lists.\
**Likely files:** `src/scripted/options.nim`, `src/scripted/ai_defaults.nim`.

### /ai-behavior-ideation
**Intent:** Generate a list of new, scoped behaviors aligned to territory control objectives.\
**Typical prompt:** "outline 25 new behaviors for meta-role system".\
**Outputs:** Behavior list with brief descriptions (no code changes).

### /include-sprawl-map
**Intent:** Map include chains and explain how modules relate.\
**Typical prompt:** "map include sprawl and explain callsites".\
**Outputs:** Clear include graph + callsite notes.\
**Likely files:** `src/agent_control.nim`, `src/scripted/*.nim`.

### /ai-chain-modularize-plan
**Intent:** Produce a concrete modularization plan for the AI include chain.\
**Typical prompt:** "how would you modularize ai chain?".\
**Outputs:** Step plan with proposed module boundaries and low-risk sequencing.

### /inline-one-offs
**Intent:** Inline single-use helpers and remove small layers of indirection.\
**Typical prompt:** "audit for verbosity; inline one-use helpers".\
**Outputs:** Small refactors that reduce indirection.\
**Likely files:** broad; often `src/step.nim`, `src/spawn.nim`, `src/tileset.nim`,
`src/combat.nim`.

### /cleanup-audit
**Intent:** Audit for cleanup or complexity hotspots and propose targets.\
**Typical prompt:** "audit for cleanup/conciseness" or "overly complex logic".\
**Outputs:** Ranked list of candidates; no code changes unless requested.

### /merge:resolve
**Intent:** Resolve merge conflicts with repo-specific priorities.\
**Typical prompt:** "resolve conflicts; keep bumped counts".\
**Inputs:** Branch target + priority rules.\
**Outputs:** Clean merge commit and test report.

### /codex-log-docs
**Intent:** Read Codex logs for this repo and synthesize docs in `docs/`.\
**Typical prompt:** "audit codex sessions and write topic docs".\
**Outputs:** New or updated docs (AI, worldgen, observation space, etc.).\
**Likely files:** `docs/*.md`.

## Notes
These templates are intentionally short. If you want any of them expanded into
full skills (with scripts or reusable patches), we can scaffold them under
`$CODEX_HOME/skills` and link them here.
