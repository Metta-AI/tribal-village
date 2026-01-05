proc decideLighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Place lanterns to extend team tint.
  if agent.inventoryLantern > 0:
    let dirs = @[
      ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
      ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)
    ]
    for d in dirs:
      let target = agent.pos + d
      if not isValidPos(target):
        continue
      if env.hasDoor(target) or not env.isEmpty(target):
        continue
      if isBlockedTerrain(env.terrain[target.x][target.y]) or isTileFrozen(target, env):
        continue
      if env.terrain[target.x][target.y] == Wheat:
        continue
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(6'u8, vecToOrientation(d).uint8))
    return controller.moveNextSearch(env, agent, agentId, state)

  # Turn wheat into lanterns at the weaving loom.
  if agent.inventoryWheat > 0:
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil:
      return controller.useOrMove(env, agent, agentId, state, loom.pos)
    return controller.moveNextSearch(env, agent, agentId, state)

  # Harvest wheat so we can craft lanterns.
  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
