proc decideMiner(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Drop off mined resources at a friendly mining camp or town center.
  if agent.inventoryOre > 0 or agent.inventoryStone > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Keep mines working for gold/stone.
  if agent.inventoryOre + agent.inventoryStone < ResourceCarryCapacity:
    let mine = env.findNearestThingSpiral(state, Mine, controller.rng)
    if mine != nil:
      return controller.useOrMove(env, agent, agentId, state, mine.pos)

  # Work raw stone and gems into crafts when carrying them.
  if getInv(agent, ItemBoulder) > 0 or getInv(agent, ItemRough) > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Table)
    if did: return act

  # Harvest rock and gem terrain when available.
  if getInv(agent, ItemBoulder) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Rock)
    if did: return act
  if getInv(agent, ItemRough) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Gem)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
