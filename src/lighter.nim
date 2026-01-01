proc decideLighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  # Priority 1: Plant lanterns outward in rings from home assembler
  if agent.inventoryLantern > 0:
    let center = if agent.homeassembler.x >= 0: agent.homeassembler else: agent.pos

    let maxR = 12
    for radius in 3 .. maxR:
      var bestDir = -1
      for i in 0 .. 7:
        let dir = orientationToVec(Orientation(i))
        let target = agent.pos + dir
        let dist = max(abs(target.x - center.x), abs(target.y - center.y))
        if dist != radius: continue
        if target.x < 0 or target.x >= MapWidth or target.y < 0 or target.y >= MapHeight:
          continue
        if not env.isEmpty(target):
          continue
        if env.hasDoor(target):
          continue
        if isBlockedTerrain(env.terrain[target.x][target.y]):
          continue
        var spaced = true
        for t in env.things:
          if t.kind == PlantedLantern and chebyshevDist(target, t.pos) < 3'i32:
            spaced = false
            break
        if spaced:
          bestDir = i
          break
      if bestDir >= 0:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(6'u8, bestDir.uint8))

    let awayFromCenter = getMoveAway(env, agent, agent.pos, center, controller.rng)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, awayFromCenter.uint8))

  # Priority 2: If adjacent to a lantern, push it further away
  elif isAdjacentToLantern(env, agent.pos):
    let near = findNearestLantern(env, agent.pos)
    if near.found and near.dist == 1'i32:
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, neighborDirIndex(agent.pos, near.pos).uint8))
    let dx = near.pos.x - agent.pos.x
    let dy = near.pos.y - agent.pos.y
    let step = agent.pos + ivec2((if dx != 0: dx div abs(dx) else: 0'i32),
                               (if dy != 0: dy div abs(dy) else: 0'i32))
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, neighborDirIndex(agent.pos, step).uint8))

  # Priority 3: Craft lantern if we have wheat
  if agent.inventoryWheat > 0:
    let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, WeavingLoom)
    if did: return act

  # Priority 4: Collect wheat
  let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if did: return act
  return controller.moveNextSearch(env, agent, agentId, state)
