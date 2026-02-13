# Step Tick - Timing infrastructure and tick-related helpers
# This file is included by step.nim

# ============================================================================
# Reward Batch Timing (compile-time conditional)
# ============================================================================

when defined(rewardBatch):
  import std/monotimes
  var rewardBatchOps: int = 0
  var rewardBatchCumMs: float64 = 0.0
  var rewardBatchSteps: int = 0
  const RewardBatchReportInterval = 500

  proc rewardBatchMsBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

  proc reportRewardBatch() =
    if rewardBatchSteps > 0:
      let avgOps = rewardBatchOps.float64 / rewardBatchSteps.float64
      let avgMs = rewardBatchCumMs / rewardBatchSteps.float64
      echo "[rewardBatch] steps=", rewardBatchSteps,
        " avgOps/step=", avgOps,
        " avgMs/step=", avgMs
      rewardBatchOps = 0
      rewardBatchCumMs = 0.0
      rewardBatchSteps = 0

# ============================================================================
# Step Timing Infrastructure (compile-time conditional)
# ============================================================================

when defined(stepTiming):
  import std/monotimes

  let stepTimingTarget = parseEnvInt("TV_STEP_TIMING", -1)
  let stepTimingWindow = parseEnvInt("TV_STEP_TIMING_WINDOW", 0)
  let stepTimingInterval = parseEnvInt("TV_TIMING_INTERVAL", 100)

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

  const TimingSystemCount = 11
  const TimingSystemNames: array[TimingSystemCount, string] = [
    "actionTint", "shields", "preDeaths", "actions", "things",
    "tumors", "tumorDamage", "auras", "popRespawn", "survival", "tintObs"
  ]

  var timingCumSum: array[TimingSystemCount, float64]
  var timingCumMax: array[TimingSystemCount, float64]
  var timingCumTotal: float64 = 0.0
  var timingStepCount: int = 0

  proc resetTimingCounters() =
    for i in 0 ..< TimingSystemCount:
      timingCumSum[i] = 0.0
      timingCumMax[i] = 0.0
    timingCumTotal = 0.0
    timingStepCount = 0

  proc recordTimingSample(idx: int, ms: float64) =
    timingCumSum[idx] += ms
    if ms > timingCumMax[idx]:
      timingCumMax[idx] = ms

  proc printTimingReport(currentStep: int) =
    if timingStepCount == 0:
      return
    let n = timingStepCount.float64
    echo ""
    echo "=== Step Timing Report (steps ", currentStep - timingStepCount + 1, "-", currentStep, ", n=", timingStepCount, ") ==="
    echo align("System", 14), " | ", align("Avg ms", 10), " | ", align("Max ms", 10), " | ", align("% Total", 8)
    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 8)
    for i in 0 ..< TimingSystemCount:
      let avg = timingCumSum[i] / n
      let maxMs = timingCumMax[i]
      let pct = if timingCumTotal > 0.0: timingCumSum[i] / timingCumTotal * 100.0 else: 0.0
      echo align(TimingSystemNames[i], 14), " | ",
           align(formatFloat(avg, ffDecimal, 4), 10), " | ",
           align(formatFloat(maxMs, ffDecimal, 4), 10), " | ",
           align(formatFloat(pct, ffDecimal, 1), 8)
    let totalAvg = timingCumTotal / n
    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 8)
    echo align("TOTAL", 14), " | ", align(formatFloat(totalAvg, ffDecimal, 4), 10), " | ", align("", 10), " | ", align("100.0", 8)
    echo ""
    resetTimingCounters()

# ============================================================================
# Perf Regression (compile-time conditional)
# ============================================================================

when defined(perfRegression):
  include "perf_regression"

  proc msBetweenPerfTiming(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

# ============================================================================
# Flame Graph (compile-time conditional)
# ============================================================================

when defined(flameGraph):
  include "flame_graph"

# ============================================================================
# Tick Helpers
# ============================================================================

proc stepApplySurvivalPenalty(env: Environment) =
  ## Apply per-step survival penalty to all living agents
  if env.config.survivalPenalty != 0.0:
    let penalty = env.config.survivalPenalty
    when defined(rewardBatch):
      # Batch: apply penalty to contiguous rewards array for SIMD-friendly access
      for i in 0 ..< MapAgents:
        if env.terminated[i] == 0.0 and env.truncated[i] == 0.0:
          env.rewards[i] += penalty
    else:
      for agent in env.agents:
        if isAgentAlive(env, agent):
          env.rewards[agent.agentId] += penalty

proc isOutOfBounds(pos: IVec2): bool {.inline.} =
  ## Check if position is outside the playable map area (within border margin)
  pos.x < MapBorder.int32 or pos.x >= (MapWidth - MapBorder).int32 or
  pos.y < MapBorder.int32 or pos.y >= (MapHeight - MapBorder).int32

proc applyFertileRadius(env: Environment, center: IVec2, radius: int) =
  ## Apply fertile terrain in a Chebyshev radius around center, skipping blocked tiles
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue
      if max(abs(dx), abs(dy)) > radius:
        continue
      let pos = center + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if not env.isEmpty(pos) or env.hasDoor(pos) or
         isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
        continue
      let terrain = env.terrain[pos.x][pos.y]
      if terrain notin BuildableTerrain:
        continue
      env.terrain[pos.x][pos.y] = Fertile
      env.resetTileColor(pos)
      env.updateObservations(ThingAgentLayer, pos, 0)

# ============================================================================
# Adjacent Building Search
# ============================================================================

proc findAdjacentFriendlyBuilding*(env: Environment, pos: IVec2, teamId: int,
                                    kindPredicate: proc(k: ThingKind): bool): Thing =
  ## Find an adjacent building matching kindPredicate owned by the given team.
  ## Returns nil if no matching building found.
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      let checkPos = pos + ivec2(dx.int32, dy.int32)
      if not isValidPos(checkPos):
        continue
      let b = env.getThing(checkPos)
      if not b.isNil and kindPredicate(b.kind) and b.teamId == teamId:
        return b
  nil

# Note: isGarrisonableBuilding and isTownCenterKind are defined in step.nim
# after building_combat.nim is included (they depend on garrisonCapacity)
