proc decideMiner(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # AoE mining cycle: collect gold/stone and drop off at mining camps / town centers.
  if agent.inventoryGold > 0 or agent.inventoryStone > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Work gold/stone deposits when capacity allows.
  if agent.inventoryGold + agent.inventoryStone < ResourceCarryCapacity:
    let preferGold = agent.inventoryGold <= agent.inventoryStone
    let primaryTerrain = if preferGold: TerrainType.Gold else: TerrainType.Rock
    var targetPos = env.findNearestTerrainSpiral(state, primaryTerrain, controller.rng)
    if targetPos.x < 0:
      let secondaryTerrain = if primaryTerrain == TerrainType.Gold: TerrainType.Rock else: TerrainType.Gold
      targetPos = env.findNearestTerrainSpiral(state, secondaryTerrain, controller.rng)
    if targetPos.x >= 0:
      return controller.useOrMove(env, agent, agentId, state, targetPos)

  return controller.moveNextSearch(env, agent, agentId, state)
