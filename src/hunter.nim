proc decideHunter(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  # Priority 1: Hunt tumors if we have a spear
  if agent.inventorySpear > 0:
    let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
    if tumor != nil:
      let orientIdx = spearAttackDir(agent.pos, tumor.pos)
      if orientIdx >= 0:
        return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, orientIdx.uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, tumor.pos, controller.rng).uint8))
    return controller.moveNextSearch(env, agent, agentId, state)

  # Priority 2: If a nearby tumor exists, retreat
  let nearbyTumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if nearbyTumor != nil and chebyshevDist(agent.pos, nearbyTumor.pos) <= 3:
    let awayDir = getMoveAway(env, agent, agent.pos, nearbyTumor.pos, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

  # Priority 3: Harvest nearby cows
  let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
  if didCow: return actCow

  # Priority 3: Hunt wildlife for meat/leather when available
  if getInv(agent, ItemMeat) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Animal)
    if did: return act

  # Priority 3: Craft spear if we have wood
  if agent.inventoryWood > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Forge)
    if did: return act

  # Priority 4: Collect wood
  let (did, act) = controller.findAndHarvestThing(env, agent, agentId, state, TreeObject)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
