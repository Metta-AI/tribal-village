## Log step-by-step state diffs for debugging.
##
## Gated behind `-d:stateDiff` and compiled out when disabled.

when defined(stateDiff):
  import
    std/strformat,
    items, types

  type
    TeamSnapshot* = object
      ## Snapshot of a single team's state.
      agentCount*: int
      aliveCount*: int
      deadCount*: int
      food*: int
      wood*: int
      gold*: int
      stone*: int
      water*: int
      villagerCount*: int
      archerCount*: int
      knightCount*: int
      manAtArmsCount*: int
      monkCount*: int

    StateSnapshot* = object
      ## Snapshot of key environment fields for comparison.
      step*: int
      victoryWinner*: int
      thingCount*: int
      agentCount*: int
      projectileCount*: int
      teams*: array[MapRoomObjectsTeams, TeamSnapshot]
      # Building counts.
      houseCount*: int
      altarCount*: int
      towerCount*: int
      wallCount*: int
      marketCount*: int
      castleCount*: int

    StateDiffState* = object
      ## Cached state used by the diff logger.
      prevSnapshot*: StateSnapshot
      hasSnapshot*: bool

  var
    diffState*: StateDiffState
    diffInitialized* = false

  proc initStateDiff*() =
    ## Initialize the state-diff logger.
    diffState = StateDiffState(hasSnapshot: false)
    diffInitialized = true

  proc ensureStateDiffInit*() =
    ## Initialize state-diff tracking on first use.
    if not diffInitialized:
      initStateDiff()

  proc captureSnapshot*(env: Environment): StateSnapshot =
    ## Capture current environment state into a snapshot.
    result.step = env.currentStep
    result.victoryWinner = env.victoryWinner
    result.thingCount = env.things.len
    result.agentCount = env.agents.len
    result.projectileCount = env.projectiles.len

    # Count buildings by type.
    for thing in env.things:
      if thing.isNil:
        continue
      case thing.kind
      of House: inc result.houseCount
      of Altar: inc result.altarCount
      of GuardTower, Outpost: inc result.towerCount
      of Wall: inc result.wallCount
      of Market: inc result.marketCount
      of Castle: inc result.castleCount
      else: discard

    # Team snapshots.
    for teamId in 0 ..< MapRoomObjectsTeams:
      var ts: TeamSnapshot
      # Stockpile resources.
      ts.food = env.teamStockpiles[teamId].counts[ResourceFood]
      ts.wood = env.teamStockpiles[teamId].counts[ResourceWood]
      ts.gold = env.teamStockpiles[teamId].counts[ResourceGold]
      ts.stone = env.teamStockpiles[teamId].counts[ResourceStone]
      ts.water = env.teamStockpiles[teamId].counts[ResourceWater]

      result.teams[teamId] = ts

    # Agent counts by team and class.
    for agent in env.liveAgents:
      let teamId = agent.getTeamId()
      if teamId < 0 or teamId >= MapRoomObjectsTeams:
        continue
      inc result.teams[teamId].agentCount
      if env.terminated[agent.agentId] == 0.0:
        inc result.teams[teamId].aliveCount
        case agent.unitClass
        of UnitVillager: inc result.teams[teamId].villagerCount
        of UnitArcher: inc result.teams[teamId].archerCount
        of UnitKnight: inc result.teams[teamId].knightCount
        of UnitManAtArms: inc result.teams[teamId].manAtArmsCount
        of UnitMonk: inc result.teams[teamId].monkCount
        else: discard
      else:
        inc result.teams[teamId].deadCount

  proc teamChanged(oldTeam, newTeam: TeamSnapshot): bool =
    ## Return true when any tracked team field changed.
    oldTeam.aliveCount != newTeam.aliveCount or
      oldTeam.deadCount != newTeam.deadCount or
      oldTeam.food != newTeam.food or
      oldTeam.wood != newTeam.wood or
      oldTeam.gold != newTeam.gold or
      oldTeam.stone != newTeam.stone or
      oldTeam.water != newTeam.water or
      oldTeam.villagerCount != newTeam.villagerCount or
      oldTeam.archerCount != newTeam.archerCount or
      oldTeam.knightCount != newTeam.knightCount or
      oldTeam.manAtArmsCount != newTeam.manAtArmsCount or
      oldTeam.monkCount != newTeam.monkCount

  proc snapshotChanged(oldSnap, newSnap: StateSnapshot): bool =
    ## Return true when any tracked snapshot field changed.
    if oldSnap.victoryWinner != newSnap.victoryWinner or
        oldSnap.thingCount != newSnap.thingCount or
        oldSnap.projectileCount != newSnap.projectileCount or
        oldSnap.houseCount != newSnap.houseCount or
        oldSnap.altarCount != newSnap.altarCount or
        oldSnap.towerCount != newSnap.towerCount or
        oldSnap.wallCount != newSnap.wallCount or
        oldSnap.marketCount != newSnap.marketCount or
        oldSnap.castleCount != newSnap.castleCount:
      return true
    for teamId in 0 ..< MapRoomObjectsTeams:
      if teamChanged(oldSnap.teams[teamId], newSnap.teams[teamId]):
        return true
    false

  proc logDiff(name: string, oldVal, newVal: int) =
    ## Log a single field diff.
    if oldVal != newVal:
      let delta = newVal - oldVal
      let sign = if delta > 0: "+" else: ""
      echo &"  {name}: {oldVal} -> {newVal} ({sign}{delta})"

  proc logTeamDiff(teamId: int, oldTeam, newTeam: TeamSnapshot) =
    ## Log diffs for one team snapshot.
    if not teamChanged(oldTeam, newTeam):
      return

    echo &"  Team {teamId}:"
    logDiff("    alive", oldTeam.aliveCount, newTeam.aliveCount)
    logDiff("    dead", oldTeam.deadCount, newTeam.deadCount)
    logDiff("    villagers", oldTeam.villagerCount, newTeam.villagerCount)
    logDiff("    archers", oldTeam.archerCount, newTeam.archerCount)
    logDiff("    knights", oldTeam.knightCount, newTeam.knightCount)
    logDiff("    manAtArms", oldTeam.manAtArmsCount, newTeam.manAtArmsCount)
    logDiff("    monks", oldTeam.monkCount, newTeam.monkCount)
    logDiff("    food", oldTeam.food, newTeam.food)
    logDiff("    wood", oldTeam.wood, newTeam.wood)
    logDiff("    gold", oldTeam.gold, newTeam.gold)
    logDiff("    stone", oldTeam.stone, newTeam.stone)
    logDiff("    water", oldTeam.water, newTeam.water)

  proc compareAndLog*(oldSnap, newSnap: StateSnapshot) =
    ## Compare two snapshots and log all differences.
    if not snapshotChanged(oldSnap, newSnap):
      return

    echo &"[StateDiff] Step {oldSnap.step} -> {newSnap.step}:"
    logDiff("  victoryWinner", oldSnap.victoryWinner, newSnap.victoryWinner)
    logDiff("  things", oldSnap.thingCount, newSnap.thingCount)
    logDiff("  projectiles", oldSnap.projectileCount, newSnap.projectileCount)
    logDiff("  houses", oldSnap.houseCount, newSnap.houseCount)
    logDiff("  altars", oldSnap.altarCount, newSnap.altarCount)
    logDiff("  towers", oldSnap.towerCount, newSnap.towerCount)
    logDiff("  walls", oldSnap.wallCount, newSnap.wallCount)
    logDiff("  markets", oldSnap.marketCount, newSnap.marketCount)
    logDiff("  castles", oldSnap.castleCount, newSnap.castleCount)

    for teamId in 0 ..< MapRoomObjectsTeams:
      logTeamDiff(teamId, oldSnap.teams[teamId], newSnap.teams[teamId])

  proc capturePreStep*(env: Environment) =
    ## Call before step() to capture pre-step state.
    ensureStateDiffInit()
    diffState.prevSnapshot = captureSnapshot(env)
    diffState.hasSnapshot = true

  proc comparePostStep*(env: Environment) =
    ## Call after step() to compare and log diffs.
    ensureStateDiffInit()
    if not diffState.hasSnapshot:
      return
    let newSnap = captureSnapshot(env)
    compareAndLog(diffState.prevSnapshot, newSnap)
    diffState.prevSnapshot = newSnap

when not defined(stateDiff):
  ## Ignore state-diff initialization when the feature is disabled.
  template ensureStateDiffInit*() =
    discard

  ## Ignore pre-step capture when the feature is disabled.
  template capturePreStep*(env: untyped) =
    discard

  ## Ignore post-step comparison when the feature is disabled.
  template comparePostStep*(env: untyped) =
    discard
