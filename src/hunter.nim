proc decideHunter(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Drop off food at a friendly mill or town center.
  if hasFoodCargo(agent):
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Mill, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  if agent.inventoryWood > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Priority 2: If a nearby tumor exists, retreat
  let nearbyTumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if nearbyTumor != nil and chebyshevDist(agent.pos, nearbyTumor.pos) <= 3:
    let awayDir = getMoveAway(env, agent, agent.pos, nearbyTumor.pos, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

  # Priority 3: Harvest nearby cows
  let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
  if didCow: return actCow

  # Priority 3: Hunt wildlife for food when available
  if getInv(agent, ItemFish) < MapObjectAgentMaxInventory:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Animal)
    if did: return act

  # Priority 4: Collect wood
  let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
