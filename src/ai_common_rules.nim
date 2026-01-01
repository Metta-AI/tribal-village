# This file is included by ai_policies_default before role files.

proc isOutOfSight(agent: Thing): bool =
  ## Out of sight if beyond observation radius from home assembler.
  if agent.homeassembler.x < 0:
    return true
  chebyshevDist(agent.pos, agent.homeassembler) > ObservationRadius.int32

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
    if env.terrain[candidate.x][candidate.y] != TerrainEmptyVal:
      continue
    if isTileFrozen(candidate, env):
      continue
    return candidate
  return ivec2(-1, -1)

proc buildRoadToward(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState, targetPos: IVec2): uint8 =
  ## Try to place a road on the next step toward target; otherwise move toward it.
  let dirIdx = neighborDirIndex(agent.pos, targetPos)
  let step = agent.pos + orientationToVec(Orientation(dirIdx))
  if isValidPos(step) and env.isEmpty(step) and not env.hasDoor(step) and
     env.terrain[step.x][step.y] == TerrainEmptyVal and not isTileFrozen(step, env):
    return saveStateAndReturn(controller, agentId, state, encodeAction(6'u8, dirIdx.uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8))
