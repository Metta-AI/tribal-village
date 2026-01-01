proc decideFarmer(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let targetFertile = 10
  let fertileCount = countFertileEmpty(env, agent.pos, 8)

  # Step 1: Create fertile ground until target reached
  if fertileCount < targetFertile:
    let wateringPos = findNearestEmpty(env, agent.pos, false, 8)
    if wateringPos.x >= 0:
      if agent.inventoryWater == 0:
        let waterPos = env.findNearestTerrainSpiral(state, Water, controller.rng)
        if waterPos.x >= 0:
          let dx = abs(waterPos.x - agent.pos.x)
          let dy = abs(waterPos.y - agent.pos.y)
          if max(dx, dy) == 1'i32:
            return saveStateAndReturn(controller, agentId, state,
              encodeAction(3'u8, neighborDirIndex(agent.pos, waterPos).uint8))
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, waterPos, controller.rng).uint8))
      else:
        let dx = abs(wateringPos.x - agent.pos.x)
        let dy = abs(wateringPos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(3'u8, neighborDirIndex(agent.pos, wateringPos).uint8))
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, wateringPos, controller.rng).uint8))

    return controller.moveNextSearch(env, agent, agentId, state)

  # Step 2: Plant on fertile tiles if holding resources
  block planting:
    let (didPlant, act) = tryPlantOnFertile(controller, env, agent, agentId, state)
    if didPlant:
      return act

  # Step 3: Gather resources to plant (wood then wheat)
  if agent.inventoryWood == 0:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
    if did: return act

  if agent.inventoryWheat == 0:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if did: return act

  # Step 4: If stocked but couldn't plant, roam to expand search
  return controller.moveNextSearch(env, agent, agentId, state)
