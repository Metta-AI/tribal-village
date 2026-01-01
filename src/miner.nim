proc decideMiner(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  # Keep ore flowing from mines
  if agent.inventoryOre < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Mine)
    if did: return act

  # Offload ore at converters when full
  if agent.inventoryOre > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Converter)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
