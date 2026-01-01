proc decideMiner(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  # Keep ore flowing from mines
  if agent.inventoryOre < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Mine)
    if did: return act

  # Work raw stone and gems into crafts when carrying them.
  if getInv(agent, ItemBoulder) > 0 or getInv(agent, ItemRough) > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Table)
    if did: return act

  # Offload ore at converters when full
  if agent.inventoryOre > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Converter)
    if did: return act

  # Harvest rock and gem terrain when available
  if getInv(agent, ItemBoulder) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Rock)
    if did: return act
  if getInv(agent, ItemRough) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Gem)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
