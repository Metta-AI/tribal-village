proc decideBrewer(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  # Priority 1: Brew drinks when carrying growth + water
  if getInv(agent, ItemPlantGrowth) > 0 and agent.inventoryWater > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, ClayOven)
    if did: return act

  # Priority 2: Gather plant growth from bushes
  if getInv(agent, ItemPlantGrowth) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Bush)
    if did: return act

  let wateringPos = findNearestEmpty(env, agent.pos, false, 8)
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
    return controller.moveNextSearch(env, agent, agentId, state)

  if wateringPos.x >= 0:
    let dx = abs(wateringPos.x - agent.pos.x)
    let dy = abs(wateringPos.y - agent.pos.y)
    if max(dx, dy) == 1'i32:
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(3'u8, neighborDirIndex(agent.pos, wateringPos).uint8))
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, wateringPos, controller.rng).uint8))

  return controller.moveNextSearch(env, agent, agentId, state)
