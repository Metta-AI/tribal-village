proc decideArmorer(controller: Controller, env: Environment, agent: Thing,
                   agentId: int, state: var AgentState): uint8 =
  # Priority 1: If we have armor, deliver it to teammates who need it
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

  # Priority 2: Craft armor if we have wood
  if agent.inventoryWood > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Armory)
    if did: return act

  # Priority 3: Collect wood
  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
