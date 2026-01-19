# Codex Command Templates (Draft)

Date: 2026-01-19
Owner: Docs / Tooling
Status: Draft

These candidate slash commands are inferred from repeated patterns in the Codex
log for `tribal-village` (heavy use of `rg`, `sed -n`, Nim build/run/test, and
systematic spelunking of `environment.nim`, `renderer.nim`, `terrain.nim`,
`spawn.nim`, `registry.nim`, `step.nim`). They are intended to be easy-to-run
skills that match the most common asks.

---

## /tv-validate
**Purpose**: Run the standard build/run/test pipeline used in most changes.

**Typical ask**: “run the compile, play, and ai_harness tests” / “validate before commit”.

**Template steps**:
1. `nim c -d:release tribal_village.nim`
2. `timeout 15s nim r -d:release tribal_village.nim` (or `gtimeout` on macOS)
3. `nim r --path:src tests/ai_harness.nim`

---

## /tv-spelunk <pattern>
**Purpose**: Fast codebase search + open likely files for a mechanic.

**Typical ask**: “find where X is handled” / “show me the code for X”.

**Template steps**:
1. `rg -n "<pattern>" src` (include `docs` if needed)
2. Open the top 2–3 hits with `sed -n '1,240p' <file>`.

**Notes**: Logs show repeated use of `rg -n` + `sed -n` for investigation.

---

## /tv-terrain-elevation
**Purpose**: Investigate cliffs, ramps, and elevation traversal.

**Typical ask**: “how do cliffs/ramps work” / “why is movement blocked on elevation”.

**Template steps**:
1. `rg -n "applyBiomeElevation|applyCliffRamps|applyCliffs" src/spawn.nim`
2. `sed -n '120,260p' src/spawn.nim`
3. `rg -n "canTraverseElevation" src/environment.nim`
4. `sed -n '400,460p' src/environment.nim`
5. `rg -n "RampUp|RampDown|Cliff" src/terrain.nim src/types.nim src/registry.nim`

---

## /tv-tint-freeze
**Purpose**: Investigate clippy tint, action tints, and frozen tiles.

**Typical ask**: “why are tiles frozen” / “how does tint layer work”.

**Template steps**:
1. `rg -n "Tint|tint|Clippy|frozen" src/tint.nim src/colors.nim src/step.nim src/renderer.nim`
2. `sed -n '1,200p' src/tint.nim`
3. `sed -n '1,160p' src/colors.nim`
4. `rg -n "TintLayer" src/environment.nim`

---

## /tv-game-loop
**Purpose**: Open the main step loop and action handlers.

**Typical ask**: “how does the step loop work” / “where is action X implemented”.

**Template steps**:
1. `sed -n '1,220p' src/step.nim`
2. `rg -n "case verb|attackAction|useAction|buildAction" src/step.nim`
3. `sed -n '220,900p' src/step.nim`

---

## /tv-observation
**Purpose**: Inspect observation space and inventory encoding.

**Typical ask**: “what is in the observation layers” / “why is item X not visible”.

**Template steps**:
1. `rg -n "ObservationName|ObservationLayers|TintLayer" src/types.nim`
2. `sed -n '150,260p' src/types.nim`
3. `rg -n "updateObservations|updateAgentInventoryObs" src/environment.nim`
4. `sed -n '1,200p' src/environment.nim`

---

## /tv-economy-respawn
**Purpose**: Inspect inventory/stockpile rules, altars/hearts, and respawn logic.

**Typical ask**: “how do hearts/altars work” / “why aren’t agents respawning”.

**Template steps**:
1. `rg -n "altar|hearts|respawn" src/step.nim src/items.nim src/types.nim`
2. `sed -n '1800,2100p' src/step.nim`
3. `sed -n '1,200p' src/items.nim`

---

## /tv-git-scan
**Purpose**: Quick state + history check before/after changes.

**Typical ask**: “what changed?” / “show me recent commits”.

**Template steps**:
1. `git status -sb`
2. `git diff --stat`
3. `git log --oneline -n 20`

