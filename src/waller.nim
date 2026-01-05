proc signi(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

proc decideWaller(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let altar = agent.homeAltar
  if altar.x < 0:
    return controller.moveNextSearch(env, agent, agentId, state)

  const WallRadius = 5

  var target = ivec2(-1, -1)
  for dx in -WallRadius .. WallRadius:
    for dy in -WallRadius .. WallRadius:
      if max(abs(dx), abs(dy)) != WallRadius:
        continue
      let pos = altar + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if env.hasDoor(pos) or not env.isEmpty(pos):
        continue
      if isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
        continue
      target = pos
      break
    if target.x >= 0:
      break

  if target.x < 0:
    return controller.moveNextSearch(env, agent, agentId, state)

  let dir = ivec2(signi(target.x - altar.x), signi(target.y - altar.y))
  let staging = target - dir
  let approach = staging - dir
  let desired = Orientation(vecToOrientation(dir))

  if agent.pos == staging and agent.orientation == desired:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, getTeamId(agent.agentId), BuildIndexWall)
    if did:
      return act

  # Approach from inside so the agent faces outward when placing walls.
  if agent.pos == approach:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, vecToOrientation(dir).uint8))

  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, approach, controller.rng).uint8))
