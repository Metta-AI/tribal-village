proc decideArmorer(controller: Controller, env: Environment, agent: Thing,
                   agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Priority 1: Train into a melee unit if still a villager.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)

  # Priority 2: Trigger blacksmith upgrades when available.
  let blacksmith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
  if blacksmith != nil:
    return controller.useOrMove(env, agent, agentId, state, blacksmith.pos)

  # Priority 3: Drop off any carried wood for the team stockpile.
  if agent.inventoryWood > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Priority 4: Collect wood for stockpile.
  let (did, act) = controller.findAndHarvestThing(env, agent, agentId, state, TreeObject)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
