# Test Suite Audit Report

Date: 2026-01-31
Owner: Engineering / QA
Status: Active
Issue: tv-o4qfd
Auditor: polecat/nux

## Executive Summary

The tribal_village test suite contains 49 test files covering various aspects of game behavior, domain logic, and integration scenarios. The tests are generally well-structured but have several coverage gaps, potential flaky tests, and some weak assertions that could mask real failures.

---

## 1. Coverage Gaps

### 1.1 Source Modules Without Direct Test Coverage

The following source modules in `src/` do not have corresponding dedicated test files:

| Module | Lines | Purpose | Risk |
|--------|-------|---------|------|
| `action_audit.nim` | - | Action tracking/debugging | Low |
| `actions.nim` | - | Action encoding/decoding | Medium |
| `combat_audit.nim` | - | Combat analysis | Low |
| `command_panel.nim` | - | UI command panel | Low (UI) |
| `console_viz.nim` | - | Console visualization | Low (Debug) |
| `ffi.nim` | - | Foreign function interface | Medium |
| `gather_heatmap.nim` | - | Resource gathering heatmaps | Low |
| `perf_regression.nim` | - | Performance testing | Low |
| `renderer.nim` | - | Game rendering | Low (UI) |
| `replay_analyzer.nim` | - | Replay analysis | Medium |
| `replay_common.nim` | - | Replay utilities | Medium |
| `replay_writer.nim` | - | Replay file writing | Medium |
| `spatial_index.nim` | - | Spatial indexing | High |
| `state_diff.nim` | - | State comparison | Medium |
| `state_dumper.nim` | - | State serialization | Medium |
| `tileset.nim` | - | Tile graphics | Low (UI) |
| `tint.nim` | - | Color tinting | Low (UI) |
| `tumor_audit.nim` | - | Tumor system analysis | Low |

**Recommendations:**
- **High Priority:** Add unit tests for `spatial_index.nim` - this is likely used for collision detection and pathfinding
- **Medium Priority:** Add tests for `actions.nim` (action encoding is critical), `ffi.nim` (external interface), and replay modules
- **Low Priority:** UI and debug modules can remain without direct tests

### 1.2 Critical Paths Potentially Undertested

Based on analysis of the codebase, these critical paths may need additional coverage:

1. **Market Price Dynamics:** `behavior_trade.nim` tests basic trading but may not cover edge cases like:
   - Price floor/ceiling enforcement
   - Concurrent multi-team trading effects
   - Long-term price recovery

2. **Multi-Building Garrison:** Tests exist for single building garrison but multi-building evacuation/transfer scenarios are sparse

3. **AI Handoff Scenarios:** When AI control switches teams mid-game via Tab key cycling

---

## 2. Flaky Tests

### 2.1 Currently Failing Tests (Pre-existing)

**File:** `tests/behavior_balance.nim`

| Test | Status | Analysis |
|------|--------|----------|
| `no team wins more than 80% of games` | FAILING | Depends on emergent simulation behavior across seeds. May fail if game balance changes. |
| `all teams have surviving units across seeds` | FAILING | Same issue - emergent behavior varies. |

**Root Cause:** These tests run multi-step simulations and check aggregate outcomes. They are inherently sensitive to any changes in AI behavior, combat mechanics, or spawn logic.

**Filed:** tv-iecjt

### 2.2 Tests with Flakiness Risk

**Pattern: Fixed Seeds with Long Simulations**

Tests that rely on specific outcomes from long simulations are inherently fragile:

| File | Test Pattern | Risk |
|------|--------------|------|
| `behavior_ai.nim` | 300-step simulations with seed 42 | Medium |
| `integration_behaviors.nim` | 500-step games with fixed seeds | Medium |
| `fuzz_seeds.nim` | 100 games × 200 steps | High (good for catching crashes, but long runtime) |
| `behavior_balance.nim` | 20 games × 500 steps | High |

**Pattern: Race Conditions**

Tests in `behavior_wonder_race.nim` depend on specific step ordering which could become flaky if step timing changes.

**Pattern: Probabilistic Mechanics**

| File | Issue |
|------|-------|
| `ai_harness.nim:164-194` | Biome bonus tests - run 1000 trials but check only `>= 10` and `<= 500` |
| `behavior_ai.nim:380` | "different seeds produce different outcomes" - doesn't hard-fail on collision |

---

## 3. Poor Assertions

### 3.1 Always-True Assertions

These assertions effectively pass regardless of actual behavior:

```nim
# behavior_ai.nim:190
check anyCombat or true  # Pass even if no combat (teams might not have met)

# behavior_villagers.nim:191
check repaired or hpAfter >= hpBefore - 1 or true  # Relaxed check - repair is best-effort

# behavior_villagers.nim:454
check anyProgress or true  # Pass if simulation ran
```

**Impact:** These tests provide no regression protection - they always pass.

**Recommendation:** Either:
- Remove these tests (they provide false confidence)
- Tighten assertions to require actual behavior
- Add comments explaining why relaxed checks are acceptable

### 3.2 Overly Permissive Assertions

```nim
# behavior_economy.nim:83
check totalAt200 > 0 or totalAt100 > 0

# behavior_ai.nim:116
check totalAt100 > 0 or totalAt200 > 0
```

**Issue:** These check that resources were gathered at EITHER checkpoint, not that the economy is functioning properly over time.

### 3.3 Missing Negative Case Testing

Many tests verify success cases but don't test that failures are properly handled:

- Building placement tests verify successful placement but few test that invalid placements are rejected
- Combat tests verify damage is dealt but few verify damage is NOT dealt when it shouldn't be (range, team, etc.)

---

## 4. Test Organization Issues

### 4.1 Duplicate Test Coverage

Some functionality is tested in multiple places with slight variations:
- Monk conversion tested in `behavior_combat.nim`, `behavior_diplomacy.nim`, and `domain_conversion_relics.nim`
- Garrison mechanics in `behavior_garrison.nim` and `domain_garrison.nim`

**Recommendation:** Consolidate or clearly delineate unit vs integration scope.

### 4.2 Test Naming Inconsistency

- `behavior_*` vs `domain_*` distinction is unclear
- Some `domain_*` tests are behavioral, some are unit-level

---

## 5. Recommendations Summary

### Immediate Actions

1. **Fix or Skip Balance Tests** - The failing tests should be either fixed or marked as `skip` with a tracking issue

2. **Remove Always-True Assertions** - Tests with `or true` provide no value and should be tightened or removed

3. **Add spatial_index Tests** - This is a critical module without dedicated tests

### Short-term Improvements

4. **Add Negative Case Testing** - Especially for:
   - Invalid building placement
   - Out-of-range attacks
   - Cross-team action blocking

5. **Document Test Categories** - Clarify the distinction between `behavior_*` and `domain_*` tests

### Long-term Considerations

6. **Consider Property-Based Testing** - For balance-sensitive tests, consider using property-based testing that's more robust to parameter changes

7. **Add Test Coverage Metrics** - Implement `scripts/coverage_report.nim` to track coverage over time

---

## Appendix: Test File Inventory

| Category | Count | Files |
|----------|-------|-------|
| Behavior Tests | 25 | behavior_*.nim |
| Domain Tests | 17 | domain_*.nim |
| Integration | 1 | integration_behaviors.nim |
| Fuzz/Stress | 1 | fuzz_seeds.nim |
| Harness/Utils | 3 | ai_harness.nim, log_harness.nim, test_utils.nim |
| Determinism | 1 | test_map_determinism.nim |
| Unit Tests | 1 | test_balance_scorecard.nim |
| **Total** | **49** | |

---

*Report generated as part of test audit (tv-o4qfd)*
