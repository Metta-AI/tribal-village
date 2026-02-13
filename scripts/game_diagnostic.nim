## game_diagnostic.nim - Comprehensive game state diagnostic
## Tracks: population, grid objects by kind, deaths, births, SPS per window
##
## Usage:
##   nim c -r -d:release --path:src scripts/game_diagnostic.nim

import std/[os, strutils, strformat, monotimes, tables, algorithm]
import environment
import agent_control
import types

proc main() =
  let totalSteps = parseInt(getEnv("TV_SPS_STEPS", "3000"))
  let window = parseInt(getEnv("TV_SPS_WINDOW", "100"))
  let seed = parseInt(getEnv("TV_SPS_SEED", "42"))

  echo "=== Game Diagnostic: Population, Objects, Deaths, SPS ==="
  echo &"  Total steps: {totalSteps}, Window: {window}, Seed: {seed}"
  echo ""

  initGlobalController(BuiltinAI, seed = seed)
  var env = newEnvironment()

  # Track deaths per window
  var prevAlive: array[MapAgents, bool]
  var prevTerminated: array[MapAgents, float32]
  for id in 0 ..< MapAgents:
    prevAlive[id] = env.terminated[id] == 0.0
    prevTerminated[id] = env.terminated[id]

  # Track previous grid state for births
  var prevAgentCount = 0
  for id in 0 ..< MapAgents:
    if env.terminated[id] == 0.0:
      inc prevAgentCount

  var windowStart = getMonoTime()
  let overallStart = getMonoTime()

  echo "=== Per-Window Report ==="
  echo ""

  for i in 0 ..< totalSteps:
    var actions = getActions(env)
    env.step(addr actions)

    if (i + 1) mod window == 0:
      let now = getMonoTime()
      let windowMs = (now.ticks - windowStart.ticks).float64 / 1_000_000.0
      let windowSps = float64(window) / (windowMs / 1000.0)

      # Count alive agents and track births/deaths
      var aliveCount = 0
      var deathsThisWindow = 0
      var birthsThisWindow = 0
      for id in 0 ..< MapAgents:
        let alive = env.terminated[id] == 0.0
        if alive:
          inc aliveCount
        # Death: was alive, now terminated
        if prevAlive[id] and not alive:
          inc deathsThisWindow
        # Birth: was terminated, now alive (respawn/training)
        if not prevAlive[id] and alive:
          inc birthsThisWindow
        prevAlive[id] = alive

      # Count grid objects by category
      var buildingCount = 0
      var resourceCount = 0
      var decorCount = 0
      var wallCount = 0
      var otherFgCount = 0
      var bgCount = 0

      # Detailed building breakdown
      var buildingCounts: CountTable[string]
      var resourceCounts: CountTable[string]

      for x in 0 ..< MapWidth:
        for y in 0 ..< MapHeight:
          let t = env.grid[x][y]
          if t != nil:
            let k = t.kind
            case k
            of Wall: inc wallCount
            of Tree, Bush, Cactus, Stalagmite, Stump:
              inc resourceCount
              resourceCounts.inc($k)
            of Stone, Gold, Magma, Wheat, Fish:
              inc resourceCount
              resourceCounts.inc($k)
            of Cow, Bear, Wolf:
              inc resourceCount
              resourceCounts.inc($k)
            of Corpse, Skeleton:
              inc decorCount
            of TownCenter, House, Barracks, ArcheryRange, Stable, SiegeWorkshop,
               MangonelWorkshop, TrebuchetWorkshop, Blacksmith, Market, Dock,
               Monastery, Temple, University, Castle, Wonder,
               ClayOven, WeavingLoom, Outpost, GuardTower, Mill, Granary,
               LumberCamp, Quarry, MiningCamp, Lantern:
              inc buildingCount
              buildingCounts.inc($k)
            of Altar, Spawner, Tumor, GoblinHive, GoblinHut, GoblinTotem,
               ControlPoint, Barrel, Relic:
              inc otherFgCount
            of Door, Stubble:
              discard  # background grid
            of CliffEdgeN, CliffEdgeE, CliffEdgeS, CliffEdgeW,
               CliffCornerInNE, CliffCornerInSE, CliffCornerInSW, CliffCornerInNW,
               CliffCornerOutNE, CliffCornerOutSE, CliffCornerOutSW, CliffCornerOutNW:
              inc decorCount
            of Agent:
              discard  # agents tracked separately

          # Background grid
          let bg = env.backgroundGrid[x][y]
          if bg != nil:
            inc bgCount

      let totalFg = wallCount + resourceCount + buildingCount + decorCount + otherFgCount

      echo &"--- Step {i+1} (SPS: {windowSps:.0f}, ms/step: {windowMs/float64(window):.2f}) ---"
      echo &"  Agents: {aliveCount} alive  (+{birthsThisWindow} born, -{deathsThisWindow} died)"
      echo &"  Grid FG: {totalFg} total = {wallCount} walls + {resourceCount} resources + {buildingCount} buildings + {decorCount} decor + {otherFgCount} other"
      echo &"  Grid BG: {bgCount}"

      if buildingCount > 0:
        var bPairs: seq[(int, string)]
        for k, v in buildingCounts:
          bPairs.add((v, k))
        bPairs.sort(proc(a, b: (int, string)): int = cmp(b[0], a[0]))
        var topBuildings: seq[string]
        for j in 0 ..< min(8, bPairs.len):
          topBuildings.add(&"{bPairs[j][1]}:{bPairs[j][0]}")
        echo &"  Buildings: {topBuildings.join(\", \")}"

      if deathsThisWindow > 0 or birthsThisWindow > 0:
        echo &"  Population delta: {birthsThisWindow - deathsThisWindow:+d}"

      echo ""
      windowStart = now

  let overallEnd = getMonoTime()
  let totalMs = (overallEnd.ticks - overallStart.ticks).float64 / 1_000_000.0

  echo "=== Final Summary ==="
  echo &"Overall: {float64(totalSteps) / (totalMs / 1000.0):.1f} SPS, {totalMs/1000.0:.2f}s total"

  # Final population census
  var finalAlive = 0
  var totalDeaths = 0
  for id in 0 ..< MapAgents:
    if env.terminated[id] == 0.0:
      inc finalAlive
    else:
      inc totalDeaths
  echo &"Final agents: {finalAlive} alive, {totalDeaths} total terminated"

main()
