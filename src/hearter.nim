proc decideHearter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  # AoE-style population loop: gold → magma → bar → altar (hearts)
  if agent.inventoryBar > 0:
    for thing in env.things:
      if thing.kind == Altar and thing.pos == agent.homeAltar:
        let dx = abs(thing.pos.x - agent.pos.x)
        let dy = abs(thing.pos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(3'u8, neighborDirIndex(agent.pos, thing.pos).uint8))
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, thing.pos, controller.rng).uint8))

  elif agent.inventoryGold > 0:
    let magmaPool = env.findNearestThingSpiral(state, Magma, controller.rng)
    if magmaPool != nil:
      let dx = abs(magmaPool.pos.x - agent.pos.x)
      let dy = abs(magmaPool.pos.y - agent.pos.y)
      if max(dx, dy) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(3'u8, neighborDirIndex(agent.pos, magmaPool.pos).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, magmaPool.pos, controller.rng).uint8))

    let nextSearchPos = getNextSpiralPoint(state, controller.rng)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))

  else:
    let goldPos = env.findNearestTerrainSpiral(state, TerrainType.Gem, controller.rng)
    if goldPos.x >= 0:
      let dx = abs(goldPos.x - agent.pos.x)
      let dy = abs(goldPos.y - agent.pos.y)
      if max(dx, dy) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(3'u8, neighborDirIndex(agent.pos, goldPos).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, goldPos, controller.rng).uint8))

    let nextSearchPos = getNextSpiralPoint(state, controller.rng)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))
