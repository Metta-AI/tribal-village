proc decideWoodsman(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # AoE wood cycle: gather wood and drop it at lumber camps / town centers.
  if agent.inventoryWood > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return controller.useOrMove(env, agent, agentId, state, dropoff.pos)

  # Collect wood for stockpile.
  let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
