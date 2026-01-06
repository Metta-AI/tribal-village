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
