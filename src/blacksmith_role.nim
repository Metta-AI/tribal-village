proc decideSmith(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # If carrying armor, deliver it to teammates who need it.
  if agent.inventoryArmor > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedArmor)
    if teammate != nil:
      let dx = abs(teammate.pos.x - agent.pos.x)
      let dy = abs(teammate.pos.y - agent.pos.y)
      if max(dx, dy) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

  # Craft armor at armory when possible.
  if agent.inventoryWood > 0:
    let armory = env.findNearestFriendlyThingSpiral(state, teamId, Armory, controller.rng)
    if armory != nil:
      return controller.useOrMove(env, agent, agentId, state, armory.pos)

  # Otherwise gather wood for armor crafting.
  let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
  if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
