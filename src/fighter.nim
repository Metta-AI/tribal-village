proc isTeamBuilding(kind: ThingKind): bool =
  case kind
  of Altar, TownCenter, House, Armory, ClayOven, WeavingLoom, Outpost, Mill, LumberCamp,
     MiningCamp, Barracks, ArcheryRange, Stable, SiegeWorkshop, Blacksmith, Market, Dock,
     Monastery, University, Castle:
    true
  else:
    false

proc hasTeamLanternNear(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.things:
    if thing.kind != Lantern:
      continue
    if not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y) <= 2:
      return true
  false

proc findNearestUnlitBuilding(env: Environment, teamId: int, origin: IVec2): Thing =
  var bestDist = int.high
  for thing in env.things:
    if thing.teamId != teamId:
      continue
    if not isTeamBuilding(thing.kind):
      continue
    if hasTeamLanternNear(env, teamId, thing.pos):
      continue
    let dist = abs(thing.pos.x - origin.x) + abs(thing.pos.y - origin.y)
    if dist < bestDist:
      bestDist = dist
      result = thing

proc countTeamLanterns(env: Environment, teamId: int): int =
  for thing in env.things:
    if thing.kind != Lantern:
      continue
    if thing.lanternHealthy and thing.teamId == teamId:
      inc result

proc isLanternPlacementValid(env: Environment, pos: IVec2): bool =
  isValidPos(pos) and env.isEmpty(pos) and not env.hasDoor(pos) and
    not isBlockedTerrain(env.terrain[pos.x][pos.y]) and not isTileFrozen(pos, env) and
    env.terrain[pos.x][pos.y] notin {Water, Wheat}

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  let lanternCount = countTeamLanterns(env, teamId)
  if lanternCount < 10:
    # Expand lanterns outward from the home altar in a spiral.
    if agent.homeAltar.x >= 0:
      state.basePosition = agent.homeAltar
    var target = ivec2(-1, -1)
    for _ in 0 ..< 10:
      let candidate = getNextSpiralPoint(state, controller.rng)
      if not isLanternPlacementValid(env, candidate):
        continue
      if hasTeamLanternNear(env, teamId, candidate):
        continue
      target = candidate
      break

    if agent.inventoryLantern > 0:
      if target.x >= 0:
        if chebyshevDist(agent.pos, target) == 1'i32:
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(6'u8, neighborDirIndex(agent.pos, target).uint8))
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, target, controller.rng).uint8))
      return controller.moveNextSearch(env, agent, agentId, state)

    # No lantern: ensure a loom exists near base, then craft (or gather wheat).
    if env.countTeamBuildings(teamId, WeavingLoom) == 0 and agent.unitClass == UnitVillager:
      if agent.homeAltar.x >= 0 and chebyshevDist(agent.pos, agent.homeAltar) > 2'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, agent.homeAltar, controller.rng).uint8))
      let (didBuild, buildAct) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexWeavingLoom)
      if didBuild: return buildAct

    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil and agent.inventoryWheat > 0:
      return controller.useOrMove(env, agent, agentId, state, loom.pos)
    let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if didWheat: return actWheat
    let (didBush, actBush) = controller.findAndHarvest(env, agent, agentId, state, Bush)
    if didBush: return actBush
    return controller.moveNextSearch(env, agent, agentId, state)

  # Patrol and keep buildings lit by nearby lanterns.
  let unlit = findNearestUnlitBuilding(env, teamId, agent.pos)
  if unlit != nil:
    if agent.inventoryLantern > 0:
      var bestPos = ivec2(-1, -1)
      var bestDist = int.high
      for dx in -2 .. 2:
        for dy in -2 .. 2:
          if abs(dx) + abs(dy) > 2:
            continue
          let target = unlit.pos + ivec2(dx.int32, dy.int32)
          if not isValidPos(target):
            continue
          if not env.isEmpty(target) or env.hasDoor(target):
            continue
          if isBlockedTerrain(env.terrain[target.x][target.y]) or isTileFrozen(target, env):
            continue
          if env.terrain[target.x][target.y] == Water or env.terrain[target.x][target.y] == Wheat:
            continue
          let dist = abs(target.x - agent.pos.x) + abs(target.y - agent.pos.y)
          if dist < bestDist:
            bestDist = dist
            bestPos = target
      if bestPos.x >= 0:
        if chebyshevDist(agent.pos, bestPos) == 1'i32:
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(6'u8, neighborDirIndex(agent.pos, bestPos).uint8))
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, bestPos, controller.rng).uint8))

    # No lantern in inventory: craft or gather resources to make one.
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil and (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
      return controller.useOrMove(env, agent, agentId, state, loom.pos)

    let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if didWheat: return actWheat
    let (didWood, actWood) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

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
