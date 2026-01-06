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
  const CoreEconomy = [Granary, LumberCamp, Quarry, MiningCamp]
  const ProductionBuildings = [WeavingLoom, ClayOven, Blacksmith]
  const MilitaryBuildings = [Barracks, ArcheryRange, Stable, SiegeWorkshop]
  const DefenseBuildings = [Outpost, Castle]

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
  for kind in CoreEconomy:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Remote dropoff buildings near resources.
  let dropoffDistanceThreshold = 5
  let nearbyWheat = countNearbyTerrain(env, agent.pos, 4, {Wheat})
  let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
  let (didMill, actMill) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, Mill,
    nearbyWheat + nearbyFertile, 8,
    [Mill, Granary, TownCenter], dropoffDistanceThreshold
  )
  if didMill: return actMill

  let nearbyTrees = countNearbyTrees(env, agent.pos, 4)
  let (didLumber, actLumber) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, LumberCamp,
    nearbyTrees, 6,
    [LumberCamp, TownCenter], dropoffDistanceThreshold
  )
  if didLumber: return actLumber

  let nearbyGold = countNearbyTerrain(env, agent.pos, 4, {Gold})
  let (didMining, actMining) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, MiningCamp,
    nearbyGold, 6,
    [MiningCamp, TownCenter], dropoffDistanceThreshold
  )
  if didMining: return actMining

  let nearbyStone = countNearbyTerrain(env, agent.pos, 4, {Stone, Stalagmite})
  let (didQuarry, actQuarry) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, Quarry,
    nearbyStone, 6,
    [Quarry, TownCenter], dropoffDistanceThreshold
  )
  if didQuarry: return actQuarry

  # Production buildings.
  for kind in ProductionBuildings:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Military production.
  for kind in MilitaryBuildings:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Defensive buildings.
  for kind in DefenseBuildings:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
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
