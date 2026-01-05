proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Train into a combat unit when possible.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)

  # Keep armor topped up.
  if agent.inventoryArmor < ArmorPoints:
    let armory = env.findNearestFriendlyThingSpiral(state, teamId, Armory, controller.rng)
    if armory != nil:
      return controller.useOrMove(env, agent, agentId, state, armory.pos)

  # If spear charges are empty, try to resupply at a blacksmith.
  if agent.unitClass == UnitManAtArms and agent.inventorySpear == 0:
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Primary target: tumors.
  let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if tumor != nil:
    return controller.useOrMove(env, agent, agentId, state, tumor.pos)

  # Secondary: hunt nearby animals for food while patrolling.
  let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
  if didCow: return actCow
  let (didAnimal, actAnimal) = controller.findAndHarvest(env, agent, agentId, state, Animal)
  if didAnimal: return actAnimal

  return controller.moveNextSearch(env, agent, agentId, state)
