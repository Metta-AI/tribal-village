proc decideFarmer(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Drop off any gathered food.
  if hasFoodCargo(agent):
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Mill, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Ensure at least one mill exists.
  if env.countTeamBuildings(teamId, Mill) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMill)
    if did: return act

  let targetFertile = 10
  let fertileCount = countFertileEmpty(env, agent.pos, 8)

  # Step 1: Create fertile ground until target reached.
  if fertileCount < targetFertile:
    let wateringPos = findNearestEmpty(env, agent.pos, false, 8)
    if wateringPos.x >= 0:
      if agent.inventoryWater == 0:
        let waterPos = env.findNearestTerrainSpiral(state, Water, controller.rng)
        if waterPos.x >= 0:
          return controller.useOrMove(env, agent, agentId, state, waterPos)
      else:
        let dx = abs(wateringPos.x - agent.pos.x)
        let dy = abs(wateringPos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(3'u8, neighborDirIndex(agent.pos, wateringPos).uint8))
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, wateringPos, controller.rng).uint8))
    return controller.moveNextSearch(env, agent, agentId, state)

  # Step 2: Plant on fertile tiles if holding resources.
  block planting:
    let (didPlant, act) = tryPlantOnFertile(controller, env, agent, agentId, state)
    if didPlant:
      return act

  # Step 3: Gather resources to plant (wood then wheat).
  if agent.inventoryWood == 0:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
    if did: return act
  if agent.inventoryWheat == 0:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
