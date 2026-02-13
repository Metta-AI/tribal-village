## sps_over_time.nim - Measure SPS degradation across a long episode
##
## Usage:
##   nim c -r -d:release --path:src scripts/sps_over_time.nim
##
## Environment variables:
##   TV_SPS_STEPS   - Total steps to run (default: 3000)
##   TV_SPS_WINDOW  - Steps per measurement window (default: 100)
##   TV_SPS_SEED    - Random seed (default: 42)

import std/[os, strutils, strformat, monotimes]
import environment
import agent_control

proc main() =
  let totalSteps = parseInt(getEnv("TV_SPS_STEPS", "3000"))
  let window = parseInt(getEnv("TV_SPS_WINDOW", "100"))
  let seed = parseInt(getEnv("TV_SPS_SEED", "42"))

  echo "=== SPS Over Time: Degradation Check ==="
  echo &"  Total steps: {totalSteps}"
  echo &"  Window size: {window}"
  echo &"  Seed:        {seed}"
  echo ""

  initGlobalController(BuiltinAI, seed = seed)
  var env = newEnvironment()

  echo "    Step       SPS   ms/step  Agents  GridObjs"
  echo "-".repeat(55)

  var windowStart = getMonoTime()
  let overallStart = getMonoTime()

  for i in 0 ..< totalSteps:
    var actions = getActions(env)
    env.step(addr actions)

    if (i + 1) mod window == 0:
      let now = getMonoTime()
      let windowMs = (now.ticks - windowStart.ticks).float64 / 1_000_000.0
      let windowSps = float64(window) / (windowMs / 1000.0)
      let msPerStep = windowMs / float64(window)

      # Count alive agents
      var aliveCount = 0
      for id in 0 ..< MapAgents:
        if env.terminated[id] == 0.0:
          inc aliveCount

      # Count non-nil grid objects
      var gridObjCount = 0
      for x in 0 ..< MapWidth:
        for y in 0 ..< MapHeight:
          if env.grid[x][y] != nil:
            inc gridObjCount

      echo &"{i+1:>8}  {windowSps:>8.1f}  {msPerStep:>8.3f}  {aliveCount:>6}  {gridObjCount:>8}"

      windowStart = now

  let overallEnd = getMonoTime()
  let totalMs = (overallEnd.ticks - overallStart.ticks).float64 / 1_000_000.0
  let totalSps = float64(totalSteps) / (totalMs / 1000.0)

  echo "-".repeat(55)
  echo &"Overall: {totalSps:.1f} SPS over {totalSteps} steps ({totalMs/1000.0:.2f}s)"

main()
