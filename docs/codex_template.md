# Codex Template Commands

Date: 2026-01-19
Owner: Docs / Codex
Status: Draft

These are candidate slash-commands/skills distilled from repeated Codex session requests
inside this repo. They are phrased as reusable templates with parameters.

---

## /tv-play-smoke
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

**Notes:** Use ANSI mode when GUI hang is suspected. Capture output from `Loading tribal assets...`.

---

## /tv-asset-orient
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

---

## /tv-asset-fix
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

---

## /tv-cleanup-audit
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

---

## /tv-worldgen-debug
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

---

## /tv-training-smoke
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

---

## /tv-install-debug
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

---

## /tv-ai-behavior-audit
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

---

## /tv-replay-enable
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
