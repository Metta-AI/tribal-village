# Tribal Village Performance Improvements

Date: 2026-01-28
Owner: Engineering / Analysis
Status: Active

## Summary

A 38% performance improvement was achieved by optimizing how agent observations are updated during each simulation step. The change moved from incremental per-tile updates to a batch rebuild strategy.

**Results:**
- Before: ~733 steps/second
- After: ~1017 steps/second
- Improvement: **38% faster**

## The Problem

Tribal Village simulates a multi-agent environment where each of the 1006 agents has an 11x11 observation window showing the world around them. These observations must be kept in sync as the game state changes.

The original implementation used **incremental updates**: every time something in the world changed (agent moved, item picked up, building placed, etc.), the `updateObservations()` function was called. This function iterated through *every single agent* to check if the change was visible to them:

```nim
# OLD: Called ~50+ times per step
proc updateObservations(env, layer, pos, value) =
  for agentId in 0 ..< agentCount:  # 1006 agents
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    # Check if this tile is in agent's view...
    # Update observation if visible
```

With approximately 50+ world changes per step, this resulted in:
- **~50,300 agent iterations per step** (50 updates * 1006 agents)
- Function call overhead for each `updateObservations` call
- Poor cache locality due to scattered access patterns
- Profile showed `updateObservations` consuming **65% of total runtime**

## The Solution

Replace incremental updates with a single **batch rebuild** at the end of each step:

```nim
# NEW: Called once per step
proc rebuildObservations(env: Environment) =
  zeroMem(addr env.observations, sizeof(env.observations))
  for agentId in 0 ..< env.agents.len:  # 1006 agents
    # Rebuild entire 11x11 observation window
    for obsX in 0 ..< 11:
      for obsY in 0 ..< 11:
        writeTileObs(env, agentId, obsX, obsY, worldX, worldY)
```

The old `updateObservations()` function becomes a no-op:

```nim
proc updateObservations(env, layer, pos, value) {.inline.} =
  discard  # Observations rebuilt in batch at end of step()
```

## Complexity Analysis

| Approach | Operations per Step |
|----------|-------------------|
| **Incremental** | O(updates * agents) = ~50 * 1006 = ~50,300 |
| **Batch rebuild** | O(agents * tiles) = 1006 * 121 = ~121,726 |

While the batch approach does more absolute work, it's faster because:

1. **Single function call** vs 50+ calls with associated overhead
2. **Predictable memory access** - sequential iteration through agents and tiles
3. **Better cache utilization** - all observation memory accessed in order
4. **Eliminated redundant checks** - no per-update visibility calculations

## Additional Optimizations

The commit also included these micro-optimizations:

1. **Removed redundant zeroing** - `writeTileObs` no longer zeros values since `rebuildObservations` does a single `zeroMem` upfront

2. **Added inline pragmas** - `writeTileObs` and `isAgentAlive` marked `{.inline.}` for better codegen

3. **Conditional writes** - Only write non-zero values since memory is pre-zeroed:
   ```nim
   if teamValue != 0:
     agentObs[][ord(TeamLayer)][obsX][obsY] = teamValue.uint8
   ```

4. **Simplified team ownership logic** - Removed redundant Agent kind checks in non-agent branch

## Profile Comparison

| Metric | Before | After |
|--------|--------|-------|
| updateObservations | 65% | 0% (eliminated) |
| rebuildObservations | N/A | 57% |
| Reference counting overhead | 28% | 7% |
| Steps/second | 733 | 1017 |

## Key Insight

The counterintuitive lesson: **doing more work in a single batch can be faster than doing less work spread across many calls**. The overhead of function calls, cache misses, and scattered memory access can dominate actual computation time.

## Files Changed

- `src/environment.nim` - Core observation functions
- `src/step.nim` - Added `rebuildObservations()` call at end of step
- `src/types.nim` - Added inline pragma to `isAgentAlive`
