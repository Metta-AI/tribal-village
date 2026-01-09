# This file is included by src/external.nim
proc tryBuildAction(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState, teamId: int, index: int): tuple[did: bool, action: uint8] =
  if index < 0 or index >= BuildChoices.len:
    return (false, 0'u8)
  let key = BuildChoices[index]
  if not env.canAffordBuild(teamId, key):
    return (false, 0'u8)
  block findBuildPos:
    ## Find an empty adjacent tile for building, preferring the provided direction.
    let preferDir = orientationToVec(agent.orientation)
    let dirs = @[
      preferDir,
      ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
      ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)
    ]
    var buildPos = ivec2(-1, -1)
    for d in dirs:
      if d.x == 0 and d.y == 0:
        continue
      let candidate = agent.pos + d
      if not isValidPos(candidate):
        continue
      if not env.canPlaceBuilding(candidate):
        continue
      # Avoid building on roads so they stay clear for traffic.
      if env.terrain[candidate.x][candidate.y] == TerrainRoad:
        continue
      buildPos = candidate
      break
    if buildPos.x < 0:
      return (false, 0'u8)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(8'u8, index.uint8)))

proc goToAdjacentAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                          state: var AgentState, targetPos: IVec2,
                          buildIndex: int): tuple[did: bool, action: uint8] =
  if targetPos.x < 0:
    return (false, 0'u8)
  if buildIndex < 0 or buildIndex >= BuildChoices.len:
    return (false, 0'u8)
  let teamId = getTeamId(agent.agentId)
  let key = BuildChoices[buildIndex]
  if not env.canAffordBuild(teamId, key):
    return (false, 0'u8)
  if not env.canPlaceBuilding(targetPos):
    return (false, 0'u8)
  if env.terrain[targetPos.x][targetPos.y] == TerrainRoad:
    return (false, 0'u8)
  if chebyshevDist(agent.pos, targetPos) == 1'i32:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, buildIndex)
    if did: return (true, act)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8)))

proc goToStandAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, standPos, targetPos: IVec2,
                       buildIndex: int): tuple[did: bool, action: uint8] =
  if standPos.x < 0:
    return (false, 0'u8)
  if buildIndex < 0 or buildIndex >= BuildChoices.len:
    return (false, 0'u8)
  let teamId = getTeamId(agent.agentId)
  let key = BuildChoices[buildIndex]
  if not env.canAffordBuild(teamId, key):
    return (false, 0'u8)
  if not env.canPlaceBuilding(targetPos):
    return (false, 0'u8)
  if env.terrain[targetPos.x][targetPos.y] == TerrainRoad:
    return (false, 0'u8)
  if not isValidPos(standPos) or env.hasDoor(standPos) or
      isBlockedTerrain(env.terrain[standPos.x][standPos.y]) or isTileFrozen(standPos, env) or
      not env.isEmpty(standPos) or not env.canAgentPassDoor(agent, standPos):
    return (false, 0'u8)
  if agent.pos == standPos:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, buildIndex)
    if did: return (true, act)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, standPos, controller.rng).uint8)))

proc tryBuildNearResource(controller: Controller, env: Environment, agent: Thing, agentId: int,
                          state: var AgentState, teamId: int, kind: ThingKind,
                          resourceCount, minResource: int,
                          nearbyKinds: openArray[ThingKind], distanceThreshold: int): tuple[did: bool, action: uint8] =
  if resourceCount < minResource:
    return (false, 0'u8)
  let dist = nearestFriendlyBuildingDistance(env, teamId, nearbyKinds, agent.pos)
  if dist <= distanceThreshold:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx >= 0:
    return tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
  (false, 0'u8)

proc tryBuildCampThreshold(controller: Controller, env: Environment, agent: Thing, agentId: int,
                           state: var AgentState, teamId: int, kind: ThingKind,
                           resourceCount, minResource: int,
                           nearbyKinds: openArray[ThingKind],
                           minSpacing: int = 3,
                           searchRadius: int = 4): tuple[did: bool, action: uint8] =
  ## Build a camp if resource threshold is met and no nearby camp is within minSpacing.
  if resourceCount < minResource:
    return (false, 0'u8)
  let dist = nearestFriendlyBuildingDistance(env, teamId, nearbyKinds, agent.pos)
  if dist <= minSpacing:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx < 0 or idx >= BuildChoices.len:
    return (false, 0'u8)
  let key = BuildChoices[idx]
  if not env.canAffordBuild(teamId, key):
    return (false, 0'u8)
  block findBuildSpotNear:
    ## Find a buildable tile near center plus an adjacent stand tile.
    var buildPos = ivec2(-1, -1)
    var standPos = ivec2(-1, -1)
    let center = agent.pos
    let minX = max(0, center.x - searchRadius)
    let maxX = min(MapWidth - 1, center.x + searchRadius)
    let minY = max(0, center.y - searchRadius)
    let maxY = min(MapHeight - 1, center.y + searchRadius)

    for x in minX .. maxX:
      for y in minY .. maxY:
        let pos = ivec2(x.int32, y.int32)
        if not env.canPlaceBuilding(pos):
          continue
        # Avoid building on roads so they stay clear for traffic.
        if env.terrain[pos.x][pos.y] == TerrainRoad:
          continue
        for d in [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]:
          let stand = pos + d
          if not isValidPos(stand):
            continue
          if env.hasDoor(stand):
            continue
          if isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env):
            continue
          if not env.isEmpty(stand):
            continue
          if not env.canAgentPassDoor(agent, stand):
            continue
          buildPos = pos
          standPos = stand
          break
        if buildPos.x >= 0:
          break
      if buildPos.x >= 0:
        break
    if buildPos.x < 0:
      return (false, 0'u8)
    return goToStandAndBuild(controller, env, agent, agentId, state,
      standPos, buildPos, idx)

proc tryBuildIfMissing(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, teamId: int, kind: ThingKind): tuple[did: bool, action: uint8] =
  if controller.getBuildingCount(env, teamId, kind) != 0:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx < 0:
    return (false, 0'u8)
  let key = BuildChoices[idx]
  let costs = buildCostsForKey(key)
  if costs.len == 0:
    return (false, 0'u8)
  if not env.canSpendStockpile(teamId, costs):
    for cost in costs:
      case cost.res
      of ResourceWood:
        return controller.ensureWood(env, agent, agentId, state)
      of ResourceStone:
        return controller.ensureStone(env, agent, agentId, state)
      of ResourceGold:
        return controller.ensureGold(env, agent, agentId, state)
      of ResourceFood:
        return controller.ensureWheat(env, agent, agentId, state)
      of ResourceWater, ResourceNone:
        discard
    return (false, 0'u8)

  let (didAdjacent, actAdjacent) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
  if didAdjacent:
    return (didAdjacent, actAdjacent)

  let anchor =
    if state.basePosition.x >= 0: state.basePosition
    elif agent.homeAltar.x >= 0: agent.homeAltar
    else: agent.pos

  const searchRadius = 8
  var bestDist = int.high
  var buildPos = ivec2(-1, -1)
  var standPos = ivec2(-1, -1)
  let minX = max(0, anchor.x - searchRadius)
  let maxX = min(MapWidth - 1, anchor.x + searchRadius)
  let minY = max(0, anchor.y - searchRadius)
  let maxY = min(MapHeight - 1, anchor.y + searchRadius)
  let ax = anchor.x.int
  let ay = anchor.y.int
  for x in minX .. maxX:
    for y in minY .. maxY:
      let pos = ivec2(x.int32, y.int32)
      if not env.canPlaceBuilding(pos):
        continue
      if env.terrain[pos.x][pos.y] == TerrainRoad:
        continue
      for d in [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]:
        let stand = pos + d
        if not isValidPos(stand):
          continue
        if env.hasDoor(stand):
          continue
        if isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env):
          continue
        if not env.isEmpty(stand):
          continue
        if not env.canAgentPassDoor(agent, stand):
          continue
        let dist = abs(x - ax) + abs(y - ay)
        if dist < bestDist:
          bestDist = dist
          buildPos = pos
          standPos = stand
        break
  if buildPos.x >= 0:
    return goToStandAndBuild(controller, env, agent, agentId, state,
      standPos, buildPos, idx)
  return tryBuildAction(controller, env, agent, agentId, state, teamId, idx)

include "gatherer"
include "builder"
include "fighter"
proc decideAction*(controller: Controller, env: Environment, agentId: int): uint8 =
  let agent = env.agents[agentId]

  # Skip inactive agents
  if not isAgentAlive(env, agent):
    return encodeAction(0'u8, 0'u8)

  # Initialize agent role if needed (2 gatherers, 2 builders, 2 fighters)
  if not controller.agentsInitialized[agentId]:
    let role =
      case agentId mod MapAgentsPerVillage
      of 0, 1: Gatherer
      of 2, 3: Builder
      of 4, 5: Fighter
      else:
        sample(controller.rng, [Gatherer, Builder, Fighter])

    var initState = AgentState(
      role: role,
      spiralStepsInArc: 0,
      spiralArcsCompleted: 0,
      spiralClockwise: (agentId mod 2) == 0,
      basePosition: agent.pos,
      lastSearchPosition: agent.pos,
      lastPosition: agent.pos,
      recentPosIndex: 0,
      recentPosCount: 0,
      escapeMode: false,
      escapeStepsRemaining: 0,
      escapeDirection: ivec2(0, -1),
      closestFoodPos: ivec2(-1, -1),
      closestWoodPos: ivec2(-1, -1),
      closestStonePos: ivec2(-1, -1),
      closestGoldPos: ivec2(-1, -1),
      closestMagmaPos: ivec2(-1, -1),
      plannedTarget: ivec2(-1, -1),
      plannedPath: @[],
      plannedPathIndex: 0,
      pathBlockedTarget: ivec2(-1, -1)
    )
    for kind in ThingKind:
      initState.cachedThingPos[kind] = ivec2(-1, -1)
    controller.agents[agentId] = initState
    controller.agentsInitialized[agentId] = true

  var state = controller.agents[agentId]

  # --- Simple bail-out to avoid getting stuck/oscillation ---
  # Update recent positions history (ring buffer size 12)
  state.recentPositions[state.recentPosIndex] = agent.pos
  state.recentPosIndex = (state.recentPosIndex + 1) mod 12
  if state.recentPosCount < 12:
    inc state.recentPosCount

  proc recentAt(offset: int): IVec2 =
    let idx = (state.recentPosIndex - 1 - offset + 12 * 12) mod 12
    state.recentPositions[idx]

  # Enter escape mode if stuck in 1-3 tiles for 10+ steps
  if not state.escapeMode and state.recentPosCount >= 10:
    var uniqueCount = 0
    var unique: array[3, IVec2]
    for i in 0 ..< 10:
      let p = recentAt(i)
      var seen = false
      for j in 0 ..< uniqueCount:
        if unique[j] == p:
          seen = true
          break
      if not seen:
        if uniqueCount < 3:
          unique[uniqueCount] = p
          inc uniqueCount
        else:
          uniqueCount = 4
          break
    if uniqueCount <= 3:
      state.escapeMode = true
      state.escapeStepsRemaining = 10
      state.recentPosCount = 0
      state.recentPosIndex = 0
      # Choose an escape direction: prefer any empty cardinal, shuffled
      var dirs = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]
      for i in countdown(dirs.len - 1, 1):
        let j = randIntInclusive(controller.rng, 0, i)
        let tmp = dirs[i]
        dirs[i] = dirs[j]
        dirs[j] = tmp
      var chosen = ivec2(0, -1)
      for d in dirs:
        if isPassable(env, agent, agent.pos + d):
          chosen = d
          break
      state.escapeDirection = chosen

  # If in escape mode, try to move in escape direction for a few steps
  if state.escapeMode and state.escapeStepsRemaining > 0:
    let tryDirs = [state.escapeDirection,
                   ivec2(state.escapeDirection.y, -state.escapeDirection.x),  # perpendicular 1
                   ivec2(-state.escapeDirection.y, state.escapeDirection.x),  # perpendicular 2
                   ivec2(-state.escapeDirection.x, -state.escapeDirection.y)] # opposite
    for d in tryDirs:
      let np = agent.pos + d
      if isPassable(env, agent, np):
        dec state.escapeStepsRemaining
        if state.escapeStepsRemaining <= 0:
          state.escapeMode = false
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))
    # If all blocked, drop out of escape for this tick
    state.escapeMode = false

  # From here on, ensure lastPosition is updated this tick regardless of branch
  state.lastPosition = agent.pos
  # Anchor spiral search around home altar when possible (common base-centric search)
  if agent.homeAltar.x >= 0:
    state.basePosition = agent.homeAltar
  else:
    state.basePosition = agent.pos

  # Emergency self-heal: eat bread if below half HP (applies to all roles)
  if agent.inventoryBread > 0 and agent.hp * 2 < agent.maxHp:
    let healDirs = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),  # cardinals first
                    ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)] # diagonals
    for d in healDirs:
      let target = agent.pos + d
      if not env.hasDoor(target) and
          target.x >= 0 and target.x < MapWidth and
          target.y >= 0 and target.y < MapHeight and
          env.isEmpty(target) and
          not isBlockedTerrain(env.terrain[target.x][target.y]) and
          env.canAgentPassDoor(agent, target):
        let dirIdx = neighborDirIndex(agent.pos, target)
        return saveStateAndReturn(
          controller, agentId, state,
          encodeAction(3'u8, dirIdx.uint8))

  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  # Role-based decision making
  case state.role:
  of Gatherer: return decideGatherer(controller, env, agent, agentId, state)
  of Builder: return decideBuilder(controller, env, agent, agentId, state)
  of Fighter: return decideFighter(controller, env, agent, agentId, state)

# Compatibility function for updateController
proc updateController*(controller: Controller) =
  # No complex state to update - keep it simple
  discard
