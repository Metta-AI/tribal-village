proc decideScout(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  let home = agent.homeassembler
  let hasHome = home.x >= 0

  let threat = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if threat != nil and chebyshevDist(agent.pos, threat.pos) <= 4:
    let awayDir = getMoveAway(env, agent, agent.pos, threat.pos, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

  if hasHome and not isOutOfSight(agent):
    let awayDir = getMoveAway(env, agent, agent.pos, home, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

  return controller.moveNextSearch(env, agent, agentId, state)
