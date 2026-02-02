# tribal_village Performance Optimization Tasks

> Generated: 2026-02-02
> Status: 7/7 complete ✅
> Goal: Improve from ~2.25 steps/sec to 7-10+ steps/sec

## Completed

### tv-1za43: Spatial Utilities Consolidation ✅
Added new utilities to `src/spatial_index.nim`:
- `findNearestThingOfKindsSpatial()` - multi-kind queries (Agent OR Tumor)
- `collectThingsInRangeSpatial()` - generic collection by kind
- `collectAgentsByClassInRange()` - unit-class filtering (tanks, monks)

### tv-8zpne: Predator Targeting with Spatial Queries ✅
**Commit:** `c4c693d perf: use spatial query for predator targeting`

Replaced O(radius²) grid scans with `findNearestPredatorTargetSpatial()` for wolf packs
and bears. The new spatial query uses cell-based partitioning for efficient lookups.

### tv-5p1h6: Aura Processing Optimization ✅
**Commit:** `cea913f perf: optimize aura processing with dedicated unit collections`

Added `env.tankUnits` and `env.monkUnits` collections maintained on spawn/death/class-change.
Aura processing now iterates only relevant units instead of all agents.

### tv-z6sib: Spawner Tumor Scan with Spatial Query ✅
**Commit:** `3ad7b56 perf: replace spawner tumor scan with spatial query`

Replaced 11x11 grid scans with `countUnclaimedTumorsInRangeSpatial()`.

### tv-5zkfl: Staggered AI Threat Map Updates ✅
**Commit:** `ae9e378 perf: stagger AI threat map updates across steps`
**Commit:** `24431b2 perf: stagger threat map decay to every 5 steps`

Threat map updates now staggered by agent ID mod 5, reducing per-step cost by 5x.

### tv-eemdy: Fighter Target Re-evaluation Optimization ✅
**Commit:** `e6cde2f perf: optimize fighter target re-evaluation`
**Commit:** `a3c91b5 perf: optimize fighter target evaluation with cache and reduced frequency`

Increased `TargetSwapInterval` and added caching for `isThreateningAlly()` results.

### tv-53xww: Combat Aura Damage Check with Spatial Query ✅
**Commit:** `1e9a8c9 perf: use spatial query for tank aura damage reduction`

Replaced O(n) agent scan with `collectAgentsByClassInRange()` for tank aura damage reduction

---

## Summary Table

| Task | File(s) | Status |
|------|---------|--------|
| Predator targeting | step.nim, spatial_index.nim | ✅ Complete |
| Aura processing | step.nim, types.nim, spawn.nim | ✅ Complete |
| Spawner tumor scan | step.nim | ✅ Complete |
| Threat map stagger | ai_defaults.nim, ai_core.nim | ✅ Complete |
| Fighter target cache | fighter.nim, constants.nim | ✅ Complete |
| Combat aura check | combat.nim | ✅ Complete |

## Testing

To verify performance, run:
```bash
nim c -r -d:release --path:src scripts/perf_baseline.nim --steps 1000
nim c -r --path:src tests/integration_behaviors.nim
```

## Key Insight

The spatial index infrastructure (`src/spatial_index.nim`) is well-designed and provides
efficient cell-based partitioning for O(1) amortized spatial queries. All hot paths now
use these utilities instead of O(n) or O(n²) scans.
