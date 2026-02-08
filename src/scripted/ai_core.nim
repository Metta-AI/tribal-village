## Core AI system module - imported by agent_control.nim via ai_defaults.
## Provides foundational AI types, pathfinding, and utility functions.
import std/[tables, sets]
import ../entropy
import vmath
import ../environment, ../common_types, ../terrain
import ai_types
import coordination

# Re-export modules so downstream importers get full environment/AI type access
export ai_types, environment, common_types, terrain, coordination, entropy

const
  CacheMaxAge* = 20  # Invalidate cached positions after this many steps
  ThreatMapStaggerInterval* = 5  # Only 1/5 of agents update threat map per step
  DefensiveRetaliationWindow* = 30  ## Steps after being attacked that defensive stance allows retaliation

proc stanceAllowsAutoAttack*(env: Environment, agent: Thing): bool =
  ## Returns true if the agent's stance allows auto-attacking enemies.
  ## - Aggressive: always auto-attack
  ## - Defensive: only auto-attack if recently attacked (retaliation)
  ## - StandGround: auto-attack enemies in range
  ## - NoAttack: never auto-attack
  case agent.stance
  of StanceAggressive, StanceStandGround: true
  of StanceDefensive:
    # Defensive stance: only attack if attacked within the retaliation window
    agent.lastAttackedStep > 0 and
      (env.currentStep - agent.lastAttackedStep) <= DefensiveRetaliationWindow
  of StanceNoAttack: false

proc hasHarvestableResource*(thing: Thing): bool =
  ## Check if a resource thing still has harvestable inventory.
  ## Returns false if the thing has been depleted (0 inventory remaining).
  if thing.isNil:
    return false
  case thing.kind
  of Stump, Stubble:
    let key = if thing.kind == Stubble: ItemWheat else: ItemWood
    return getInv(thing, key) > 0
  of Stone, Stalagmite:
    return getInv(thing, ItemStone) > 0
  of Gold:
    return getInv(thing, ItemGold) > 0
  of Bush, Cactus:
    return getInv(thing, ItemPlant) > 0
  of Fish:
    return getInv(thing, ItemFish) > 0
  of Wheat:
    return getInv(thing, ItemWheat) > 0
  of Corpse:
    for key, count in thing.inventory.pairs:
      if count > 0:
        return true
    return false
  of Tree:
    # Trees use harvestTree which has its own checks; consider alive trees harvestable
    return true
  of Cow:
    return true  # Cows are always interactable (milk or kill)
  else:
    return true  # Non-resource things (buildings etc.) are always valid

const
  Directions8* = [
    ivec2(0, -1),  # 0: North
    ivec2(0, 1),   # 1: South
    ivec2(-1, 0),  # 2: West
    ivec2(1, 0),   # 3: East
    ivec2(-1, -1), # 4: NW
    ivec2(1, -1),  # 5: NE
    ivec2(-1, 1),  # 6: SW
    ivec2(1, 1)    # 7: SE
  ]

  SearchRadius* = 50
  SpiralAdvanceSteps = 3

# ---------------------------------------------------------------------------
# Generic per-agent per-step cache infrastructure
# Consolidates repeated cache boilerplate pattern used in fighter.nim
# ---------------------------------------------------------------------------

type
  PerAgentCache*[T] = object
    ## Generic per-agent cache with per-step invalidation.
    ## Used to avoid redundant spatial lookups when canStart/shouldTerminate/act
    ## all call the same expensive function for the same agent in the same step.
    cacheStep*: int
    cache*: array[MapAgents, T]
    valid*: array[MapAgents, bool]

proc invalidateIfStale*[T](cache: var PerAgentCache[T], currentStep: int) {.inline.} =
  ## Invalidate the cache if the step has changed.
  if cache.cacheStep != currentStep:
    cache.cacheStep = currentStep
    for i in 0 ..< MapAgents:
      cache.valid[i] = false

proc get*[T](cache: var PerAgentCache[T], env: Environment, agentId: int,
             compute: proc(env: Environment, agentId: int): T): T =
  ## Get cached value or compute and cache if not valid.
  ## The compute proc takes env and agentId and returns the result.
  cache.invalidateIfStale(env.currentStep)
  if agentId >= 0 and agentId < MapAgents:
    if not cache.valid[agentId]:
      cache.cache[agentId] = compute(env, agentId)
      cache.valid[agentId] = true
    return cache.cache[agentId]
  # Fallback: compute without caching for invalid agentId
  compute(env, agentId)

proc getWithAgent*[T](cache: var PerAgentCache[T], env: Environment, agent: Thing,
                       compute: proc(env: Environment, agent: Thing): T): T =
  ## Get cached value or compute and cache if not valid.
  ## The compute proc takes env and agent Thing and returns the result.
  cache.invalidateIfStale(env.currentStep)
  let aid = agent.agentId
  if aid >= 0 and aid < MapAgents:
    if not cache.valid[aid]:
      cache.cache[aid] = compute(env, agent)
      cache.valid[aid] = true
    return cache.cache[aid]
  # Fallback: compute without caching for invalid agentId
  compute(env, agent)

proc getDifficulty*(controller: Controller, teamId: int): DifficultyConfig =
  ## Get the difficulty configuration for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    return controller.difficulty[teamId]
  return defaultDifficultyConfig(DiffNormal)

proc setDifficulty*(controller: Controller, teamId: int, level: DifficultyLevel) =
  ## Set the difficulty level for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId] = defaultDifficultyConfig(level)

proc setDifficultyConfig*(controller: Controller, teamId: int, config: DifficultyConfig) =
  ## Set a custom difficulty configuration for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId] = config

proc enableAdaptiveDifficulty*(controller: Controller, teamId: int, targetTerritory: float32 = 0.5) =
  ## Enable adaptive difficulty for a team. The AI will adjust its difficulty
  ## based on territory control compared to the target percentage.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId].adaptive = true
    controller.difficulty[teamId].adaptiveTarget = targetTerritory

proc disableAdaptiveDifficulty*(controller: Controller, teamId: int) =
  ## Disable adaptive difficulty for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId].adaptive = false

proc shouldApplyDecisionDelay*(controller: Controller, teamId: int): bool =
  ## Check if the AI should apply a decision delay (return NOOP) based on difficulty.
  ## Returns true with probability equal to decisionDelayChance.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  let chance = controller.difficulty[teamId].decisionDelayChance
  if chance <= 0.0:
    return false
  randChance(controller.rng, chance)

const
  AdaptiveCheckInterval* = 500  # Check every 500 steps

proc updateAdaptiveDifficulty*(controller: Controller, env: Environment) =
  ## Update difficulty levels for teams with adaptive mode enabled.
  ## Adjusts difficulty up if team is doing too well, down if struggling.
  let currentStep = env.currentStep.int32
  let score = env.scoreTerritory()
  let totalTiles = max(1, score.scoredTiles)
  const Threshold = 0.15

  for teamId in 0 ..< MapRoomObjectsTeams:
    if not controller.difficulty[teamId].adaptive:
      continue
    if currentStep - controller.difficulty[teamId].lastAdaptiveCheck < AdaptiveCheckInterval:
      continue

    controller.difficulty[teamId].lastAdaptiveCheck = currentStep
    let territoryRatio = float32(score.teamTiles[teamId]) / float32(totalTiles)
    let target = controller.difficulty[teamId].adaptiveTarget
    let currentLevel = controller.difficulty[teamId].level

    template applyDifficultyLevel(newLevel: DifficultyLevel) =
      if newLevel != currentLevel:
        let savedAdaptive = controller.difficulty[teamId].adaptive
        let savedTarget = controller.difficulty[teamId].adaptiveTarget
        controller.difficulty[teamId] = defaultDifficultyConfig(newLevel)
        controller.difficulty[teamId].adaptive = savedAdaptive
        controller.difficulty[teamId].adaptiveTarget = savedTarget
        controller.difficulty[teamId].lastAdaptiveCheck = currentStep

    if territoryRatio > target + Threshold:
      applyDifficultyLevel(case currentLevel
        of DiffEasy: DiffNormal
        of DiffNormal: DiffHard
        of DiffHard, DiffBrutal: DiffBrutal)
    elif territoryRatio < target - Threshold:
      applyDifficultyLevel(case currentLevel
        of DiffEasy, DiffNormal: DiffEasy
        of DiffHard: DiffNormal
        of DiffBrutal: DiffHard)

proc getAgentRole*(controller: Controller, agentId: int): AgentRole =
  ## Get the role of an agent (for profiling)
  if agentId >= 0 and agentId < MapAgents and controller.agentsInitialized[agentId]:
    return controller.agents[agentId].role
  return Gatherer  # Default

proc isAgentInitialized*(controller: Controller, agentId: int): bool =
  ## Check if an agent has been initialized (for profiling)
  if agentId >= 0 and agentId < MapAgents:
    return controller.agentsInitialized[agentId]
  return false

# Helper proc to save state and return action
proc saveStateAndReturn*(controller: Controller, agentId: int, state: AgentState, action: uint8): uint8 =
  var nextState = state
  nextState.lastActionVerb = action.int div ActionArgumentCount
  nextState.lastActionArg = action.int mod ActionArgumentCount
  controller.agents[agentId] = nextState
  controller.agentsInitialized[agentId] = true
  return action

proc vecToOrientation*(vec: IVec2): int =
  ## Map a step vector to orientation index (0..7)
  # Lookup: index = (signi(x)+1)*3 + (signi(y)+1), mapped to direction
  const orientationTable = [
    # (x=-1,y=-1)=NW, (x=-1,y=0)=W, (x=-1,y=1)=SW
    # (x=0,y=-1)=N,   (x=0,y=0)=0,  (x=0,y=1)=S
    # (x=1,y=-1)=NE,  (x=1,y=0)=E,  (x=1,y=1)=SE
    4, 2, 6,  # x=-1: NW, W, SW
    0, 0, 1,  # x=0:  N, (origin), S
    5, 3, 7   # x=1:  NE, E, SE
  ]
  let ix = (if vec.x < 0: 0 elif vec.x > 0: 2 else: 1)
  let iy = (if vec.y < 0: 0 elif vec.y > 0: 2 else: 1)
  orientationTable[ix * 3 + iy]

proc signi*(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

# chebyshevDist is provided by environment (via step.nim template)

# Fog of War / Revealed Map Functions

proc revealTilesInRange*(env: Environment, teamId: int, center: IVec2, radius: int) =
  ## Mark tiles within radius of center as revealed for the specified team.
  ## Uses Chebyshev distance (square vision area) matching the game's standard.
  ## Optimized: skips tiles already revealed to reduce write operations.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  # Pre-compute bounds for the reveal area (clamped to map)
  let minX = max(0, center.x.int - radius)
  let maxX = min(MapWidth - 1, center.x.int + radius)
  let minY = max(0, center.y.int - radius)
  let maxY = min(MapHeight - 1, center.y.int + radius)
  # Skip if center already revealed and we're likely to have revealed the surrounding area
  # This optimization helps when agents are stationary
  if env.revealedMaps[teamId][center.x][center.y]:
    # Sample a few corner tiles to check if area is likely already revealed
    let cornerRevealed = env.revealedMaps[teamId][minX][minY] and
                         env.revealedMaps[teamId][maxX][maxY] and
                         env.revealedMaps[teamId][minX][maxY] and
                         env.revealedMaps[teamId][maxX][minY]
    if cornerRevealed:
      return  # Area already fully revealed, skip iteration
  # Iterate and reveal, skipping already-revealed tiles
  for x in minX .. maxX:
    for y in minY .. maxY:
      if not env.revealedMaps[teamId][x][y]:
        env.revealedMaps[teamId][x][y] = true

proc isRevealed*(env: Environment, teamId: int, pos: IVec2): bool =
  ## Check if a tile has been revealed (explored) by the specified team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if not isValidPos(pos):
    return false
  env.revealedMaps[teamId][pos.x][pos.y]

proc clearRevealedMap*(env: Environment, teamId: int) =
  ## Clear the revealed map for a team (e.g., at episode reset).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.revealedMaps[teamId][x][y] = false

proc updateRevealedMapFromVision*(env: Environment, agent: Thing) =
  ## Update the revealed map based on agent's current vision.
  ## Scouts have extended vision range for exploration.
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  # Scouts have extended line of sight for exploration
  let visionRadius = if agent.unitClass == UnitScout:
    ScoutVisionRange.int
  else:
    ThreatVisionRange.int

  env.revealTilesInRange(teamId, agent.pos, visionRadius)

proc getRevealedTileCount*(env: Environment, teamId: int): int =
  ## Count how many tiles have been revealed by a team (exploration progress).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  result = 0
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.revealedMaps[teamId][x][y]:
        inc result

# Shared Threat Map Functions

proc decayThreats*(controller: Controller, teamId: int, currentStep: int32) =
  ## Remove threats that haven't been seen recently
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var map = addr controller.threatMaps[teamId]
  var writeIdx = 0
  for readIdx in 0 ..< map.count:
    let age = currentStep - map.entries[readIdx].lastSeen
    if age < ThreatDecaySteps:
      if writeIdx != readIdx:
        map.entries[writeIdx] = map.entries[readIdx]
      inc writeIdx
  map.count = writeIdx.int32
  map.lastUpdateStep = currentStep

proc reportThreat*(controller: Controller, teamId: int, pos: IVec2,
                   strength: int32, currentStep: int32,
                   agentId: int32 = -1, isStructure: bool = false) =
  ## Report a threat position to the team's shared threat map.
  ## Called by any agent that spots an enemy.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var map = addr controller.threatMaps[teamId]

  # Check if threat already exists at this position or for this agent
  for i in 0 ..< map.count:
    let entry = addr map.entries[i]
    # Update existing entry if same position or same enemy agent
    if (entry.pos == pos) or (agentId >= 0 and entry.agentId == agentId):
      entry.pos = pos
      entry.strength = max(entry.strength, strength)
      entry.lastSeen = currentStep
      entry.agentId = agentId
      entry.isStructure = isStructure
      return

  # Add new threat if space available
  if map.count < MaxThreatEntries:
    map.entries[map.count] = ThreatEntry(
      pos: pos,
      strength: strength,
      lastSeen: currentStep,
      agentId: agentId,
      isStructure: isStructure
    )
    inc map.count

proc getNearestThreat*(controller: Controller, teamId: int, pos: IVec2,
                       currentStep: int32): tuple[pos: IVec2, dist: int32, found: bool] =
  ## Get the nearest known threat to a position.
  ## Returns the threat position and distance, or found=false if none.
  result = (pos: ivec2(-1, -1), dist: int32.high, found: false)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue  # Skip stale threats
    let dist = chebyshevDist(pos, entry.pos)
    if dist < result.dist:
      result = (pos: entry.pos, dist: dist, found: true)

proc getThreatsInRange*(controller: Controller, teamId: int, pos: IVec2,
                        rangeVal: int32, currentStep: int32): seq[ThreatEntry] =
  ## Get all known threats within range of a position.
  result = @[]
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue  # Skip stale threats
    let dist = chebyshevDist(pos, entry.pos)
    if dist <= rangeVal:
      result.add entry

proc getTotalThreatStrength*(controller: Controller, teamId: int, pos: IVec2,
                              rangeVal: int32, currentStep: int32): int32 =
  ## Get the total threat strength within range of a position.
  result = 0
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue
    let dist = chebyshevDist(pos, entry.pos)
    if dist <= rangeVal:
      result += entry.strength

proc hasKnownThreats*(controller: Controller, teamId: int, currentStep: int32): bool =
  ## Check if team has any known (non-stale) threats
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let age = currentStep - map.entries[i].lastSeen
    if age < ThreatDecaySteps:
      return true
  false

proc clearThreatMap*(controller: Controller, teamId: int) =
  ## Clear all threats for a team (e.g., at episode reset)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  controller.threatMaps[teamId].count = 0
  controller.threatMaps[teamId].lastUpdateStep = 0

proc updateThreatMapFromVision*(controller: Controller, env: Environment,
                                 agent: Thing, currentStep: int32) =
  ## Scan agent's vision range and report any enemies to the team threat map.
  ## Also updates the team's revealed map (fog of war).
  ## Called each tick for each agent to share threat intelligence.
  ## Scouts have extended line of sight (AoE2-style).
  ##
  ## Optimized: scans grid tiles within vision radius instead of all agents,
  ## and uses spatial index for building detection.
  ## Additional optimization: skips fog updates if agent hasn't moved since last reveal.
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  # Scouts have extended vision range for both threat detection and exploration
  let visionRange = if agent.unitClass == UnitScout:
    ScoutVisionRange
  else:
    ThreatVisionRange

  # Update fog of war - reveal tiles in vision range
  # Optimization: Skip if agent hasn't moved since last fog update
  let agentId = agent.agentId
  if agentId >= 0 and agentId < MapAgents:
    let lastPos = controller.fogLastRevealPos[agentId]
    let lastStep = controller.fogLastRevealStep[agentId]
    # Only update fog if agent moved or this is first update for this agent
    if lastPos != agent.pos or lastStep <= 0:
      env.updateRevealedMapFromVision(agent)
      controller.fogLastRevealPos[agentId] = agent.pos
      controller.fogLastRevealStep[agentId] = currentStep
  else:
    # Fallback for invalid agent IDs - always update
    env.updateRevealedMapFromVision(agent)

  # Scan for enemy agents within vision range using spatial index
  # Scan spatial cells for enemy agents and structures
  let (cx, cy) = cellCoords(agent.pos)
  let vr = visionRange.int
  let cellRadius = distToCellRadius16(min(vr, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize))
  for ddx in -cellRadius .. cellRadius:
    for ddy in -cellRadius .. cellRadius:
      let nx = cx + ddx
      let ny = cy + ddy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue
      # Enemy agents
      for other in env.spatialIndex.kindCells[Agent][nx][ny]:
        if other.isNil or not isAgentAlive(env, other):
          continue
        let otherTeam = getTeamId(other)
        if otherTeam == teamId or otherTeam < 0:
          continue
        if chebyshevDist(agent.pos, other.pos) <= visionRange:
          let strength: int32 = case other.unitClass
            of UnitKnight: 3
            of UnitManAtArms, UnitArcher: 2
            of UnitMangonel: 4
            of UnitTrebuchet: 5
            else: 1
          controller.reportThreat(teamId, other.pos, strength, currentStep,
                                  agentId = other.agentId.int32, isStructure = false)
      # Enemy structures
      for thing in env.spatialIndex.cells[nx][ny].things:
        if thing.isNil or not isBuildingKind(thing.kind):
          continue
        if thing.teamId < 0 or thing.teamId == teamId:
          continue
        if chebyshevDist(agent.pos, thing.pos) <= visionRange:
          let strength: int32 = case thing.kind
            of Castle: 5
            of GuardTower: 3
            of Barracks, ArcheryRange, Stable: 2
            else: 1
          controller.reportThreat(teamId, thing.pos, strength, currentStep,
                                  agentId = -1, isStructure = true)

proc updateClosestSeen*(state: var AgentState, basePos: IVec2, candidate: IVec2, current: var IVec2) =
  if candidate.x < 0:
    return
  if current.x < 0:
    current = candidate
    return
  if chebyshevDist(candidate, basePos) < chebyshevDist(current, basePos):
    current = candidate

proc clampToPlayable*(pos: IVec2): IVec2 {.inline.} =
  ## Keep positions inside the playable area (inside border walls).
  result.x = min(MapWidth - MapBorder - 1, max(MapBorder, pos.x))
  result.y = min(MapHeight - MapBorder - 1, max(MapBorder, pos.y))

proc getNextSpiralPoint*(state: var AgentState): IVec2 =
  ## Advance the spiral one step using incremental state.
  var direction = state.spiralArcsCompleted mod 4
  if not state.spiralClockwise:
    case direction
    of 1: direction = 3
    of 3: direction = 1
    else: discard
  let delta = case direction
    of 0: ivec2(0, -1)   # North
    of 1: ivec2(1, 0)    # East
    of 2: ivec2(0, 1)    # South
    else: ivec2(-1, 0)   # West

  state.lastSearchPosition = clampToPlayable(state.lastSearchPosition + delta)
  state.spiralStepsInArc += 1
  if state.spiralStepsInArc > (state.spiralArcsCompleted div 2) + 1:
    state.spiralArcsCompleted += 1
    state.spiralStepsInArc = 1
    if state.spiralArcsCompleted > 100:
      state.spiralArcsCompleted = 0
      state.spiralStepsInArc = 1
      state.basePosition = state.lastSearchPosition
  state.lastSearchPosition

proc findNearestThing*(env: Environment, pos: IVec2, kind: ThingKind,
                      maxDist: int = SearchRadius): Thing =
  ## Find nearest thing of a kind using spatial index for O(1) cell lookup
  findNearestThingSpatial(env, pos, kind, maxDist)

proc radiusBounds*(center: IVec2, radius: int): tuple[startX, endX, startY, endY: int] {.inline.} =
  (max(0, center.x.int - radius), min(MapWidth - 1, center.x.int + radius),
   max(0, center.y.int - radius), min(MapHeight - 1, center.y.int + radius))

proc findNearestWater*(env: Environment, pos: IVec2): IVec2 =
  result = ivec2(-1, -1)
  let (startX, endX, startY, endY) = radiusBounds(pos, SearchRadius)
  var minDist = int.high
  for x in startX .. endX:
    for y in startY .. endY:
      let dist = abs(x - pos.x.int) + abs(y - pos.y.int)
      if dist >= SearchRadius or dist >= minDist:
        continue
      if env.terrain[x][y] != Water:
        continue
      let candidate = ivec2(x.int32, y.int32)
      if isTileFrozen(candidate, env):
        continue
      minDist = dist
      result = candidate

proc findNearestFriendlyThing*(env: Environment, pos: IVec2, teamId: int, kind: ThingKind): Thing =
  ## Find nearest team-owned thing using spatial index for O(1) cell lookup
  findNearestFriendlyThingSpatial(env, pos, teamId, kind, SearchRadius)

proc findNearestThingSpiral*(env: Environment, state: var AgentState, kind: ThingKind): Thing =
  ## Find nearest thing using spiral search pattern - more systematic than random search
  template cacheAndReturn(thing: Thing) =
    state.cachedThingPos[kind] = thing.pos
    state.cachedThingStep[kind] = env.currentStep
    return thing

  let cachedPos = state.cachedThingPos[kind]
  if cachedPos.x >= 0:
    if env.currentStep - state.cachedThingStep[kind] < CacheMaxAge and
       abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      let cachedThing = env.getThing(cachedPos)
      if not isNil(cachedThing) and cachedThing.kind == kind and
         hasHarvestableResource(cachedThing):
        return cachedThing
    state.cachedThingPos[kind] = ivec2(-1, -1)

  result = findNearestThing(env, state.lastSearchPosition, kind)
  if not isNil(result): cacheAndReturn(result)
  result = findNearestThing(env, state.basePosition, kind)
  if not isNil(result): cacheAndReturn(result)

  for _ in 0 ..< SpiralAdvanceSteps:
    discard getNextSpiralPoint(state)
  result = findNearestThing(env, state.lastSearchPosition, kind)
  if not isNil(result): cacheAndReturn(result)

proc findNearestWaterSpiral*(env: Environment, state: var AgentState): IVec2 =
  template cacheAndReturn(pos: IVec2) =
    state.cachedWaterPos = pos
    state.cachedWaterStep = env.currentStep
    return pos

  let cachedPos = state.cachedWaterPos
  if cachedPos.x >= 0:
    if env.currentStep - state.cachedWaterStep < CacheMaxAge and
       abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      if env.terrain[cachedPos.x][cachedPos.y] == Water and not isTileFrozen(cachedPos, env):
        return cachedPos
    state.cachedWaterPos = ivec2(-1, -1)

  result = findNearestWater(env, state.lastSearchPosition)
  if result.x >= 0: cacheAndReturn(result)
  result = findNearestWater(env, state.basePosition)
  if result.x >= 0: cacheAndReturn(result)

  for _ in 0 ..< SpiralAdvanceSteps:
    discard getNextSpiralPoint(state)
  result = findNearestWater(env, state.lastSearchPosition)
  if result.x >= 0: cacheAndReturn(result)

proc findNearestFriendlyThingSpiral*(env: Environment, state: var AgentState, teamId: int,
                                    kind: ThingKind): Thing =
  ## Find nearest team-owned thing using spiral search pattern
  result = findNearestFriendlyThing(env, state.lastSearchPosition, teamId, kind)
  if not isNil(result):
    return result

  result = findNearestFriendlyThing(env, state.basePosition, teamId, kind)
  if not isNil(result):
    return result

  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)
  result = findNearestFriendlyThing(env, nextSearchPos, teamId, kind)
  return result

template forNearbyCells*(center: IVec2, radius: int, body: untyped) =
  let cx {.inject.} = center.x.int
  let cy {.inject.} = center.y.int
  let startX {.inject.} = max(0, cx - radius)
  let endX {.inject.} = min(MapWidth - 1, cx + radius)
  let startY {.inject.} = max(0, cy - radius)
  let endY {.inject.} = min(MapHeight - 1, cy + radius)
  for x {.inject.} in startX..endX:
    for y {.inject.} in startY..endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      body

proc countNearbyTerrain*(env: Environment, center: IVec2, radius: int,
                         allowed: set[TerrainType]): int =
  forNearbyCells(center, radius):
    if env.terrain[x][y] in allowed:
      inc result

proc countNearbyThings*(env: Environment, center: IVec2, radius: int,
                        allowed: set[ThingKind]): int =
  forNearbyCells(center, radius):
    let occ = env.grid[x][y]
    if not isNil(occ) and occ.kind in allowed:
      inc result

proc nearestFriendlyBuildingDistance*(env: Environment, teamId: int,
                                      kinds: openArray[ThingKind], pos: IVec2): int =
  ## Find distance to nearest friendly building of specified kinds.
  ## Optimized: uses spatial index for O(cells) instead of O(n) thingsByKind iteration.
  result = int.high
  for kind in kinds:
    # Use current best distance as maxDist to enable early-exit optimization
    let nearest = findNearestFriendlyThingSpatial(env, pos, teamId, kind, result)
    if not nearest.isNil:
      result = min(result, int(chebyshevDist(nearest.pos, pos)))

proc getBuildingCount*(controller: Controller, env: Environment, teamId: int, kind: ThingKind): int =
  if controller.buildingCountsStep != env.currentStep:
    controller.buildingCountsStep = env.currentStep
    controller.buildingCounts = default(array[MapRoomObjectsTeams, array[ThingKind, int]])
    # Clear claimed buildings at start of new step - claims are per-step to prevent
    # multiple builders from trying to build the same building type in the same step
    controller.claimedBuildings = default(array[MapRoomObjectsTeams, set[ThingKind]])
    # Optimized: iterate only building kinds via thingsByKind instead of all env.things
    for bKind in TeamBuildingKinds:
      for thing in env.thingsByKind[bKind]:
        if thing.teamId < 0 or thing.teamId >= MapRoomObjectsTeams:
          continue
        controller.buildingCounts[thing.teamId][thing.kind] += 1
  controller.buildingCounts[teamId][kind]

proc isBuildingClaimed*(controller: Controller, teamId: int, kind: ThingKind): bool =
  ## Check if a building type is claimed by another builder this step.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  kind in controller.claimedBuildings[teamId]

proc claimBuilding*(controller: Controller, teamId: int, kind: ThingKind) =
  ## Claim a building type so other builders don't try to build the same thing.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  controller.claimedBuildings[teamId].incl(kind)

proc getBuildingCountNear*(env: Environment, teamId: int, kind: ThingKind,
                          center: IVec2, radius: int32 = SettlementRadius): int =
  ## Count buildings of a given type for a team within Chebyshev distance of center.
  ## Used for per-settlement building checks (e.g., each settlement needs its own Granary).
  for thing in env.thingsByKind[kind]:
    if thing.teamId != teamId:
      continue
    if chebyshevDist(center, thing.pos) <= radius:
      inc result

proc anyMissingBuildingNear*(env: Environment, teamId: int,
                             kinds: openArray[ThingKind],
                             center: IVec2, radius: int32 = SettlementRadius): bool =
  ## Check if any of the given building types are missing near a settlement center.
  for kind in kinds:
    if getBuildingCountNear(env, teamId, kind, center, radius) == 0:
      return true
  false

proc getTotalBuildingCountNear*(env: Environment, teamId: int,
                                center: IVec2, radius: int32 = SettlementRadius): int =
  ## Count total buildings for a team within Chebyshev distance of a settlement center.
  for bKind in TeamBuildingKinds:
    for thing in env.thingsByKind[bKind]:
      if thing.teamId != teamId:
        continue
      if chebyshevDist(center, thing.pos) <= radius:
        inc result

proc canAffordBuild*(env: Environment, agent: Thing, key: ItemKey): bool =
  let costs = buildCostsForKey(key)
  choosePayment(env, agent, costs) != PayNone


proc neighborDirIndex*(fromPos, toPos: IVec2): int =
  ## Orientation index (0..7) toward adjacent target (includes diagonals)
  vecToOrientation(ivec2(signi(toPos.x - fromPos.x), signi(toPos.y - fromPos.y)))


proc sameTeam*(agentA, agentB: Thing): bool =
  ## Check if two Things are on the same team using bitwise mask comparison.
  ## Uses O(1) bitwise AND operation for efficiency in hot paths.
  sameTeamMask(agentA, agentB)

proc getBasePos*(agent: Thing): IVec2 =
  ## Return the agent's home altar position if valid, otherwise the agent's current position.
  if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos

proc findTeamAltar*(env: Environment, agent: Thing, teamId: int): tuple[pos: IVec2, hearts: int] =
  ## Find the nearest team altar, preferring the agent's home altar.
  ## Returns (position, hearts) or (ivec2(-1,-1), 0) if none found.
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      return (homeAltar.pos, homeAltar.hearts)
  # Use spatial query instead of O(n) altar scan
  let nearestAltar = findNearestFriendlyThingSpatial(env, agent.pos, teamId, Altar, 1000)
  if not nearestAltar.isNil:
    return (nearestAltar.pos, nearestAltar.hearts)
  (ivec2(-1, -1), 0)

proc findAttackOpportunity*(env: Environment, agent: Thing): int =
  ## Return attack orientation index if a valid target is in reach, else -1.
  ## Simplified: pick the closest aligned target within range using a priority order.
  ## Respects agent stance:
  ## - Aggressive/StandGround: auto-attack enemies in range
  ## - Defensive: only auto-attack if recently attacked (retaliation)
  ## - NoAttack: never auto-attack
  ##
  ## Optimized: scans 8 attack lines (cardinal+diagonal) out to maxRange
  ## instead of iterating all env.things. Cost: O(8 * maxRange) = O(48) max.
  if agent.unitClass == UnitMonk:
    return -1
  # Check stance allows auto-attacking (handles defensive retaliation logic)
  if not stanceAllowsAutoAttack(env, agent):
    return -1

  let maxRange = case agent.unitClass
    of UnitArcher, UnitCrossbowman, UnitArbalester: ArcherBaseRange
    of UnitMangonel: MangonelAoELength
    of UnitTrebuchet:
      if agent.packed: 0 else: TrebuchetBaseRange  # Can't attack when packed
    else:
      if agent.inventorySpear > 0: 2 else: 1

  if maxRange <= 0:
    return -1

  proc targetPriority(kind: ThingKind): int =
    if agent.unitClass == UnitMangonel:
      if kind in AttackableStructures:
        return 0
      case kind
      of Tumor: 1
      of Spawner: 2
      of Agent: 3
      else: 4
    else:
      case kind
      of Tumor: 0
      of Spawner: 1
      of Agent: 2
      else:
        if kind in AttackableStructures: 3 else: 4

  let agentTeamId = getTeamId(agent)
  var bestDir = -1
  var bestDist = int.high
  var bestPriority = int.high

  template tryTarget(thing: Thing, dirI: int, stepDist: int) =
    ## Check if thing is a valid attack target and update best if higher priority.
    let isEnemy = case thing.kind
      of Agent: isAgentAlive(env, thing) and not sameTeam(agent, thing)
      of Tumor, Spawner: true
      else: thing.kind in AttackableStructures and thing.teamId != agentTeamId
    if isEnemy:
      let priority = targetPriority(thing.kind)
      if priority < bestPriority or (priority == bestPriority and stepDist < bestDist):
        bestPriority = priority
        bestDist = stepDist
        bestDir = dirI

  # Scan along 8 directions (cardinal + diagonal) up to maxRange
  for dirIdx in 0 .. 7:
    let d = Directions8[dirIdx]
    for step in 1 .. maxRange:
      let tx = agent.pos.x + d.x * step
      let ty = agent.pos.y + d.y * step
      if tx < 0 or tx >= MapWidth or ty < 0 or ty >= MapHeight:
        break
      let gridThing = env.grid[tx][ty]
      if not gridThing.isNil:
        tryTarget(gridThing, dirIdx, step)
      let bgThing = env.backgroundGrid[tx][ty]
      if not bgThing.isNil and bgThing != gridThing:
        tryTarget(bgThing, dirIdx, step)

  return bestDir

proc isPassable*(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Consider lantern tiles passable for generic checks and respect doors/water.
  if not isValidPos(pos):
    return false
  if env.isWaterBlockedForAgent(agent, pos):
    return false
  if not env.canAgentPassDoor(agent, pos):
    return false
  let occupant = env.grid[pos.x][pos.y]
  if isNil(occupant):
    return true
  return occupant.kind == Lantern

proc canEnterForMove*(env: Environment, agent: Thing, fromPos, toPos: IVec2): bool =
  ## Directional passability check that mirrors move logic (lantern pushing rules).
  if not isValidPos(toPos):
    return false
  if toPos.x < MapBorder.int32 or toPos.x >= (MapWidth - MapBorder).int32 or
      toPos.y < MapBorder.int32 or toPos.y >= (MapHeight - MapBorder).int32:
    return false
  if not env.canTraverseElevation(fromPos, toPos):
    return false
  if env.isWaterBlockedForAgent(agent, toPos):
    return false
  if not env.canAgentPassDoor(agent, toPos):
    return false
  if env.isEmpty(toPos):
    return true
  let blocker = env.getThing(toPos)
  if isNil(blocker) or blocker.kind != Lantern:
    return false

  # Uses spatial query instead of O(n) lantern scan
  template spacingOk(nextPos: IVec2): bool =
    var ok = true
    var nearbyLanterns: seq[Thing] = @[]
    collectThingsInRangeSpatial(env, nextPos, Lantern, 2, nearbyLanterns)
    for t in nearbyLanterns:
      if t != blocker:
        ok = false
        break
    ok

  let delta = toPos - fromPos
  let ahead1 = ivec2(toPos.x + delta.x, toPos.y + delta.y)
  let ahead2 = ivec2(toPos.x + delta.x * 2, toPos.y + delta.y * 2)
  if isValidPos(ahead2) and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and
      not env.isWaterBlockedForAgent(agent, ahead2) and spacingOk(ahead2):
    return true
  if isValidPos(ahead1) and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and
      not env.isWaterBlockedForAgent(agent, ahead1) and spacingOk(ahead1):
    return true

  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0:
        continue
      let alt = ivec2(toPos.x + dx, toPos.y + dy)
      if not isValidPos(alt):
        continue
      if env.isEmpty(alt) and not env.hasDoor(alt) and
          not env.isWaterBlockedForAgent(agent, alt) and spacingOk(alt):
        return true
  return false

proc getMoveTowards*(env: Environment, agent: Thing, fromPos, toPos: IVec2,
                    rng: var Rand, avoidDir: int = -1): int =
  ## Get a movement direction towards target, with obstacle avoidance
  let clampedTarget = clampToPlayable(toPos)
  if clampedTarget == fromPos:
    # Target is outside playable bounds; push back inward toward the widest margin.
    var bestDir = -1
    var bestMargin = -1
    var avoidCandidate = -1
    for idx, d in Directions8:
      let np = fromPos + d
      if not canEnterForMove(env, agent, fromPos, np):
        continue
      if idx == avoidDir:
        avoidCandidate = idx
        continue
      let marginX = min(np.x - MapBorder, (MapWidth - MapBorder - 1) - np.x)
      let marginY = min(np.y - MapBorder, (MapHeight - MapBorder - 1) - np.y)
      let margin = min(marginX, marginY)
      if margin > bestMargin:
        bestMargin = margin
        bestDir = idx
    if bestDir >= 0:
      return bestDir
    if avoidCandidate >= 0:
      return avoidCandidate
    return -1

  let dx = clampedTarget.x - fromPos.x
  let dy = clampedTarget.y - fromPos.y
  let step = ivec2(signi(dx), signi(dy))
  if step.x != 0 or step.y != 0:
    let primaryDir = vecToOrientation(step)
    let primaryMove = fromPos + Directions8[primaryDir]
    if primaryDir != avoidDir and canEnterForMove(env, agent, fromPos, primaryMove):
      return primaryDir

  var bestDir = -1
  var bestDist = int.high
  var avoidCandidate = -1
  for idx, d in Directions8:
    let np = fromPos + d
    if not canEnterForMove(env, agent, fromPos, np):
      continue
    if idx == avoidDir:
      avoidCandidate = idx
      continue
    let dist = int(chebyshevDist(np, clampedTarget))
    if dist < bestDist:
      bestDist = dist
      bestDir = idx
  if bestDir >= 0:
    return bestDir
  if avoidCandidate >= 0:
    return avoidCandidate

  # All blocked - return -1 to signal no valid move (caller should noop)
  return -1

proc findPath*(controller: Controller, env: Environment, agent: Thing, fromPos, targetPos: IVec2): seq[IVec2] =
  ## A* pathfinding from fromPos toward targetPos, returning the path as a
  ## sequence of positions (including start). If targetPos itself is impassable,
  ## the algorithm targets passable neighbors instead.
  ##
  ## Implementation notes:
  ## - Uses a generation counter to invalidate stale cache entries in O(1)
  ##   instead of clearing the full map-sized arrays each call.
  ## - Open set uses a binary heap (min-heap by f-score) for O(log n) extraction.
  ## - Exploration is capped at 250 nodes to bound worst-case cost per tick.

  # Increment generation for this call - makes all previous data stale
  inc controller.pathCache.generation
  let gen = controller.pathCache.generation

  # Build goals list (target or passable neighbors)
  controller.pathCache.goalsLen = 0
  if isPassable(env, agent, targetPos):
    controller.pathCache.goals[0] = targetPos
    controller.pathCache.goalsLen = 1
  else:
    for d in Directions8:
      let candidate = targetPos + d
      if isValidPos(candidate) and isPassable(env, agent, candidate):
        if controller.pathCache.goalsLen < MaxPathGoals:
          controller.pathCache.goals[controller.pathCache.goalsLen] = candidate
          inc controller.pathCache.goalsLen

  if controller.pathCache.goalsLen == 0:
    return @[]

  # Check if already at goal
  for i in 0 ..< controller.pathCache.goalsLen:
    if controller.pathCache.goals[i] == fromPos:
      return @[fromPos]

  # Heuristic: minimum chebyshev distance to any goal
  proc heuristic(cache: PathfindingCache, loc: IVec2): int32 =
    var best = int32.high
    for i in 0 ..< cache.goalsLen:
      let d = int32(chebyshevDist(loc, cache.goals[i]))
      if d < best:
        best = d
    best

  # Initialize open heap with starting position
  controller.pathCache.openHeap.clear()
  let startH = heuristic(controller.pathCache, fromPos)
  controller.pathCache.openHeap.push(PathHeapNode(fScore: startH, pos: fromPos))

  # Initialize gScore for start
  controller.pathCache.gScoreGen[fromPos.x][fromPos.y] = gen
  controller.pathCache.gScoreVal[fromPos.x][fromPos.y] = 0

  var explored = 0
  while controller.pathCache.openHeap.len > 0:
    if explored > 250:
      return @[]

    # Pop node with lowest f-score from heap
    let node = controller.pathCache.openHeap.pop()
    let current = node.pos

    # Skip if already processed (closed) - handles duplicate heap entries
    if controller.pathCache.closedGen[current.x][current.y] == gen:
      continue

    # Mark as closed
    controller.pathCache.closedGen[current.x][current.y] = gen
    inc explored

    # Check if current is a goal
    for i in 0 ..< controller.pathCache.goalsLen:
      if current == controller.pathCache.goals[i]:
        # Reconstruct path
        controller.pathCache.pathLen = 0
        var cur = current
        while true:
          if controller.pathCache.pathLen >= MaxPathLength:
            break
          controller.pathCache.path[controller.pathCache.pathLen] = cur
          inc controller.pathCache.pathLen
          # Check if we have a parent
          if controller.pathCache.cameFromGen[cur.x][cur.y] != gen:
            break
          cur = controller.pathCache.cameFromVal[cur.x][cur.y]

        # Build result seq in correct order (path is reversed)
        result = newSeq[IVec2](controller.pathCache.pathLen)
        for j in 0 ..< controller.pathCache.pathLen:
          result[j] = controller.pathCache.path[controller.pathCache.pathLen - 1 - j]
        return result

    # Explore neighbors
    for dirIdx in 0 .. 7:
      let nextPos = current + Directions8[dirIdx]
      if not isValidPos(nextPos):
        continue
      if not canEnterForMove(env, agent, current, nextPos):
        continue

      # Skip if already closed
      if controller.pathCache.closedGen[nextPos.x][nextPos.y] == gen:
        continue

      # Get current gScore (or int32.high if not visited)
      let currentG = controller.pathCache.gScoreVal[current.x][current.y]
      let tentativeG = currentG + 1

      # Get neighbor's current gScore
      let neighborHasScore = controller.pathCache.gScoreGen[nextPos.x][nextPos.y] == gen
      let nextG = if neighborHasScore: controller.pathCache.gScoreVal[nextPos.x][nextPos.y] else: int32.high

      if tentativeG < nextG:
        # Update cameFrom
        controller.pathCache.cameFromGen[nextPos.x][nextPos.y] = gen
        controller.pathCache.cameFromVal[nextPos.x][nextPos.y] = current
        # Update gScore
        controller.pathCache.gScoreGen[nextPos.x][nextPos.y] = gen
        controller.pathCache.gScoreVal[nextPos.x][nextPos.y] = tentativeG
        # Push to heap (duplicates OK - stale entries skipped via closed check)
        let h = heuristic(controller.pathCache, nextPos)
        controller.pathCache.openHeap.push(PathHeapNode(fScore: tentativeG + h, pos: nextPos))

  @[]

proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  ## Check if there's a healthy team lantern within 3 tiles of position.
  ## Optimized: uses spatial index for O(1 cell) instead of O(all lanterns) iteration.
  var nearby: seq[Thing] = @[]
  collectThingsInRangeSpatial(env, pos, Lantern, 3, nearby)
  for thing in nearby:
    if thing.lanternHealthy and thing.teamId == teamId:
      return true
  false

proc isLanternPlacementValid*(env: Environment, pos: IVec2): bool =
  isValidPos(pos) and env.isEmpty(pos) and not env.hasDoor(pos) and
    not isBlockedTerrain(env.terrain[pos.x][pos.y]) and not isTileFrozen(pos, env) and
    env.terrain[pos.x][pos.y] != Water


proc tryPlantOnFertile*(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  ## If carrying wood/wheat and a fertile tile is nearby, plant; otherwise move toward it.
  if agent.inventoryWheat > 0 or agent.inventoryWood > 0:
    var fertilePos = ivec2(-1, -1)
    var minDist = int.high
    let startX = max(0, agent.pos.x - 8)
    let endX = min(MapWidth - 1, agent.pos.x + 8)
    let startY = max(0, agent.pos.y - 8)
    let endY = min(MapHeight - 1, agent.pos.y + 8)
    let ax = agent.pos.x.int
    let ay = agent.pos.y.int
    for x in startX..endX:
      for y in startY..endY:
        if env.terrain[x][y] != TerrainType.Fertile:
          continue
        let candPos = ivec2(x.int32, y.int32)
        if env.isEmpty(candPos) and isNil(env.getBackgroundThing(candPos)) and not env.hasDoor(candPos):
          let dist = abs(x - ax) + abs(y - ay)
          if dist < minDist:
            minDist = dist
            fertilePos = candPos
    if fertilePos.x >= 0:
      if max(abs(fertilePos.x - agent.pos.x), abs(fertilePos.y - agent.pos.y)) == 1'i32:
        let dirIdx = neighborDirIndex(agent.pos, fertilePos)
        let plantArg = (if agent.inventoryWheat > 0: dirIdx else: dirIdx + 4)
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(7'u8, plantArg.uint8)))
      else:
        let avoidDir = (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
        let dir = getMoveTowards(env, agent, agent.pos, fertilePos, controller.rng, avoidDir)
        if dir < 0:
          return (false, 0'u8)  # Can't move toward fertile, let other option handle it
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(1'u8, dir.uint8)))
  return (false, 0'u8)

proc moveNextSearch*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): uint8 =
  let dir = getMoveTowards(
    env, agent, agent.pos, getNextSpiralPoint(state),
    controller.rng, (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1))
  if dir < 0:
    return saveStateAndReturn(controller, agentId, state, 0'u8)  # Noop when blocked
  return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dir.uint8))

proc isAdjacent*(a, b: IVec2): bool =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  max(dx, dy) == 1'i32

proc actAt*(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2, verb: uint8,
           argument: int = -1): uint8 =
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(verb,
      (if argument < 0: neighborDirIndex(agent.pos, targetPos) else: argument).uint8))

proc isOscillating*(state: AgentState): bool =
  ## Detect stuck/oscillating movement by checking if the last 6 positions
  ## contain at most 2 unique locations (bouncing between the same tiles).
  if state.recentPosCount < 6:
    return false
  var uniqueCount = 0
  var unique: array[4, IVec2]
  let historyLen = state.recentPositions.len
  for i in 0 ..< 6:
    let idx = (state.recentPosIndex - 1 - i + historyLen * historyLen) mod historyLen
    let p = state.recentPositions[idx]
    var seen = false
    for j in 0 ..< uniqueCount:
      if unique[j] == p:
        seen = true
        break
    if not seen:
      if uniqueCount < unique.len:
        unique[uniqueCount] = p
        inc uniqueCount
      if uniqueCount > 2:
        return false
  uniqueCount <= 2

proc moveTo*(controller: Controller, env: Environment, agent: Thing, agentId: int,
            state: var AgentState, targetPos: IVec2): uint8 =
  ## Move agent toward targetPos using A* for long distances and greedy movement
  ## for short distances. Detects oscillation and falls back to spiral search
  ## when paths are blocked.
  if state.pathBlockedTarget == targetPos:
    return controller.moveNextSearch(env, agent, agentId, state)
  let stuck = isOscillating(state)
  if stuck:
    state.pathBlockedTarget = ivec2(-1, -1)
    state.plannedPath.setLen(0)

  template replanPath() =
    state.plannedPath = findPath(controller, env, agent, agent.pos, targetPos)
    state.plannedTarget = targetPos
    state.plannedPathIndex = 0

  let usesAstar = chebyshevDist(agent.pos, targetPos) >= 6 or stuck
  if usesAstar:
    if state.pathBlockedTarget != targetPos or stuck:
      let needsReplan = state.plannedTarget != targetPos or
                        state.plannedPath.len == 0 or stuck
      let driftedOffPath = not needsReplan and
                           state.plannedPathIndex < state.plannedPath.len and
                           state.plannedPath[state.plannedPathIndex] != agent.pos
      if needsReplan or driftedOffPath:
        replanPath()
      if state.plannedPath.len >= 2 and state.plannedPathIndex < state.plannedPath.len - 1:
        let nextPos = state.plannedPath[state.plannedPathIndex + 1]
        if canEnterForMove(env, agent, agent.pos, nextPos):
          var dirIdx = neighborDirIndex(agent.pos, nextPos)
          if state.role == Builder and state.lastPosition == nextPos:
            let altDir = getMoveTowards(env, agent, agent.pos, targetPos, controller.rng, dirIdx)
            if altDir != dirIdx:
              state.plannedPath.setLen(0)
              state.plannedPathIndex = 0
              return saveStateAndReturn(controller, agentId, state,
                encodeAction(1'u8, altDir.uint8))
          state.plannedPathIndex += 1
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(1'u8, dirIdx.uint8))
        # Next step blocked - recompute path instead of giving up on target
        state.plannedPath = findPath(controller, env, agent, agent.pos, targetPos)
        state.plannedTarget = targetPos
        state.plannedPathIndex = 0
        # If recomputed path is valid, follow it immediately
        if state.plannedPath.len >= 2:
          let recomputedNext = state.plannedPath[1]
          if canEnterForMove(env, agent, agent.pos, recomputedNext):
            let dirIdx = neighborDirIndex(agent.pos, recomputedNext)
            state.plannedPathIndex = 1
            return saveStateAndReturn(controller, agentId, state,
              encodeAction(1'u8, dirIdx.uint8))
        # Recompute also failed - mark target as blocked
        state.plannedPath.setLen(0)
        state.pathBlockedTarget = targetPos
        return controller.moveNextSearch(env, agent, agentId, state)
      elif state.plannedPath.len == 0:
        state.pathBlockedTarget = targetPos
        return controller.moveNextSearch(env, agent, agentId, state)
    else:
      state.plannedPath.setLen(0)
  var dirIdx = getMoveTowards(
    env, agent, agent.pos, targetPos, controller.rng,
    (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
  )
  if dirIdx < 0:
    return saveStateAndReturn(controller, agentId, state, 0'u8)  # Noop when blocked
  if state.role == Builder and state.lastPosition == agent.pos + Directions8[dirIdx]:
    let altDir = getMoveTowards(env, agent, agent.pos, targetPos, controller.rng, dirIdx)
    if altDir >= 0 and altDir != dirIdx:
      dirIdx = altDir
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, dirIdx.uint8))

proc useAt*(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2): uint8 =
  actAt(controller, env, agent, agentId, state, targetPos, 3'u8)

proc useOrMoveTo*(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState, targetPos: IVec2): uint8 =
  ## If adjacent to target, interact (use); otherwise move toward it.
  if isAdjacent(agent.pos, targetPos):
    controller.actAt(env, agent, agentId, state, targetPos, 3'u8)
  else:
    controller.moveTo(env, agent, agentId, state, targetPos)

proc tryMoveToKnownResource*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                            state: var AgentState, pos: var IVec2,
                            allowed: set[ThingKind], verb: uint8): tuple[did: bool, action: uint8] =
  if pos.x < 0:
    return (false, 0'u8)
  if pos == state.pathBlockedTarget:
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  let thing = env.getThing(pos)
  if isNil(thing) or thing.kind notin allowed or isThingFrozen(thing, env) or
     not hasHarvestableResource(thing):
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  # Skip if reserved by another agent on our team
  let teamId = getTeamId(agent)
  if isResourceReserved(teamId, pos, agentId):
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  # Reserve this resource for ourselves
  discard reserveResource(teamId, agentId, pos, env.currentStep)
  return (true, if isAdjacent(agent.pos, pos):
    actAt(controller, env, agent, agentId, state, pos, verb)
  else:
    moveTo(controller, env, agent, agentId, state, pos))

proc moveToNearestSmith*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                        state: var AgentState, teamId: int): tuple[did: bool, action: uint8] =
  let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith)
  if not isNil(smith):
    return (true, controller.useOrMoveTo(env, agent, agentId, state, smith.pos))
  (false, 0'u8)

proc findDropoffBuilding*(env: Environment, state: var AgentState, teamId: int,
                          res: StockpileResource, rng: var Rand): Thing =
  template tryKind(kind: ThingKind) =
    if isNil(result):
      result = env.findNearestFriendlyThingSpiral(state, teamId, kind)
  case res
  of ResourceFood:
    tryKind(Granary); tryKind(Mill); tryKind(TownCenter)
  of ResourceWood:
    tryKind(LumberCamp); tryKind(TownCenter)
  of ResourceStone:
    tryKind(Quarry); tryKind(TownCenter)
  of ResourceGold:
    tryKind(MiningCamp); tryKind(TownCenter)
  of ResourceWater, ResourceNone:
    discard
  if isNil(result):
    # Use spatial query instead of O(n) TownCenter scan
    result = findNearestFriendlyThingSpatial(env, state.basePosition, teamId, TownCenter, 1000)

proc dropoffCarrying*(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState,
                      allowFood: bool = false,
                      allowWood: bool = false,
                      allowStone: bool = false,
                      allowGold: bool = false): tuple[did: bool, action: uint8] =
  ## Unified dropoff function - attempts to drop off resources in priority order
  let teamId = getTeamId(agent)

  template tryDropoff(res: StockpileResource) =
    let dropoff = findDropoffBuilding(env, state, teamId, res, controller.rng)
    if not isNil(dropoff):
      return (true, controller.useOrMoveTo(env, agent, agentId, state, dropoff.pos))

  if allowFood:
    for key, count in agent.inventory.pairs:
      if count > 0 and isFoodItem(key):
        tryDropoff(ResourceFood)
        break

  if allowWood and agent.inventoryWood > 0: tryDropoff(ResourceWood)
  if allowGold and agent.inventoryGold > 0: tryDropoff(ResourceGold)
  if allowStone and agent.inventoryStone > 0: tryDropoff(ResourceStone)

  (false, 0'u8)

proc ensureResourceReserved(controller: Controller, env: Environment, agent: Thing, agentId: int,
                            state: var AgentState, closestPos: var IVec2,
                            allowedKinds: set[ThingKind],
                            kinds: openArray[ThingKind]): tuple[did: bool, action: uint8] =
  ## Shared resource-gathering with reservation: check cached position, spiral-search
  ## for the nearest resource of the given kinds, reserve it, then use or move to it.
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, closestPos, allowedKinds, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let teamId = getTeamId(agent)
  for kind in kinds:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    if isResourceReserved(teamId, target.pos, agentId):
      continue
    updateClosestSeen(state, state.basePosition, target.pos, closestPos)
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWood*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  ensureResourceReserved(controller, env, agent, agentId, state,
    state.closestWoodPos, {Stump, Tree}, [Stump, Tree])

proc ensureStone*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  ensureResourceReserved(controller, env, agent, agentId, state,
    state.closestStonePos, {Stone, Stalagmite}, [Stone, Stalagmite])

proc ensureGold*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  ensureResourceReserved(controller, env, agent, agentId, state,
    state.closestGoldPos, {Gold}, [Gold])

proc ensureWater*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  # Invalidate cached water if blocked, depleted, or frozen
  if state.closestWaterPos.x >= 0 and
     (state.closestWaterPos == state.pathBlockedTarget or
      env.terrain[state.closestWaterPos.x][state.closestWaterPos.y] != Water or
      isTileFrozen(state.closestWaterPos, env)):
    state.closestWaterPos = ivec2(-1, -1)
  if state.closestWaterPos.x >= 0:
    return (true, controller.useOrMoveTo(env, agent, agentId, state, state.closestWaterPos))
  let target = findNearestWaterSpiral(env, state)
  if target.x >= 0 and target != state.pathBlockedTarget:
    updateClosestSeen(state, state.basePosition, target, state.closestWaterPos)
    return (true, controller.useOrMoveTo(env, agent, agentId, state, target))
  if target.x >= 0:
    state.cachedWaterPos = ivec2(-1, -1)
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWheat*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent)
  for kind in [Wheat, Stubble]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    # Skip if reserved by another agent
    if isResourceReserved(teamId, target.pos, agentId):
      continue
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureHuntFood*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent)
  for kind in [Corpse, Cow, Bush, Fish]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    # Skip if reserved by another agent
    if isResourceReserved(teamId, target.pos, agentId):
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestFoodPos)
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    # For cows: milk (interact) if healthy and food not critical, kill (attack) otherwise
    let verb = if kind == Cow:
      let foodCritical = env.stockpileCount(teamId, ResourceFood) < 3
      let cowHealthy = target.hp * 2 >= target.maxHp
      if cowHealthy and not foodCritical: 3'u8 else: 2'u8
    else:
      3'u8
    return (true, if isAdjacent(agent.pos, target.pos):
      (if verb == 2'u8:
        controller.actAt(env, agent, agentId, state, target.pos, verb)
      else:
        controller.useAt(env, agent, agentId, state, target.pos))
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

# Patrol behavior helpers
proc setPatrol*(controller: Controller, agentId: int, point1, point2: IVec2) =
  ## Set patrol waypoints for an agent. Enables patrol mode.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolPoint1 = point1
    controller.agents[agentId].patrolPoint2 = point2
    controller.agents[agentId].patrolToSecondPoint = true
    controller.agents[agentId].patrolActive = true

proc clearPatrol*(controller: Controller, agentId: int) =
  ## Disable patrol mode for an agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolActive = false
    controller.agents[agentId].patrolPoint1 = ivec2(-1, -1)
    controller.agents[agentId].patrolPoint2 = ivec2(-1, -1)

proc isPatrolActive*(controller: Controller, agentId: int): bool =
  ## Check if patrol mode is active for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].patrolActive
  false

proc getPatrolTarget*(controller: Controller, agentId: int): IVec2 =
  ## Get the current patrol target waypoint.
  if agentId >= 0 and agentId < MapAgents:
    let state = controller.agents[agentId]
    if state.patrolToSecondPoint:
      return state.patrolPoint2
    else:
      return state.patrolPoint1
  ivec2(-1, -1)

# Scout behavior helpers
proc setScoutMode*(controller: Controller, agentId: int, active: bool = true) =
  ## Enable or disable scout mode for an agent. Scouts explore outward from base
  ## and flee when enemies are spotted, reporting threats to the team.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].scoutActive = active
    if active:
      controller.agents[agentId].scoutExploreRadius = ObservationRadius.int32 + 5
      controller.agents[agentId].scoutLastEnemySeenStep = -100  # Long ago

proc clearScoutMode*(controller: Controller, agentId: int) =
  ## Disable scout mode for an agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].scoutActive = false

proc isScoutModeActive*(controller: Controller, agentId: int): bool =
  ## Check if scout mode is active for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].scoutActive
  false

proc getScoutExploreRadius*(controller: Controller, agentId: int): int32 =
  ## Get the current exploration radius for a scouting agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].scoutExploreRadius
  0

proc recordScoutEnemySighting*(controller: Controller, agentId: int, currentStep: int32) =
  ## Record that the scout has seen an enemy. Used to trigger flee behavior.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].scoutLastEnemySeenStep = currentStep

# Hold position behavior helpers
proc setHoldPosition*(controller: Controller, agentId: int, pos: IVec2) =
  ## Set hold position for an agent. The agent will stay at the given position
  ## and attack enemies in range but won't chase.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].holdPositionTarget = pos
    controller.agents[agentId].holdPositionActive = true

proc clearHoldPosition*(controller: Controller, agentId: int) =
  ## Disable hold position for an agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].holdPositionActive = false
    controller.agents[agentId].holdPositionTarget = ivec2(-1, -1)

proc isHoldPositionActive*(controller: Controller, agentId: int): bool =
  ## Check if hold position is active for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].holdPositionActive
  false

proc getHoldPosition*(controller: Controller, agentId: int): IVec2 =
  ## Get the hold position target for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].holdPositionTarget
  ivec2(-1, -1)

# Follow behavior helpers
proc setFollowTarget*(controller: Controller, agentId: int, targetAgentId: int) =
  ## Set an agent to follow another agent.
  if agentId >= 0 and agentId < MapAgents and
     targetAgentId >= 0 and targetAgentId < MapAgents:
    controller.agents[agentId].followTargetAgentId = targetAgentId
    controller.agents[agentId].followActive = true

proc clearFollowTarget*(controller: Controller, agentId: int) =
  ## Disable follow mode for an agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].followActive = false
    controller.agents[agentId].followTargetAgentId = -1

proc isFollowActive*(controller: Controller, agentId: int): bool =
  ## Check if follow mode is active for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].followActive
  false

proc getFollowTargetId*(controller: Controller, agentId: int): int =
  ## Get the follow target agent ID for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].followTargetAgentId
  -1

# Stop behavior helpers
const StopIdleSteps* = 200  # Steps before stopped agent returns to default role behavior

proc stopAgentInternal(controller: Controller, agentId: int) =
  ## Internal helper: clears all orders, path, and active option without setting expiry.
  if agentId >= 0 and agentId < MapAgents:
    # Clear all movement/behavior modes
    controller.agents[agentId].patrolActive = false
    controller.agents[agentId].patrolPoint1 = ivec2(-1, -1)
    controller.agents[agentId].patrolPoint2 = ivec2(-1, -1)
    controller.agents[agentId].attackMoveTarget = ivec2(-1, -1)
    controller.agents[agentId].scoutActive = false
    controller.agents[agentId].holdPositionActive = false
    controller.agents[agentId].holdPositionTarget = ivec2(-1, -1)
    controller.agents[agentId].followActive = false
    controller.agents[agentId].followTargetAgentId = -1
    # Clear current path
    controller.agents[agentId].plannedPath.setLen(0)
    controller.agents[agentId].plannedPathIndex = 0
    controller.agents[agentId].plannedTarget = ivec2(-1, -1)
    controller.agents[agentId].pathBlockedTarget = ivec2(-1, -1)
    # Reset active option
    controller.agents[agentId].activeOptionId = -1
    controller.agents[agentId].activeOptionTicks = 0

proc stopAgentFull*(controller: Controller, agentId: int, currentStep: int32) =
  ## Fully stop an agent: clears all orders, path, and active option.
  ## Agent will remain idle until given a new command or StopIdleSteps passes.
  stopAgentInternal(controller, agentId)
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].stoppedActive = true
    controller.agents[agentId].stoppedUntilStep = currentStep + StopIdleSteps

proc stopAgentDeferred*(controller: Controller, agentId: int) =
  ## Stop an agent without knowing the current step.
  ## Sets stoppedUntilStep to -1 (sentinel); decideAction will initialize it properly.
  stopAgentInternal(controller, agentId)
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].stoppedActive = true
    controller.agents[agentId].stoppedUntilStep = -1  # Sentinel for deferred init

proc clearAgentStop*(controller: Controller, agentId: int) =
  ## Clear the stopped state for an agent, allowing normal behavior to resume.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].stoppedActive = false
    controller.agents[agentId].stoppedUntilStep = 0

proc isAgentStopped*(controller: Controller, agentId: int): bool =
  ## Check if an agent is currently in stopped state.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].stoppedActive
  false

proc getAgentStoppedUntilStep*(controller: Controller, agentId: int): int32 =
  ## Get the step at which the stopped state will expire.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].stoppedUntilStep
  0

# Stance API - Controller-level procs for setting/getting agent stance.
# Stance is stored on the agent (Thing) but we use AgentState.pendingStance
# for deferred application when we have env access in decideAction.

proc setAgentStanceDeferred*(controller: Controller, agentId: int, stance: AgentStance) =
  ## Set pending stance for an agent. Applied in decideAction when we have env access.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].pendingStance = stance
    controller.agents[agentId].stanceModified = true

proc getAgentPendingStance*(controller: Controller, agentId: int): AgentStance =
  ## Get the pending stance for an agent (what will be applied on next decideAction).
  ## Returns StanceDefensive if no stance has been set or if agentId is invalid.
  if agentId >= 0 and agentId < MapAgents:
    if controller.agents[agentId].stanceModified:
      return controller.agents[agentId].pendingStance
  StanceDefensive

proc isAgentStanceModified*(controller: Controller, agentId: int): bool =
  ## Check if agent has a pending stance modification.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].stanceModified
  false

proc clearAgentStanceModified*(controller: Controller, agentId: int) =
  ## Clear the stance modified flag after applying the stance.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].stanceModified = false

