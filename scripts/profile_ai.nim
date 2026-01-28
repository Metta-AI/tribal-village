## Headless driver for profiling the built-in AI (no renderer).
## Example:
##   nim r -d:release --path:src scripts/profile_ai.nim
##   TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_ai.nim

import std/[os, strutils, monotimes, times]
import environment
import agent_control
import types

proc parseEnvInt(name: string, fallback: int): int =
  let raw = getEnv(name, "")
  if raw.len == 0:
    return fallback
  try:
    parseInt(raw)
  except ValueError:
    fallback

proc countHouses(env: Environment): array[MapRoomObjectsTeams, int] =
  var counts: array[MapRoomObjectsTeams, int]
  for house in env.thingsByKind[House]:
    let teamId = house.teamId
    if teamId >= 0 and teamId < counts.len:
      inc counts[teamId]
  counts

proc updateMaxHearts(env: Environment, maxHearts: var array[MapRoomObjectsTeams, int]) =
  for altar in env.thingsByKind[Altar]:
    let teamId = altar.teamId
    if teamId >= 0 and teamId < maxHearts.len:
      if altar.hearts > maxHearts[teamId]:
        maxHearts[teamId] = altar.hearts

proc formatCounts(label: string, counts: array[MapRoomObjectsTeams, int]): string =
  var parts: seq[string] = @[]
  for teamId in 0 ..< counts.len:
    parts.add("t" & $teamId & "=" & $counts[teamId])
  label & " " & parts.join(" ")

proc msBetween(a, b: MonoTime): float64 =
  float64(inNanoseconds(b - a)) / 1_000_000.0

when isMainModule:
  let steps = max(1, parseEnvInt("TV_PROFILE_STEPS", 1000))
  let reportEvery = max(0, parseEnvInt("TV_PROFILE_REPORT_EVERY", 0))
  let seed = parseEnvInt("TV_PROFILE_SEED", 42)
  let warmupSteps = parseEnvInt("TV_PROFILE_WARMUP", 100)

  var env = newEnvironment()
  initGlobalController(BuiltinAI, seed)

  let baselineHouses = countHouses(env)
  var maxHouses = baselineHouses
  var maxHearts: array[MapRoomObjectsTeams, int]
  for teamId in 0 ..< maxHearts.len:
    maxHearts[teamId] = MapObjectAltarInitialHearts
  updateMaxHearts(env, maxHearts)

  # --- Warmup phase ---
  echo "Warming up for ", warmupSteps, " steps..."
  var actions: array[MapAgents, uint8]
  for step in 1 .. warmupSteps:
    actions = getActions(env)
    env.step(addr actions)

  # --- Profiling phase ---
  echo "Profiling for ", steps, " steps..."
  echo ""

  var totalAiMs = 0.0
  var totalStepMs = 0.0
  var totalMs = 0.0
  var maxAiMs = 0.0
  var maxStepMs = 0.0

  # Per-bucket stats: time 100-step windows
  let bucketSize = 100
  var bucketAiMs = 0.0
  var bucketStepMs = 0.0
  var bucketCount = 0

  let profileStart = getMonoTime()

  for step in 1 .. steps:
    let t0 = getMonoTime()
    actions = getActions(env)
    let t1 = getMonoTime()
    env.step(addr actions)
    let t2 = getMonoTime()

    let aiMs = msBetween(t0, t1)
    let stepMs = msBetween(t1, t2)

    totalAiMs += aiMs
    totalStepMs += stepMs
    if aiMs > maxAiMs: maxAiMs = aiMs
    if stepMs > maxStepMs: maxStepMs = stepMs

    bucketAiMs += aiMs
    bucketStepMs += stepMs
    inc bucketCount

    let currentHouses = countHouses(env)
    for teamId in 0 ..< maxHouses.len:
      if currentHouses[teamId] > maxHouses[teamId]:
        maxHouses[teamId] = currentHouses[teamId]
    updateMaxHearts(env, maxHearts)

    if bucketCount >= bucketSize:
      let avgAi = bucketAiMs / float64(bucketCount)
      let avgStep = bucketStepMs / float64(bucketCount)
      let stepsPerSec = 1000.0 / (avgAi + avgStep)
      echo "steps ", (step - bucketCount + 1 + warmupSteps), "-", (step + warmupSteps),
        ": ai=", formatFloat(avgAi, ffDecimal, 2), "ms",
        " sim=", formatFloat(avgStep, ffDecimal, 2), "ms",
        " total=", formatFloat(avgAi + avgStep, ffDecimal, 2), "ms",
        " (", formatFloat(stepsPerSec, ffDecimal, 1), " steps/s)"
      bucketAiMs = 0.0
      bucketStepMs = 0.0
      bucketCount = 0

    if reportEvery > 0 and step mod reportEvery == 0:
      echo "  step=", step + warmupSteps, " ", formatCounts("houses", currentHouses),
        " ", formatCounts("max_hearts", maxHearts)

  let profileEnd = getMonoTime()
  totalMs = msBetween(profileStart, profileEnd)

  echo ""
  echo "=== AI TICK PERFORMANCE PROFILE ==="
  echo "Steps profiled: ", steps, " (after ", warmupSteps, " warmup)"
  echo "Total wall time: ", formatFloat(totalMs / 1000.0, ffDecimal, 2), "s"
  echo ""
  echo "--- Per-step timing ---"
  echo "AI (getActions):  avg=", formatFloat(totalAiMs / float64(steps), ffDecimal, 3), "ms",
    "  max=", formatFloat(maxAiMs, ffDecimal, 3), "ms",
    "  total=", formatFloat(totalAiMs / 1000.0, ffDecimal, 2), "s",
    "  (", formatFloat(totalAiMs / totalMs * 100, ffDecimal, 1), "%)"
  echo "Sim (env.step):   avg=", formatFloat(totalStepMs / float64(steps), ffDecimal, 3), "ms",
    "  max=", formatFloat(maxStepMs, ffDecimal, 3), "ms",
    "  total=", formatFloat(totalStepMs / 1000.0, ffDecimal, 2), "s",
    "  (", formatFloat(totalStepMs / totalMs * 100, ffDecimal, 1), "%)"
  echo ""
  let avgTotal = (totalAiMs + totalStepMs) / float64(steps)
  echo "Steps/second: ", formatFloat(1000.0 / avgTotal, ffDecimal, 1)
  echo "Per-agent AI: ", formatFloat(totalAiMs / float64(steps) / float64(MapAgents) * 1000, ffDecimal, 2), "us"
  echo ""
  echo "--- Game state ---"
  echo "Agents: ", MapAgents, " (", MapAgentsPerTeam, " per team x ", MapRoomObjectsTeams, " teams + goblins)"
  echo formatCounts("baseline_houses", baselineHouses)
  echo formatCounts("max_houses", maxHouses)
  echo formatCounts("max_hearts", maxHearts)
  echo ""
  echo "--- Hotpath complexity (post-optimization) ---"
  echo "updateThreatMapFromVision: O(visionRange^2) grid scan per agent (was O(agents))"
  echo "findAttackOpportunity: O(8*maxRange) line scan per agent (was O(things))"
  echo "fighterFindNearbyEnemy: O(enemyRadius^2) grid scan (was O(agents))"
  echo "isThreateningAlly: O(AllyThreatRadius^2) grid scan (was O(agents))"
  echo "needsPopCapHouse: O(1) cached per-step pop count (was O(agents))"
  echo "findNearestFriendlyMonk: O(HealerSeekRadius^2) grid scan (was O(agents))"
  echo "--- Remaining O(n) hotpaths (candidates for future optimization) ---"
  echo "nearestFriendlyBuildingDistance: O(things) linear scan (not using spatial index)"
  echo "hasTeamLanternNear: O(things) linear scan per call"
  echo "optFighterLanterns: O(things) scan for unlit buildings"
  echo "revealTilesInRange: O(visionRadius^2) per agent per step"
