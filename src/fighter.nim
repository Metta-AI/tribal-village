proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Lantern ring expansion / relocation.
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
        if target.x < 0 or target.x >= MapWidth or target.y < 0 or target.y >= MapHeight:
          continue
        if not env.isEmpty(target) or env.hasDoor(target):
          continue
        if env.terrain[target.x][target.y] == Water or isTileFrozen(target, env):
          continue
        var spaced = true
        for t in env.things:
          if t.kind == Lantern and chebyshevDist(target, t.pos) < 3'i32:
            spaced = false
            break
        if spaced:
          bestDir = i
          break
      if bestDir >= 0:
        return saveStateAndReturn(controller, agentId, state, encodeAction(6'u8, bestDir.uint8))

    # If no ring slot found, step outward to expand the ring.
    let away = getMoveAway(env, agent, agent.pos, center, controller.rng)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, away.uint8))

  # If adjacent to a lantern without one to plant, push it outward.
  if isAdjacentToLantern(env, agent.pos):
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

  # Craft lanterns at the weaving loom when possible.
  if agent.inventoryWheat > 0:
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil:
      return controller.useOrMove(env, agent, agentId, state, loom.pos)

  # Gather wheat for lanterns.
  let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
  if didWheat: return actWheat

  # Train into a combat unit when possible.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)

  # Maintain armor and spears.
  if agent.inventoryArmor < ArmorPoints:
    let armory = env.findNearestFriendlyThingSpiral(state, teamId, Armory, controller.rng)
    if armory != nil:
      return controller.useOrMove(env, agent, agentId, state, armory.pos)

  if agent.unitClass == UnitManAtArms and agent.inventorySpear == 0:
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Hunt while patrolling if nothing else to do.
  let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
  if didCow: return actCow
  let (didAnimal, actAnimal) = controller.findAndHarvest(env, agent, agentId, state, Animal)
  if didAnimal: return actAnimal

  return controller.moveNextSearch(env, agent, agentId, state)
