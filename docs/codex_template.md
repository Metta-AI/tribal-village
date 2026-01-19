# Codex Template Commands (Tribal Village)

Date: 2026-01-19
Owner: Docs / Codex
Status: Draft

## Purpose
These templates capture recurring requests found in the Codex session logs for
`/Users/relh/Code/workspace/tribal-village`. They are candidates for skills or
slash commands to standardize common workflows.

---

## /assets:normalize
**Goal**: Normalize sprite assets (transparency + size) in batch.

**Inputs**
- Target folders (default: `data/`, `data/oriented/`)
- Target size (default: 256)
- Rules (e.g., skip full-tile terrain sprites, skip walls)

**Actions**
- Scan PNGs and detect non‑transparent backgrounds.
- Flood‑fill/key out background where needed.
- Crop to content and resize to the target square size.
- Report any files that could not be cleaned safely.

**Outputs**
- Updated PNGs with consistent sizing and alpha.
- Summary of changed files.

---

## /assets:split_quadrants
**Goal**: Split a 2x2 sprite sheet into four standalone PNGs.

**Inputs**
- Source image path
- Mapping for quadrants (top‑left, top‑right, bottom‑left, bottom‑right)
- Output paths

**Actions**
- Crop each quadrant to its own file.
- Optionally postprocess (crop to content + resize).
- Verify dimensions match expectations.

**Outputs**
- Four new PNGs, ready for registry mapping.

---

## /assets:oriented_generate
**Goal**: Generate or regenerate oriented sprites using prompts.

**Inputs**
- Prompt rows (from `data/prompts/assets.tsv`)
- Orientation set (`unit` or `edge`)
- Optional `--only` filter

**Actions**
- Run `scripts/generate_assets.py` with `--oriented` and postprocessing.
- Apply purple‑background keying for oriented sprites.
- Optional preview via `scripts/render_asset_preview.py`.

**Outputs**
- New oriented sprites under `data/oriented/`.
- Preview sheet for verification.

---

## /assets:wire_sprites
**Goal**: Hook newly added sprites into the registry and code.

**Inputs**
- ThingKind / ItemKey list
- Target sprite paths (including oriented variants)
- Fallback rules (if any)

**Actions**
- Update sprite registry mappings (e.g., `src/registry.nim`).
- Update any fallback sprite logic to avoid unwanted substitutions.
- Verify new assets are referenced in the renderer/tileset.

**Outputs**
- Code changes to map new assets correctly.
- Short report of any missing assets.

---

## /ai:role_audit
**Goal**: Audit scripted roles and summarize behavior coverage.

**Inputs**
- Scope (core roles, scripted roles, or both)

**Actions**
- Enumerate roles and option lists.
- Summarize high‑level intent per role.
- Flag missing behaviors or duplicated roles.

**Outputs**
- Short audit report (roles + gaps).
- Optional suggestion list for new roles/buildings.

---

## /ai:options_add
**Goal**: Add a new OptionDef to a role.

**Inputs**
- Role (gatherer / builder / fighter)
- Behavior name and priority
- Termination / interrupt rules

**Actions**
- Implement `canStart`, `act`, `shouldTerminate`.
- Wire into role option list in `src/scripted/ai_defaults.nim`.
- Add or update tests in `tests/ai_harness.nim` if needed.

**Outputs**
- New behavior added, tested, and documented.

---

## /worldgen:biome_tune
**Goal**: Adjust biome or terrain distribution parameters.

**Inputs**
- Target biome(s)
- Desired size/count/density changes

**Actions**
- Update constants in `src/terrain.nim` / `src/biome.nim`.
- Adjust spawn order or zone placement if required.
- Verify map generation remains connected.

**Outputs**
- Updated worldgen parameters.
- Quick summary of expected map changes.

---

## /worldgen:resource_clusters
**Goal**: Rebalance resource clustering and wildlife spawns.

**Inputs**
- Resource types (trees, wheat, stone, gold, fish, cows, etc.)
- Cluster size/density goals

**Actions**
- Update cluster spawning in `src/spawn.nim`.
- Validate spawn constraints (biomes, water, dungeons).
- Confirm connectivity still holds after placement.

**Outputs**
- Updated cluster logic.
- Summary of counts and placements.

---

## /merge:resolve
**Goal**: Resolve merge conflicts with repo‑specific priorities.

**Inputs**
- Branch target (usually `origin/main`)
- Priority rules (e.g., keep bumped counts, keep new assets)

**Actions**
- Merge/rebase and resolve conflicts with stated priorities.
- Re‑run required validation steps.

**Outputs**
- Clean merge commit and test report.

---

## /tests:validate_nim
**Goal**: Run the standard Nim validation suite.

**Actions**
- `nim c -d:release tribal_village.nim`
- `timeout 15s nim r -d:release tribal_village.nim`
- `nim r --path:src tests/ai_harness.nim`

**Outputs**
- Pass/fail summary with any warnings.

---

## Notes
These templates are intentionally short. If you want any of them expanded into
full skills (with scripts or reusable patches), we can scaffold them under
`$CODEX_HOME/skills` and link them here.
