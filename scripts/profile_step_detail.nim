## Detailed step profiler for nimprof analysis
## Build with: nim r --profiler:on --stackTrace:on -d:release --path:src scripts/profile_step_detail.nim
## Or without nimprof for timing only:
##   nim r -d:release --path:src scripts/profile_step_detail.nim

import nimprof
import std/[random, monotimes, times, os, strutils]
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

proc msBetween(a, b: MonoTime): float64 =
  (b.ticks - a.ticks).float64 / 1_000_000.0

when isMainModule:
  let steps = max(1, parseEnvInt("TV_PROFILE_STEPS", 2000))
  let warmupSteps = parseEnvInt("TV_PROFILE_WARMUP", 200)
  let seed = parseEnvInt("TV_PROFILE_SEED", 42)

  echo "=== Step Hotpath Profiler ==="
  echo "Steps: ", steps, " (warmup: ", warmupSteps, ")"
  echo ""

  var env = newEnvironment()
  initGlobalController(BuiltinAI, seed)

  # Warmup phase
  echo "Warming up..."
  var actions: array[MapAgents, uint8]
  for _ in 1 .. warmupSteps:
    actions = getActions(env)
    env.step(addr actions)

  # Profile phase
  echo "Profiling ", steps, " steps..."
  let t0 = getMonoTime()
  for _ in 1 .. steps:
    actions = getActions(env)
    env.step(addr actions)
  let t1 = getMonoTime()

  let totalMs = msBetween(t0, t1)
  let avgMs = totalMs / steps.float64
  let stepsPerSec = 1000.0 / avgMs

  echo ""
  echo "=== Results ==="
  echo "Total time: ", formatFloat(totalMs / 1000.0, ffDecimal, 2), "s"
  echo "Average per step: ", formatFloat(avgMs, ffDecimal, 3), "ms"
  echo "Steps/second: ", formatFloat(stepsPerSec, ffDecimal, 1)
  echo "Agents: ", MapAgents
  echo ""
  echo "Profile written to profile_results.txt"
