proc decideLighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Place lanterns outward in rings and keep spacing from existing lanterns.
  if agent.inventoryLantern > 0:
    let center = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
    let maxR = 12
    for radius in 3 .. maxR:
      var bestDir = -1
      for i in 0 .. 7:
        let dir = orientationToVec(Orientation(i))
        let target = agent.pos + dir
        let dist = max(abs(target.x - center.x), abs(target.y - center.y))
        if dist != radius:
          continue
        if not isValidPos(target):
          continue
        if env.hasDoor(target) or not env.isEmpty(target):
          continue
        if isBlockedTerrain(env.terrain[target.x][target.y]) or isTileFrozen(target, env):
          continue
        if env.terrain[target.x][target.y] == Wheat:
          continue
        var spaced = true
        for t in env.things:
          if t.kind == Lantern:
            let d = max(abs(t.pos.x - target.x), abs(t.pos.y - target.y))
            if d < 3'i32:
              spaced = false
              break
        if spaced:
          bestDir = i
          break
      if bestDir >= 0:
        return saveStateAndReturn(controller, agentId, state, encodeAction(6'u8, bestDir.uint8))

    # No ring slot found; step outward to expand search radius next tick.
    let awayDir = getMoveAway(env, agent, agent.pos, center, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

  # If adjacent to an existing lantern, step into it to push/relocate.
  if isAdjacentToLantern(env, agent.pos):
    let near = findNearestLantern(env, agent.pos)
    if near.found and near.dist == 1'i32:
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, neighborDirIndex(agent.pos, near.pos).uint8))
    if near.found:
      let dx = near.pos.x - agent.pos.x
      let dy = near.pos.y - agent.pos.y
      let step = agent.pos + ivec2((if dx != 0: dx div abs(dx) else: 0'i32),
                                   (if dy != 0: dy div abs(dy) else: 0'i32))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, neighborDirIndex(agent.pos, step).uint8))

  # Turn wheat into lanterns at the weaving loom.
  if agent.inventoryWheat > 0:
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil:
      return controller.useOrMove(env, agent, agentId, state, loom.pos)
    return controller.moveNextSearch(env, agent, agentId, state)

  # Harvest wheat so we can craft lanterns.
  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if did: return act

  return controller.moveNextSearch(env, agent, agentId, state)
