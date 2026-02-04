# Step() Hotpath Profile Analysis

Date: 2026-02-04
Issue: tv-wisp-7vl1ha
Author: polecat/ace

## Executive Summary

Profiled the `step()` function using built-in stepTiming instrumentation with 1000 agents over 1000 steps. **Current performance exceeds the 60fps target** at ~76 steps/second.

## Test Configuration

- Agents: 1006 (125 per team x 8 teams + goblins)
- Steps profiled: 1000 (after 100 warmup)
- Controller: BuiltinAI
- Build: `-d:release -d:stepTiming`

## Results

### Subsystem Breakdown (% of step() time)

| Subsystem | Avg % | Notes |
|-----------|-------|-------|
| **tintObs** | 82-86% | Dominant hotpath |
| actions | 7-10% | Agent action processing |
| things | 2-3% | Thing updates |
| tumorDamage | 2% | Tumor damage calc |
| tumors | 1% | Tumor processing |
| popRespawn | 0.5% | Respawn logic |
| preDeaths | 0.3% | Zero HP enforcement |
| auras | 0.1% | Aura processing |
| shields | 0.1% | Shield decay |
| actionTint | 0.1% | Action tint decay |

### Performance Metrics

| Metric | Value |
|--------|-------|
| Steps/second | 76.4 |
| Avg step time | 2.04ms |
| Max step time | 4.54ms |
| Per-agent AI | 10.98us |

### tintObs Growth Over Time

The tint observation subsystem grows as agents leave trails:

| Step Range | tintObs (ms) | % of step |
|------------|-------------|-----------|
| 100-200 | 0.73 | 82% |
| 500-600 | 1.72 | 83% |
| 900-1000 | 2.45 | 86% |

This 6x growth is expected as more tiles become "active" from agent movement trails.

## Spatial Index Efficiency

The spatial index is well-optimized:
- Cell-based partitioning with O(1) amortized queries
- Pre-computed lookup tables for distance-to-cell-radius
- Incremental updates (swap-and-pop for O(1) removal)
- Auto-tuning capability via `-d:spatialAutoTune`

No O(n^2) patterns found in spatial queries.

## Recommendations

1. **tintObs optimization opportunities:**
   - Consider reducing trail persistence (faster decay)
   - Batch tint updates less frequently (every N steps)
   - Use SIMD for tint color calculations

2. **Current hotpath complexity (post-optimization):**
   - `updateThreatMapFromVision`: O(visionRange^2) per agent
   - `findAttackOpportunity`: O(8*maxRange) line scan per agent
   - `needsPopCapHouse`: O(1) cached per-step

3. **Remaining O(n) candidates (from profile_ai.nim output):**
   - `nearestFriendlyBuildingDistance`: O(things) linear scan
   - `hasTeamLanternNear`: O(things) linear scan per call
   - `optFighterLanterns`: O(things) scan for unlit buildings

## Conclusion

**Target achieved:** 76 steps/sec > 60fps requirement with 1000+ agents.

The tint observation system is the dominant hotpath but is functioning correctly. Further optimization would require architectural changes to the trail/tint system if higher frame rates are needed.
