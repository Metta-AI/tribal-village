# This file is included by src/external.nim
proc findAdjacentBuildTile(env: Environment, pos: IVec2, preferDir: IVec2): IVec2 =
  ## Find an empty adjacent tile for building, preferring the provided direction.
  let dirs = @[
    preferDir,
    ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
    ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)
  ]
  for d in dirs:
    if d.x == 0 and d.y == 0:
      continue
    let candidate = pos + d
    if not isValidPos(candidate):
      continue
    if not env.canPlaceBuilding(candidate):
      continue
    # Avoid building on roads so they stay clear for traffic.
    if env.terrain[candidate.x][candidate.y] == TerrainRoad:
      continue
    return candidate
  return ivec2(-1, -1)

proc tryBuildAction(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState, teamId: int, index: int): tuple[did: bool, action: uint8] =
  if index < 0 or index >= BuildChoices.len:
    return (false, 0'u8)
  let key = BuildChoices[index]
  if not env.canAffordBuild(teamId, key):
    return (false, 0'u8)
  let buildPos = findAdjacentBuildTile(env, agent.pos, orientationToVec(agent.orientation))
  if buildPos.x < 0:
    return (false, 0'u8)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(8'u8, index.uint8)))

proc tryBuildIfMissing(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, teamId: int, kind: ThingKind): tuple[did: bool, action: uint8] =
  if controller.getBuildingCount(env, teamId, kind) == 0:
    let idx = buildIndexFor(kind)
    if idx >= 0:
      return tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
  (false, 0'u8)

proc goToAdjacentAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                          state: var AgentState, targetPos: IVec2,
                          buildIndex: int): tuple[did: bool, action: uint8] =
  if targetPos.x < 0:
    return (false, 0'u8)
  let dir = ivec2(signi(targetPos.x - agent.pos.x), signi(targetPos.y - agent.pos.y))
  if chebyshevDist(agent.pos, targetPos) == 1'i32 and
      agent.orientation == Orientation(vecToOrientation(dir)):
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, getTeamId(agent.agentId), buildIndex)
    if did: return (true, act)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8)))

proc goToStandAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, standPos, targetPos: IVec2,
                       buildIndex: int): tuple[did: bool, action: uint8] =
  if standPos.x < 0:
    return (false, 0'u8)
  if agent.pos == standPos:
    let dir = ivec2(signi(targetPos.x - agent.pos.x), signi(targetPos.y - agent.pos.y))
    if agent.orientation == Orientation(vecToOrientation(dir)):
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, getTeamId(agent.agentId), buildIndex)
      if did: return (true, act)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, standPos, controller.rng).uint8)))

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
      stuckCounter: 0,
      escapeMode: false,
      escapeStepsRemaining: 0,
      escapeDirection: ivec2(0, -1)
    )
    for kind in ThingKind:
      initState.cachedThingPos[kind] = ivec2(-1, -1)
    controller.agents[agentId] = initState
    controller.agentsInitialized[agentId] = true

  var state = controller.agents[agentId]

  # --- Simple bail-out and dithering to avoid getting stuck/oscillation ---
  # Update recent positions history (ring buffer size 4)
  state.recentPositions[state.recentPosIndex] = agent.pos
  state.recentPosIndex = (state.recentPosIndex + 1) mod 4
  if state.recentPosCount < 4:
    inc state.recentPosCount

  proc recentAt(offset: int): IVec2 =
    let idx = (state.recentPosIndex - 1 - offset + 4 * 4) mod 4
    state.recentPositions[idx]

  # Detect stuck: same position or simple 2-cycle oscillation
  if state.recentPosCount >= 2 and agent.pos == state.lastPosition:
    inc state.stuckCounter
  elif state.recentPosCount >= 4:
    let p0 = recentAt(0)
    let p1 = recentAt(1)
    let p2 = recentAt(2)
    let p3 = recentAt(3)
    if (p0 == p2 and p1 == p3) or (p0 == p1):
      inc state.stuckCounter
    else:
      state.stuckCounter = 0
  else:
    state.stuckCounter = 0

  # Enter escape mode if stuck
  if not state.escapeMode and state.stuckCounter >= 3:
    state.escapeMode = true
    state.escapeStepsRemaining = 6
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
          state.stuckCounter = 0
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))
    # If all blocked, drop out of escape for this tick
    state.escapeMode = false
    state.stuckCounter = 0

  # Small dithering chance to break deadlocks (lower for gatherers to stay focused)
  let ditherChance = if state.role == Gatherer: 0.10 else: 0.20
  if randFloat(controller.rng) < ditherChance:
    var candidates = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
                      ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)]
    for i in countdown(candidates.len - 1, 1):
      let j = randIntInclusive(controller.rng, 0, i)
      let tmp = candidates[i]
      candidates[i] = candidates[j]
      candidates[j] = tmp
    for d in candidates:
      if isPassable(env, agent, agent.pos + d):
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))

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
        return saveStateAndReturn(
          controller, agentId, state,
          encodeAction(3'u8, neighborDirIndex(agent.pos, target).uint8))

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
