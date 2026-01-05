proc decideBlacksmith(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # If carrying bars, work at the blacksmith.
  if agent.inventoryBar > 0:
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Smelt gold into bars at magma.
  if agent.inventoryGold > 0:
    let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
    if magma != nil:
      return controller.useOrMove(env, agent, agentId, state, magma.pos)

  # Otherwise mine gold.
  let goldPos = env.findNearestTerrainSpiral(state, TerrainType.Gold, controller.rng)
  if goldPos.x >= 0:
    return controller.useOrMove(env, agent, agentId, state, goldPos)

  return controller.moveNextSearch(env, agent, agentId, state)
