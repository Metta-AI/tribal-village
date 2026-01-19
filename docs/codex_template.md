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
