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

  # Harvest wheat.
  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if did: return act

  # Fallback: forage plants for food.
  let (didPlant, actPlant) = controller.findAndHarvest(env, agent, agentId, state, Bush)
  if didPlant: return actPlant

  return controller.moveNextSearch(env, agent, agentId, state)
