proc decideMiner(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Drop off mined resources at a friendly mining camp or town center.
  if agent.inventoryGold > 0 or agent.inventoryStone > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Keep mines working for gold/stone.
  if agent.inventoryGold + agent.inventoryStone < ResourceCarryCapacity:
    let mine = env.findNearestThingSpiral(state, Mine, controller.rng)
    if mine != nil:
      return controller.useOrMove(env, agent, agentId, state, mine.pos)

  # Harvest rock terrain when available.
  if getInv(agent, ItemRock) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Rock)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
