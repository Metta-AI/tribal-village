proc signi(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

proc findWallRingTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if max(abs(dx), abs(dy)) != radius:
        continue
      let pos = altar + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if env.hasDoor(pos) or not env.isEmpty(pos):
        continue
      if env.terrain[pos.x][pos.y] notin {TerrainEmpty, TerrainGrass, TerrainSand, TerrainSnow,
                                          TerrainDune, TerrainStalagmite, TerrainBridge}:
        continue
      if isTileFrozen(pos, env):
        continue
      return pos
  ivec2(-1, -1)

proc deliverToTeammate(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState, teammate: Thing): uint8 =
  let dx = abs(teammate.pos.x - agent.pos.x)
  let dy = abs(teammate.pos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  let armorNeedy = findNearestTeammateNeeding(env, agent, NeedArmor)
  let (didDrop, dropAct) = controller.dropoffCarrying(
    env, agent, agentId, state,
    allowWood = false,
    allowStone = true,
    allowGold = armorNeedy == nil
  )
  if didDrop: return dropAct

  # Top priority: keep population cap ahead of current population.
  let popCount = env.teamPopCount(teamId)
  let popCap = env.teamPopCap(teamId)
  if popCap > 0 and popCount >= popCap - 1:
    let idx = buildIndexFor(House)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Ensure a town center exists if the starter one is lost.
  if env.countTeamBuildings(teamId, TownCenter) == 0:
    let idx = buildIndexFor(TownCenter)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Build a wall ring around the altar.
  if agent.homeAltar.x >= 0:
    let target = findWallRingTarget(env, agent.homeAltar, 5)
    if target.x >= 0:
      let dir = ivec2(signi(target.x - agent.pos.x), signi(target.y - agent.pos.y))
      if agent.orientation == Orientation(vecToOrientation(dir)) and chebyshevDist(agent.pos, target) == 1'i32:
        let idx = buildIndexFor(Wall)
        if idx >= 0:
          let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
          if did: return act
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, target, controller.rng).uint8))

  # Core economic infrastructure.
  if env.countTeamBuildings(teamId, Granary) == 0:
    let idx = buildIndexFor(Granary)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, LumberYard) == 0:
    let idx = buildIndexFor(LumberYard)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Quarry) == 0:
    let idx = buildIndexFor(Quarry)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Remote dropoff buildings near resources.
  let dropoffDistanceThreshold = 5
  let nearbyWheat = countNearbyTerrain(env, agent.pos, 4, {Wheat})
  let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
  if nearbyWheat + nearbyFertile >= 8:
    let dist = nearestFriendlyBuildingDistance(env, teamId, [Mill, Granary, TownCenter], agent.pos)
    if dist > dropoffDistanceThreshold:
      let idx = buildIndexFor(Mill)
      if idx >= 0:
        let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
        if did: return act

  let nearbyTrees = countNearbyTrees(env, agent.pos, 4)
  if nearbyTrees >= 6:
    let dist = nearestFriendlyBuildingDistance(env, teamId, [LumberCamp, TownCenter], agent.pos)
    if dist > dropoffDistanceThreshold:
      let idx = buildIndexFor(LumberCamp)
      if idx >= 0:
        let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
        if did: return act

  let nearbyGold = countNearbyTerrain(env, agent.pos, 4, {Gold})
  if nearbyGold >= 6:
    let dist = nearestFriendlyBuildingDistance(env, teamId, [MiningCamp, TownCenter], agent.pos)
    if dist > dropoffDistanceThreshold:
      let idx = buildIndexFor(MiningCamp)
      if idx >= 0:
        let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
        if did: return act

  let nearbyStone = countNearbyTerrain(env, agent.pos, 4, {Stone, Stalagmite})
  if nearbyStone >= 6:
    let dist = nearestFriendlyBuildingDistance(env, teamId, [Quarry, TownCenter], agent.pos)
    if dist > dropoffDistanceThreshold:
      let idx = buildIndexFor(Quarry)
      if idx >= 0:
        let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
        if did: return act

  # Production buildings.
  if env.countTeamBuildings(teamId, WeavingLoom) == 0:
    let idx = buildIndexFor(WeavingLoom)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, ClayOven) == 0:
    let idx = buildIndexFor(ClayOven)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Blacksmith) == 0:
    let idx = buildIndexFor(Blacksmith)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Military production.
  if env.countTeamBuildings(teamId, Barracks) == 0:
    let idx = buildIndexFor(Barracks)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, ArcheryRange) == 0:
    let idx = buildIndexFor(ArcheryRange)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Stable) == 0:
    let idx = buildIndexFor(Stable)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, SiegeWorkshop) == 0:
    let idx = buildIndexFor(SiegeWorkshop)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Defensive buildings.
  if env.countTeamBuildings(teamId, Outpost) == 0:
    let idx = buildIndexFor(Outpost)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Castle) == 0:
    let idx = buildIndexFor(Castle)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Equipment support: deliver armor/spears to teammates who need them.
  if agent.inventoryArmor > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedArmor)
    if teammate != nil:
      return deliverToTeammate(controller, env, agent, agentId, state, teammate)
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  if agent.inventorySpear > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedSpear)
    if teammate != nil:
      return deliverToTeammate(controller, env, agent, agentId, state, teammate)
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Craft armor at the blacksmith when bars are available.
  if armorNeedy != nil:
    if agent.inventoryBar > 0:
      let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
      if smith != nil:
        return controller.useOrMove(env, agent, agentId, state, smith.pos)
    elif agent.inventoryGold > 0:
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if magma != nil:
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    else:
      let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
      if didGold: return actGold

  # Craft spears at the blacksmith if fighters are out.
  let spearNeedy = findNearestTeammateNeeding(env, agent, NeedSpear)
  if spearNeedy != nil:
    if agent.inventoryWood == 0:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  return controller.moveNextSearch(env, agent, agentId, state)
