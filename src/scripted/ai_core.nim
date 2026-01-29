# This file is included by src/agent_control.nim
## Simplified AI system - clean and efficient
## Replaces the 1200+ line complex system with ~150 lines
import std/[tables, sets]
import ../entropy
import vmath
import ../environment, ../common, ../terrain
import ai_types
import coordination

# Re-export types from ai_types for backwards compatibility with include chain
export ai_types

const
  CacheMaxAge* = 20  # Invalidate cached positions after this many steps

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
  ## Called periodically from updateController.
  let currentStep = env.currentStep.int32
  let score = env.scoreTerritory()
  let totalTiles = max(1, score.scoredTiles)

  for teamId in 0 ..< MapRoomObjectsTeams:
    if not controller.difficulty[teamId].adaptive:
      continue
    # Only check periodically
    let lastCheck = controller.difficulty[teamId].lastAdaptiveCheck
    if currentStep - lastCheck < AdaptiveCheckInterval:
      continue

    controller.difficulty[teamId].lastAdaptiveCheck = currentStep
    let teamTiles = score.teamTiles[teamId]
    let territoryRatio = float32(teamTiles) / float32(totalTiles)
    let target = controller.difficulty[teamId].adaptiveTarget
    let currentLevel = controller.difficulty[teamId].level

    # Adjust difficulty based on performance vs target
    # If team is doing much better than target (>20% above), increase difficulty
    # If team is doing much worse than target (>20% below), decrease difficulty
    const Threshold = 0.15

    template applyDifficultyLevel(newLevel: DifficultyLevel) =
      ## Reset difficulty config while preserving adaptive settings.
      if newLevel != currentLevel:
        let savedAdaptive = controller.difficulty[teamId].adaptive
        let savedTarget = controller.difficulty[teamId].adaptiveTarget
        controller.difficulty[teamId] = defaultDifficultyConfig(newLevel)
        controller.difficulty[teamId].adaptive = savedAdaptive
        controller.difficulty[teamId].adaptiveTarget = savedTarget
        controller.difficulty[teamId].lastAdaptiveCheck = currentStep

    if territoryRatio > target + Threshold:
      # Team is doing too well - increase difficulty
      let newLevel = case currentLevel
        of DiffEasy: DiffNormal
        of DiffNormal: DiffHard
        of DiffHard: DiffBrutal
        of DiffBrutal: DiffBrutal
      applyDifficultyLevel(newLevel)

    elif territoryRatio < target - Threshold:
      # Team is struggling - decrease difficulty
      let newLevel = case currentLevel
        of DiffEasy: DiffEasy
        of DiffNormal: DiffEasy
        of DiffHard: DiffNormal
        of DiffBrutal: DiffHard
      applyDifficultyLevel(newLevel)

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
  let x = vec.x
  let y = vec.y
  if x == 0'i32 and y == -1'i32: return 0  # N
  elif x == 0'i32 and y == 1'i32: return 1  # S
  elif x == -1'i32 and y == 0'i32: return 2 # W
  elif x == 1'i32 and y == 0'i32: return 3  # E
  elif x == -1'i32 and y == -1'i32: return 4 # NW
  elif x == 1'i32 and y == -1'i32: return 5  # NE
  elif x == -1'i32 and y == 1'i32: return 6  # SW
  elif x == 1'i32 and y == 1'i32: return 7   # SE
  else: return 0

proc signi*(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

proc chebyshevDist*(a, b: IVec2): int32 =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  return (if dx > dy: dx else: dy)

# ============================================================================
# Fog of War / Revealed Map Functions (AoE2-style exploration tracking)
# ============================================================================

proc revealTilesInRange*(env: Environment, teamId: int, center: IVec2, radius: int) =
  ## Mark tiles within radius of center as revealed for the specified team.
  ## Uses Chebyshev distance (square vision area) matching the game's standard.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  for dx in -radius .. radius:
    let worldX = center.x + dx
    if worldX < 0 or worldX >= MapWidth:
      continue
    for dy in -radius .. radius:
      let worldY = center.y + dy
      if worldY < 0 or worldY >= MapHeight:
        continue
      env.revealedMaps[teamId][worldX][worldY] = true

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

proc clearAllRevealedMaps*(env: Environment) =
  ## Clear revealed maps for all teams.
  for teamId in 0 ..< MapRoomObjectsTeams:
    env.clearRevealedMap(teamId)

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

# ============================================================================
# End Fog of War Functions
# ============================================================================

# ============================================================================
# Shared Threat Map Functions
# ============================================================================

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
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  # Scouts have extended vision range for both threat detection and exploration
  let visionRange = if agent.unitClass == UnitScout:
    ScoutVisionRange
  else:
    ThreatVisionRange

  # Update fog of war - reveal tiles in vision range
  env.updateRevealedMapFromVision(agent)

  # Scan for enemy agents within vision range using spatial index
  let vr = visionRange.int
  block scanEnemies:
    let (cx, cy) = cellCoords(agent.pos)
    let clampedMax = min(vr, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
    let cellRadius = (clampedMax + SpatialCellSize - 1) div SpatialCellSize
    for ddx in -cellRadius .. cellRadius:
      for ddy in -cellRadius .. cellRadius:
        let nx = cx + ddx
        let ny = cy + ddy
        if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
          continue
        for other in env.spatialIndex.kindCells[Agent][nx][ny]:
          if other.isNil or not isAgentAlive(env, other):
            continue
          let otherTeam = getTeamId(other)
          if otherTeam == teamId or otherTeam < 0:
            continue
          let dist = chebyshevDist(agent.pos, other.pos)
          if dist <= visionRange:
            var strength: int32 = 1
            case other.unitClass
            of UnitKnight: strength = 3
            of UnitManAtArms: strength = 2
            of UnitArcher: strength = 2
            of UnitMangonel: strength = 4
            of UnitTrebuchet: strength = 5
            of UnitMonk: strength = 1
            else: strength = 1
            controller.reportThreat(teamId, other.pos, strength, currentStep,
                                    agentId = other.agentId.int32, isStructure = false)

  # Scan for enemy structures within vision range using spatial index
  let (cx, cy) = cellCoords(agent.pos)
  let cellRadius = (vr + SpatialCellSize - 1) div SpatialCellSize
  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue
      for thing in env.spatialIndex.cells[nx][ny].things:
        if thing.isNil or not isBuildingKind(thing.kind):
          continue
        if thing.teamId < 0 or thing.teamId == teamId:
          continue  # Skip neutral and friendly
        let dist = chebyshevDist(agent.pos, thing.pos)
        if dist <= visionRange:
          # Calculate threat strength based on building type
          var strength: int32 = 1
          case thing.kind
          of Castle: strength = 5
          of GuardTower: strength = 3
          of Barracks, ArcheryRange, Stable: strength = 2
          else: strength = 1
          controller.reportThreat(teamId, thing.pos, strength, currentStep,
                                  agentId = -1, isStructure = true)

# ============================================================================
# End Shared Threat Map Functions
# ============================================================================

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
  let clockwise = state.spiralClockwise
  let arcLen = (state.spiralArcsCompleted div 2) + 1
  var direction = state.spiralArcsCompleted mod 4
  if not clockwise:
    case direction
    of 1: direction = 3
    of 3: direction = 1
    else: discard
  let delta = case direction
    of 0: ivec2(0, -1)  # North
    of 1: ivec2(1, 0)   # East
    of 2: ivec2(0, 1)   # South
    else: ivec2(-1, 0)  # West

  let nextPos = clampToPlayable(state.lastSearchPosition + delta)
  state.lastSearchPosition = nextPos
  state.spiralStepsInArc += 1
  if state.spiralStepsInArc > arcLen:
    state.spiralArcsCompleted += 1
    state.spiralStepsInArc = 1
    if state.spiralArcsCompleted > 100:
      state.spiralArcsCompleted = 0
      state.spiralStepsInArc = 1
      # Continue from the current area.
      state.basePosition = state.lastSearchPosition
  result = state.lastSearchPosition

proc findNearestThing*(env: Environment, pos: IVec2, kind: ThingKind,
                      maxDist: int = SearchRadius): Thing =
  ## Find nearest thing of a kind using spatial index for O(1) cell lookup
  findNearestThingSpatial(env, pos, kind, maxDist)

proc radiusBounds*(center: IVec2, radius: int): tuple[startX, endX, startY, endY: int] {.inline.} =
  let cx = center.x.int
  let cy = center.y.int
  (max(0, cx - radius), min(MapWidth - 1, cx + radius),
   max(0, cy - radius), min(MapHeight - 1, cy + radius))

proc findNearestWater*(env: Environment, pos: IVec2): IVec2 =
  result = ivec2(-1, -1)
  let (startX, endX, startY, endY) = radiusBounds(pos, SearchRadius)
  let cx = pos.x.int
  let cy = pos.y.int
  var minDist = int.high
  for x in startX .. endX:
    for y in startY .. endY:
      if abs(x - cx) + abs(y - cy) >= SearchRadius:
        continue
      if env.terrain[x][y] != Water:
        continue
      let pos = ivec2(x.int32, y.int32)
      if isTileFrozen(pos, env):
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < minDist:
        minDist = dist
        result = pos

proc findNearestFriendlyThing*(env: Environment, pos: IVec2, teamId: int, kind: ThingKind): Thing =
  ## Find nearest team-owned thing using spatial index for O(1) cell lookup
  findNearestFriendlyThingSpatial(env, pos, teamId, kind, SearchRadius)

proc findNearestThingSpiral*(env: Environment, state: var AgentState, kind: ThingKind): Thing =
  ## Find nearest thing using spiral search pattern - more systematic than random search
  let cachedPos = state.cachedThingPos[kind]
  if cachedPos.x >= 0:
    # Invalidate cache if too old (step-based staleness)
    let cacheAge = env.currentStep - state.cachedThingStep[kind]
    if cacheAge < CacheMaxAge and
       abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      let cachedThing = env.getThing(cachedPos)
      if not isNil(cachedThing) and cachedThing.kind == kind and
         hasHarvestableResource(cachedThing):
        return cachedThing
    state.cachedThingPos[kind] = ivec2(-1, -1)

  # First check immediate area around current position
  result = findNearestThing(env, state.lastSearchPosition, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
    state.cachedThingStep[kind] = env.currentStep
    return result

  # Also check around agent's current position before advancing spiral
  result = findNearestThing(env, state.basePosition, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
    state.cachedThingStep[kind] = env.currentStep
    return result

  # If not found, advance spiral search (multiple steps) to cover ground faster
  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)

  # Search from new spiral position
  result = findNearestThing(env, nextSearchPos, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
    state.cachedThingStep[kind] = env.currentStep
  return result

proc findNearestWaterSpiral*(env: Environment, state: var AgentState): IVec2 =
  let cachedPos = state.cachedWaterPos
  if cachedPos.x >= 0:
    let cacheAge = env.currentStep - state.cachedWaterStep
    if cacheAge < CacheMaxAge and
       abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      if env.terrain[cachedPos.x][cachedPos.y] == Water and not isTileFrozen(cachedPos, env):
        return cachedPos
    state.cachedWaterPos = ivec2(-1, -1)

  result = findNearestWater(env, state.lastSearchPosition)
  if result.x >= 0:
    state.cachedWaterPos = result
    state.cachedWaterStep = env.currentStep
    return result

  result = findNearestWater(env, state.basePosition)
  if result.x >= 0:
    state.cachedWaterPos = result
    state.cachedWaterStep = env.currentStep
    return result

  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)
  result = findNearestWater(env, nextSearchPos)
  if result.x >= 0:
    state.cachedWaterPos = result
    state.cachedWaterStep = env.currentStep
  return result

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
  result = int.high
  for thing in env.things:
    if thing.teamId != teamId:
      continue
    var matches = false
    for kind in kinds:
      if thing.kind == kind:
        matches = true
        break
    if not matches:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < result:
      result = dist

proc getBuildingCount*(controller: Controller, env: Environment, teamId: int, kind: ThingKind): int =
  if controller.buildingCountsStep != env.currentStep:
    controller.buildingCountsStep = env.currentStep
    controller.buildingCounts = default(array[MapRoomObjectsTeams, array[ThingKind, int]])
    # Clear claimed buildings at start of new step - claims are per-step to prevent
    # multiple builders from trying to build the same building type in the same step
    controller.claimedBuildings = default(array[MapRoomObjectsTeams, set[ThingKind]])
    for thing in env.things:
      if thing.isNil:
        continue
      if not isBuildingKind(thing.kind):
        continue
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

proc canAffordBuild*(env: Environment, agent: Thing, key: ItemKey): bool =
  let costs = buildCostsForKey(key)
  choosePayment(env, agent, costs) != PayNone


proc neighborDirIndex*(fromPos, toPos: IVec2): int =
  ## Orientation index (0..7) toward adjacent target (includes diagonals)
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  return vecToOrientation(ivec2(
    (if dx > 0: 1'i32 elif dx < 0: -1'i32 else: 0'i32).int,
    (if dy > 0: 1'i32 elif dy < 0: -1'i32 else: 0'i32).int
  ))


proc sameTeam*(agentA, agentB: Thing): bool =
  getTeamId(agentA) == getTeamId(agentB)

proc getBasePos*(agent: Thing): IVec2 =
  ## Return the agent's home altar position if valid, otherwise the agent's current position.
  if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos

proc findAttackOpportunity*(env: Environment, agent: Thing): int =
  ## Return attack orientation index if a valid target is in reach, else -1.
  ## Simplified: pick the closest aligned target within range using a priority order.
  ## Respects agent stance: StanceNoAttack disables auto-attacking.
  ##
  ## Optimized: scans 8 attack lines (cardinal+diagonal) out to maxRange
  ## instead of iterating all env.things. Cost: O(8 * maxRange) = O(48) max.
  if agent.unitClass == UnitMonk:
    return -1
  # NoAttack stance never auto-attacks
  if agent.stance == StanceNoAttack:
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

  # Scan along 8 directions (cardinal + diagonal) up to maxRange
  for dirIdx in 0 .. 7:
    let d = Directions8[dirIdx]
    for step in 1 .. maxRange:
      let tx = agent.pos.x + d.x * step
      let ty = agent.pos.y + d.y * step
      if tx < 0 or tx >= MapWidth or ty < 0 or ty >= MapHeight:
        break

      # Check blocking grid (agents, buildings)
      let gridThing = env.grid[tx][ty]
      if not gridThing.isNil:
        if gridThing.kind == Agent:
          if isAgentAlive(env, gridThing) and not sameTeam(agent, gridThing):
            let priority = targetPriority(Agent)
            if priority < bestPriority or (priority == bestPriority and step < bestDist):
              bestPriority = priority
              bestDist = step
              bestDir = dirIdx
        elif gridThing.kind in {Tumor, Spawner}:
          let priority = targetPriority(gridThing.kind)
          if priority < bestPriority or (priority == bestPriority and step < bestDist):
            bestPriority = priority
            bestDist = step
            bestDir = dirIdx
        elif gridThing.kind in AttackableStructures:
          if gridThing.teamId != agentTeamId:
            let priority = targetPriority(gridThing.kind)
            if priority < bestPriority or (priority == bestPriority and step < bestDist):
              bestPriority = priority
              bestDist = step
              bestDir = dirIdx

      # Check background grid (non-blocking things like Tumor/Spawner)
      let bgThing = env.backgroundGrid[tx][ty]
      if not bgThing.isNil and bgThing != gridThing:
        if bgThing.kind in {Tumor, Spawner}:
          let priority = targetPriority(bgThing.kind)
          if priority < bestPriority or (priority == bestPriority and step < bestDist):
            bestPriority = priority
            bestDist = step
            bestDir = dirIdx
        elif bgThing.kind in AttackableStructures:
          if bgThing.teamId != agentTeamId:
            let priority = targetPriority(bgThing.kind)
            if priority < bestPriority or (priority == bestPriority and step < bestDist):
              bestPriority = priority
              bestDist = step
              bestDir = dirIdx

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

  template spacingOk(nextPos: IVec2): bool =
    var ok = true
    for t in env.thingsByKind[Lantern]:
      if t != blocker:
        let dist = max(abs(t.pos.x - nextPos.x), abs(t.pos.y - nextPos.y))
        if dist < 3'i32:
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
  ## - Open set is a flat array with linear scan (adequate for the 250-node
  ##   exploration cap; a binary heap would not improve wall-clock time here).
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

  # Initialize open set with starting position
  controller.pathCache.openSetLen = 1
  controller.pathCache.openSet[0] = fromPos
  controller.pathCache.openSetActive[0] = true
  controller.pathCache.inOpenSetGen[fromPos.x][fromPos.y] = gen

  # Initialize gScore and fScore for start
  controller.pathCache.gScoreGen[fromPos.x][fromPos.y] = gen
  controller.pathCache.gScoreVal[fromPos.x][fromPos.y] = 0
  let startH = heuristic(controller.pathCache, fromPos)

  var explored = 0
  while true:
    if explored > 250:
      return @[]

    # Find node in open set with lowest fScore
    var currentIdx = -1
    var current: IVec2
    var bestF = int32.high
    for i in 0 ..< controller.pathCache.openSetLen:
      if not controller.pathCache.openSetActive[i]:
        continue
      let n = controller.pathCache.openSet[i]
      # Calculate fScore: gScore + heuristic
      let g = controller.pathCache.gScoreVal[n.x][n.y]
      let h = heuristic(controller.pathCache, n)
      let f = g + h
      if f < bestF:
        bestF = f
        current = n
        currentIdx = i

    if currentIdx < 0:
      return @[]  # Open set is empty

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

    # Remove current from open set
    controller.pathCache.openSetActive[currentIdx] = false
    inc explored

    # Explore neighbors
    for dirIdx in 0 .. 7:
      let nextPos = current + Directions8[dirIdx]
      if not isValidPos(nextPos):
        continue
      if not canEnterForMove(env, agent, current, nextPos):
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
        # Add to open set if not already there
        if controller.pathCache.inOpenSetGen[nextPos.x][nextPos.y] != gen:
          if controller.pathCache.openSetLen < MaxPathNodes:
            controller.pathCache.openSet[controller.pathCache.openSetLen] = nextPos
            controller.pathCache.openSetActive[controller.pathCache.openSetLen] = true
            inc controller.pathCache.openSetLen
            controller.pathCache.inOpenSetGen[nextPos.x][nextPos.y] = gen

  @[]

proc hasTeamLanternNear*(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.things:
    if thing.kind != Lantern:
      continue
    if not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y)) < 3'i32:
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
  template tryKind(kind: ThingKind): Thing =
    env.findNearestFriendlyThingSpiral(state, teamId, kind)
  case res
  of ResourceFood:
    result = tryKind(Granary)
    if isNil(result):
      result = tryKind(Mill)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceWood:
    result = tryKind(LumberCamp)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceStone:
    result = tryKind(Quarry)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceGold:
    result = tryKind(MiningCamp)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceWater, ResourceNone:
    result = nil
  if isNil(result):
    var bestDist = int.high
    for thing in env.thingsByKind[TownCenter]:
      if thing.teamId != teamId:
        continue
      let dist = int(chebyshevDist(thing.pos, state.basePosition))
      if dist < bestDist:
        bestDist = dist
        result = thing

proc dropoffCarrying*(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState,
                      allowFood: bool = false,
                      allowWood: bool = false,
                      allowStone: bool = false,
                      allowGold: bool = false): tuple[did: bool, action: uint8] =
  ## Unified dropoff function - attempts to drop off resources in priority order
  ## Priority: food -> wood -> gold -> stone
  let teamId = getTeamId(agent)

  # Food dropoff - requires checking inventory for any food items
  if allowFood:
    var hasFood = false
    for key, count in agent.inventory.pairs:
      if count > 0 and isFoodItem(key):
        hasFood = true
        break
    if hasFood:
      let dropoff = findDropoffBuilding(env, state, teamId, ResourceFood, controller.rng)
      if not isNil(dropoff):
        return (true, controller.useOrMoveTo(env, agent, agentId, state, dropoff.pos))

  for entry in [
    (res: ResourceWood, amount: agent.inventoryWood, allowed: allowWood),
    (res: ResourceGold, amount: agent.inventoryGold, allowed: allowGold),
    (res: ResourceStone, amount: agent.inventoryStone, allowed: allowStone)
  ]:
    if not entry.allowed or entry.amount <= 0:
      continue
    let dropoff = findDropoffBuilding(env, state, teamId, entry.res, controller.rng)
    if not isNil(dropoff):
      return (true, controller.useOrMoveTo(env, agent, agentId, state, dropoff.pos))

  (false, 0'u8)

template ensureResourceImpl(closestPos: var IVec2, allowedKinds: set[ThingKind],
                            kinds: openArray[ThingKind]): tuple[did: bool, action: uint8] =
  ## Shared logic for resource-gathering: check cached position, spiral-search
  ## for the nearest resource of the given kinds, then use or move to it.
  block:
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, closestPos, allowedKinds, 3'u8)
    if didKnown:
      (didKnown, actKnown)
    else:
      var found = false
      var foundResult: tuple[did: bool, action: uint8]
      for kind in kinds:
        let target = env.findNearestThingSpiral(state, kind)
        if isNil(target):
          continue
        if target.pos == state.pathBlockedTarget:
          state.cachedThingPos[kind] = ivec2(-1, -1)
          continue
        updateClosestSeen(state, state.basePosition, target.pos, closestPos)
        found = true
        foundResult = (true, controller.useOrMoveTo(env, agent, agentId, state, target.pos))
        break
      if found:
        foundResult
      else:
        (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWood*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestWoodPos, {Stump, Tree}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let teamId = getTeamId(agent)
  for kind in [Stump, Tree]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    # Skip if reserved by another agent
    if isResourceReserved(teamId, target.pos, agentId):
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestWoodPos)
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureStone*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestStonePos, {Stone, Stalagmite}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let teamId = getTeamId(agent)
  for kind in [Stone, Stalagmite]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    # Skip if reserved by another agent
    if isResourceReserved(teamId, target.pos, agentId):
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestStonePos)
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureGold*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestGoldPos, {Gold}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let teamId = getTeamId(agent)
  let target = env.findNearestThingSpiral(state, Gold)
  if not isNil(target):
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[Gold] = ivec2(-1, -1)
      return (true, controller.moveNextSearch(env, agent, agentId, state))
    # Skip if reserved by another agent
    if isResourceReserved(teamId, target.pos, agentId):
      return (true, controller.moveNextSearch(env, agent, agentId, state))
    updateClosestSeen(state, state.basePosition, target.pos, state.closestGoldPos)
    discard reserveResource(teamId, agentId, target.pos, env.currentStep)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWater*(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  if state.closestWaterPos.x >= 0:
    if state.closestWaterPos == state.pathBlockedTarget:
      state.closestWaterPos = ivec2(-1, -1)
    elif env.terrain[state.closestWaterPos.x][state.closestWaterPos.y] != Water or
         isTileFrozen(state.closestWaterPos, env):
      state.closestWaterPos = ivec2(-1, -1)
  if state.closestWaterPos.x >= 0:
    return (true, controller.useOrMoveTo(env, agent, agentId, state, state.closestWaterPos))

  let target = findNearestWaterSpiral(env, state)
  if target.x >= 0:
    if target == state.pathBlockedTarget:
      state.cachedWaterPos = ivec2(-1, -1)
      return (true, controller.moveNextSearch(env, agent, agentId, state))
    updateClosestSeen(state, state.basePosition, target, state.closestWaterPos)
    return (true, controller.useOrMoveTo(env, agent, agentId, state, target))
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

proc switchPatrolDirection*(controller: Controller, agentId: int) =
  ## Switch patrol direction (toggle between heading to point1 and point2).
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolToSecondPoint =
      not controller.agents[agentId].patrolToSecondPoint

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

