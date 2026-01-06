# This file is included by defaults before role files.

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
    if env.hasDoor(candidate):
      continue
    if not env.isEmpty(candidate):
      continue
    # Avoid building on roads so they stay clear for traffic.
    if env.terrain[candidate.x][candidate.y] notin {TerrainEmpty, TerrainGrass, TerrainSand, TerrainSnow,
                                                    TerrainDune, TerrainStalagmite, TerrainBridge}:
      continue
    if isTileFrozen(candidate, env):
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

proc tryBuildDoorAction(controller: Controller, env: Environment, agent: Thing, agentId: int,
                        state: var AgentState, teamId: int): tuple[did: bool, action: uint8] =
  if env.teamStockpiles[teamId].counts[ResourceWood] < 1:
    return (false, 0'u8)
  let buildPos = findAdjacentBuildTile(env, agent.pos, orientationToVec(agent.orientation))
  if buildPos.x < 0:
    return (false, 0'u8)
  if env.hasDoor(buildPos):
    return (false, 0'u8)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(8'u8, BuildIndexDoor.uint8)))

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

proc goToAdjacentAndBuildDoor(controller: Controller, env: Environment, agent: Thing, agentId: int,
                              state: var AgentState, targetPos: IVec2): tuple[did: bool, action: uint8] =
  if targetPos.x < 0:
    return (false, 0'u8)
  let dir = ivec2(signi(targetPos.x - agent.pos.x), signi(targetPos.y - agent.pos.y))
  if chebyshevDist(agent.pos, targetPos) == 1'i32 and
      agent.orientation == Orientation(vecToOrientation(dir)):
    let (did, act) = tryBuildDoorAction(controller, env, agent, agentId, state, getTeamId(agent.agentId))
    if did: return (true, act)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8)))
