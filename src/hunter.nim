proc decideWarrior(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Train into a basic melee unit when possible (grants spear charges).
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)
    return controller.moveNextSearch(env, agent, agentId, state)

  # If out of spears, try to re-arm at the blacksmith.
  if agent.inventorySpear == 0:
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)
    return controller.moveNextSearch(env, agent, agentId, state)

  # Hunt tumors with spear attacks.
  let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if tumor != nil:
    let orientIdx = spearAttackDir(agent.pos, tumor.pos)
    if orientIdx >= 0:
      return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, orientIdx.uint8))
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, tumor.pos, controller.rng).uint8))

  return controller.moveNextSearch(env, agent, agentId, state)
