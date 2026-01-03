proc decideGuard(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  let home = agent.homeAltar
  let hasHome = home.x >= 0
  let teamId = getTeamId(agent.agentId)

  # Train into a basic melee unit when possible.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)

  if hasHome and chebyshevDist(agent.pos, home) > (ObservationRadius.int32 * 2):
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, home, controller.rng).uint8))

  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  if agent.inventorySpear > 0:
    let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
    if tumor != nil:
      let orientIdx = spearAttackDir(agent.pos, tumor.pos)
      if orientIdx >= 0:
        return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, orientIdx.uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, tumor.pos, controller.rng).uint8))

  let (did, act) = controller.findAndHarvestThing(env, agent, agentId, state, TreeObject)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
