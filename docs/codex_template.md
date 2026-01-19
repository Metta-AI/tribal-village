# Codex Command Templates

Date: 2026-01-19
Owner: DevEx / Tools
Status: Draft

This file collects candidate slash-command / skill templates derived from
Codex session analysis. Each entry is a repeatable ask with a suggested
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
