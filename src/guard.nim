proc decideGuard(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  let home = agent.homeassembler
  let hasHome = home.x >= 0

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

  if agent.inventoryWood > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Forge)
    if did: return act

  let (did, act) = controller.findAndHarvestThing(env, agent, agentId, state, TreeObject)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
