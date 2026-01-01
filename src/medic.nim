proc decideMedic(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  if agent.inventoryBread > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedBread)
    if teammate != nil:
      let dx = abs(teammate.pos.x - agent.pos.x)
      let dy = abs(teammate.pos.y - agent.pos.y)
      if max(dx, dy) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

  if agent.inventoryWheat > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, ClayOven)
    if did: return act

  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
