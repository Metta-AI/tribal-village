proc decideCarpenter(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let home = agent.homeassembler
  let hasHome = home.x >= 0

  if agent.inventoryWood < RoadWoodCost:
    let (did, act) = controller.findAndHarvestThing(env, agent, agentId, state, TreeObject)
    if did: return act

  if hasHome:
    let dist = chebyshevDist(agent.pos, home)
    if dist > ObservationRadius.int32:
      return controller.buildRoadToward(env, agent, agentId, state, home)

  if agent.inventoryWood > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Table)
    if did: return act

  let buildPos = findAdjacentBuildTile(env, agent.pos, ivec2(0, 0))
  if buildPos.x >= 0:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(6'u8, neighborDirIndex(agent.pos, buildPos).uint8))

  return controller.moveNextSearch(env, agent, agentId, state)
