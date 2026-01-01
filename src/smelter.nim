proc decideSmelter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  if agent.inventoryBattery > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, assembler)
    if did: return act

  if agent.inventoryOre > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Converter)
    if did: return act

  let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Mine)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
