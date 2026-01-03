proc decideHearter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  # Handle gold → magma → bar → altar workflow
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
    let mine = env.findNearestThingSpiral(state, Mine, controller.rng)
    if mine != nil:
      let dx = abs(mine.pos.x - agent.pos.x)
      let dy = abs(mine.pos.y - agent.pos.y)
      if max(dx, dy) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(3'u8, neighborDirIndex(agent.pos, mine.pos).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, mine.pos, controller.rng).uint8))

    let nextSearchPos = getNextSpiralPoint(state, controller.rng)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))
