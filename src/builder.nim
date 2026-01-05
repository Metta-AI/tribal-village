proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Population pressure: build houses when near cap.
  let popCount = env.teamPopCount(teamId)
  let popCap = env.teamPopCap(teamId)
  if popCap > 0 and popCount >= popCap - 1:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexHouse)
    if did: return act

  # Ensure basic dropoff infrastructure exists.
  if env.countTeamBuildings(teamId, Mill) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMill)
    if did: return act
  if env.countTeamBuildings(teamId, LumberCamp) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexLumberCamp)
    if did: return act
  if env.countTeamBuildings(teamId, MiningCamp) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMiningCamp)
    if did: return act

  # Establish core military production and upgrades.
  if env.countTeamBuildings(teamId, Barracks) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexBarracks)
    if did: return act
  if env.countTeamBuildings(teamId, Blacksmith) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexBlacksmith)
    if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
