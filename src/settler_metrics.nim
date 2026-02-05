## settler_metrics.nim - Per-step metrics tracking for settler migration
##
## Gated behind -d:settlerMetrics compile flag. Zero-cost when disabled.
## Tracks settlement counts, villager distribution, and migration state.
##
## Metrics are updated each step (or every N steps) to provide a real-time
## view of settlement expansion and villager distribution.

when defined(settlerMetrics):
  import std/[strutils, tables, os]
  import types

  type
    SettlerSplitRecord* = object
      step*: int
      teamId*: int
      sourceAltar*: IVec2
      newAltar*: IVec2
      settlersCount*: int

    SettlerMetricsState* = object
      ## Per-team building counts
      townCenterCount*: array[MapRoomObjectsTeams, int]
      altarCount*: array[MapRoomObjectsTeams, int]
      ## Villagers per altar position
      villagersPerAltar*: Table[IVec2, int]
      ## Active settler migration groups
      activeSettlerGroups*: int
      ## Total splits completed per team
      settlerSplitsCompleted*: array[MapRoomObjectsTeams, int]
      ## History of completed splits
      splitHistory*: seq[SettlerSplitRecord]

  var settlerMetrics*: SettlerMetricsState
  var settlerMetricsInitialized = false
  var metricsUpdateInterval = 10  # Update every N steps

  proc initSettlerMetrics*() =
    settlerMetrics = SettlerMetricsState(
      villagersPerAltar: initTable[IVec2, int]()
    )
    let intervalEnv = getEnv("TV_SETTLER_METRICS_INTERVAL", "10")
    try:
      metricsUpdateInterval = parseInt(intervalEnv)
    except ValueError:
      metricsUpdateInterval = 10
    if metricsUpdateInterval < 1:
      metricsUpdateInterval = 1
    settlerMetricsInitialized = true

  proc ensureSettlerMetricsInit*() =
    if not settlerMetricsInitialized:
      initSettlerMetrics()

  proc updateSettlerMetrics*(env: Environment) =
    ## Recalculate settlement metrics from current game state.
    ## Call this every step or every N steps from the step loop.
    ensureSettlerMetricsInit()

    # Reset counters
    for i in 0 ..< MapRoomObjectsTeams:
      settlerMetrics.townCenterCount[i] = 0
      settlerMetrics.altarCount[i] = 0
    settlerMetrics.villagersPerAltar.clear()

    # Count town centers per team
    for thing in env.thingsByKind[TownCenter]:
      if not thing.isNil and thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
        inc settlerMetrics.townCenterCount[thing.teamId]

    # Count altars per team
    for thing in env.thingsByKind[Altar]:
      if not thing.isNil and thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
        inc settlerMetrics.altarCount[thing.teamId]

    # Count villagers per altar based on homeAltar assignments
    for agent in env.agents:
      if agent.isNil:
        continue
      if env.terminated[agent.agentId] != 0.0:
        continue
      if agent.homeAltar.x >= 0:
        settlerMetrics.villagersPerAltar.mgetOrPut(agent.homeAltar, 0) += 1

  proc shouldUpdateMetrics*(step: int): bool =
    ensureSettlerMetricsInit()
    step mod metricsUpdateInterval == 0

  proc recordSplit*(teamId: int, sourceAltar: IVec2, newAltar: IVec2,
                    settlersCount: int, step: int) =
    ## Record a completed settler split for history tracking.
    ensureSettlerMetricsInit()
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      inc settlerMetrics.settlerSplitsCompleted[teamId]
    settlerMetrics.splitHistory.add(SettlerSplitRecord(
      step: step,
      teamId: teamId,
      sourceAltar: sourceAltar,
      newAltar: newAltar,
      settlersCount: settlersCount
    ))

  proc printSettlementSummary*(env: Environment) =
    ## Dump current settlement state to stdout.
    ensureSettlerMetricsInit()

    echo "=== Settlement Summary (Step " & $env.currentStep & ") ==="

    # Per-team summary
    for teamId in 0 ..< MapRoomObjectsTeams:
      let altars = settlerMetrics.altarCount[teamId]
      let tcs = settlerMetrics.townCenterCount[teamId]
      if altars == 0 and tcs == 0:
        continue  # Skip eliminated teams

      # Count total villagers for this team
      var totalVillagers = 0
      for agent in env.agents:
        if agent.isNil:
          continue
        if env.terminated[agent.agentId] != 0.0:
          continue
        let agentTeam = agent.agentId div MapAgentsPerTeam
        if agentTeam == teamId:
          inc totalVillagers

      echo "  Team " & $teamId & ":"
      echo "    Altars: " & $altars & ", Town Centers: " & $tcs
      echo "    Total villagers alive: " & $totalVillagers
      echo "    Splits completed: " & $settlerMetrics.settlerSplitsCompleted[teamId]

      # Villagers per altar for this team
      for altarPos, count in settlerMetrics.villagersPerAltar:
        # Check if this altar belongs to this team
        let altarThing = env.grid[altarPos.x][altarPos.y]
        if not altarThing.isNil and altarThing.kind == Altar and
            altarThing.teamId == teamId:
          echo "      Altar (" & $altarPos.x & "," & $altarPos.y & "): " &
               $count & " villagers"

    # Active migrations
    echo "  Active settler groups: " & $settlerMetrics.activeSettlerGroups

    # Split history
    if settlerMetrics.splitHistory.len > 0:
      echo "  Split history:"
      for record in settlerMetrics.splitHistory:
        echo "    Step " & $record.step & ": Team " & $record.teamId &
             " split " & $record.settlersCount & " settlers from (" &
             $record.sourceAltar.x & "," & $record.sourceAltar.y & ") to (" &
             $record.newAltar.x & "," & $record.newAltar.y & ")"

    echo "========================================="
