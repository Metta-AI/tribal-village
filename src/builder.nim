proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                   agentId: int, state: var AgentState): uint8 =
  let home = agent.homeAltar
  let hasHome = home.x >= 0
  let teamId = getTeamId(agent.agentId)

  if not state.builderHasOutpost:
    if env.stockpileCount(teamId, ResourceWood) < OutpostWoodCost:
      if agent.inventoryWood > 0:
        let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, TownCenter)
        if did: return act
      let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
      if did: return act

    if hasHome and not isOutOfSight(agent):
      let awayDir = getMoveAway(env, agent, agent.pos, home, controller.rng)
      return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

    let dx = if hasHome and agent.pos.x != home.x: (if agent.pos.x > home.x: 1'i32 else: -1'i32) else: 0'i32
    let dy = if hasHome and agent.pos.y != home.y: (if agent.pos.y > home.y: 1'i32 else: -1'i32) else: 0'i32
    let buildPos = findAdjacentBuildTile(env, agent.pos, ivec2(dx, dy))
    if buildPos.x >= 0:
      state.builderHasOutpost = true
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(8'u8, BuildIndexOutpost.uint8))

    return controller.moveNextSearch(env, agent, agentId, state)

  # After outpost is built, build roads toward home (stockpile-backed).
  if env.stockpileCount(teamId, ResourceWood) == 0:
    if agent.inventoryWood > 0:
      let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, TownCenter)
      if did: return act
    let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
    if did: return act

  if hasHome:
    return controller.buildRoadToward(env, agent, agentId, state, home)

  let buildPos = findAdjacentBuildTile(env, agent.pos, ivec2(0, 0))
  if buildPos.x >= 0:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(6'u8, neighborDirIndex(agent.pos, buildPos).uint8))
  return controller.moveNextSearch(env, agent, agentId, state)
