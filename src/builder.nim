const
  WallRingRadius = 7
  WallRingRadiusSlack = 1
  WallRingRadii = [WallRingRadius, WallRingRadius - WallRingRadiusSlack, WallRingRadius + WallRingRadiusSlack]

proc tryPlantFarmTiles(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState, teamId: int): tuple[did: bool, action: uint8] =
  let millCount = controller.getBuildingCount(env, teamId, Mill)
  if millCount < 2:
    return (false, 0'u8)
  let mill = env.findNearestFriendlyThingSpiral(state, teamId, Mill, controller.rng)
  if isNil(mill):
    return (false, 0'u8)
  var fertilePos = ivec2(-1, -1)
  var minDist = 999999
  let startX = max(0, mill.pos.x - 6)
  let endX = min(MapWidth - 1, mill.pos.x + 6)
  let startY = max(0, mill.pos.y - 6)
  let endY = min(MapHeight - 1, mill.pos.y + 6)
  let mx = mill.pos.x.int
  let my = mill.pos.y.int
  for x in startX..endX:
    for y in startY..endY:
      if env.terrain[x][y] != TerrainType.Fertile:
        continue
      let candPos = ivec2(x.int32, y.int32)
      if env.isEmpty(candPos) and isNil(env.getOverlayThing(candPos)) and not env.hasDoor(candPos):
        let dist = abs(x - mx) + abs(y - my)
        if dist < minDist:
          minDist = dist
          fertilePos = candPos
  if fertilePos.x < 0:
    return (false, 0'u8)

  let wantsTree = ((fertilePos.x + fertilePos.y) mod 2'i32) == 1'i32
  if wantsTree:
    if agent.inventoryWood <= 0:
      return controller.ensureWood(env, agent, agentId, state)
  else:
    if agent.inventoryWheat <= 0:
      return controller.ensureWheat(env, agent, agentId, state)

  let dx = abs(fertilePos.x - agent.pos.x)
  let dy = abs(fertilePos.y - agent.pos.y)
  if max(dx, dy) == 1'i32 and (dx == 0 or dy == 0):
    let dirIdx = getCardinalDirIndex(agent.pos, fertilePos)
    let plantArg = if wantsTree: dirIdx + 4 else: dirIdx
    return (true, saveStateAndReturn(controller, agentId, state,
      encodeAction(7'u8, plantArg.uint8)))
  return (true, controller.moveTo(env, agent, agentId, state, fertilePos))

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  const CoreEconomy = [Granary, LumberCamp, Quarry, MiningCamp]
  const ProductionBuildings = [WeavingLoom, ClayOven, Blacksmith]
  const MilitaryBuildings = [Barracks, ArcheryRange, Stable, SiegeWorkshop]
  const DefenseBuildings = [Outpost, Castle]

  # Drop off any carried stockpile resources so building costs can be paid.
  let (didDrop, dropAct) = controller.dropoffCarrying(
    env, agent, agentId, state,
    allowFood = true,
    allowWood = true,
    allowStone = true,
    allowGold = true
  )
  if didDrop: return dropAct

  # Top priority: keep population cap ahead of current population.
  var popCount = 0
  for otherAgent in env.agents:
    if not isAgentAlive(env, otherAgent):
      continue
    if getTeamId(otherAgent.agentId) == teamId:
      inc popCount
  var popCap = 0
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId != teamId:
      continue
    if isBuildingKind(thing.kind):
      let cap = buildingPopCap(thing.kind)
      if cap > 0:
        popCap += cap
  if popCap > 0 and popCount >= popCap - 1:
    var targetBuildPos = ivec2(-1, -1)
    var targetStandPos = ivec2(-1, -1)
    let minX = max(0, basePos.x - 15)
    let maxX = min(MapWidth - 1, basePos.x + 15)
    let minY = max(0, basePos.y - 15)
    let maxY = min(MapHeight - 1, basePos.y + 15)
    block findHouse:
      for x in minX .. maxX:
        for y in minY .. maxY:
          let pos = ivec2(x.int32, y.int32)
          let dist = chebyshevDist(basePos, pos).int
          if dist < 5 or dist > 15:
            continue
          if not env.canPlaceBuilding(pos) or env.terrain[pos.x][pos.y] == TerrainRoad:
            continue
          for d in [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]:
            let stand = pos + d
            if not isValidPos(stand):
              continue
            if env.hasDoor(stand):
              continue
            if isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env):
              continue
            if not env.isEmpty(stand):
              continue
            if not env.canAgentPassDoor(agent, stand):
              continue
            targetBuildPos = pos
            targetStandPos = stand
            break findHouse
    if targetBuildPos.x >= 0:
      let (did, act) = goToStandAndBuild(
        controller, env, agent, agentId, state,
        targetStandPos, targetBuildPos, buildIndexFor(House)
      )
      if did: return act

  # Core economic infrastructure.
  for kind in CoreEconomy:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Remote dropoff buildings near resources.
  let dropoffDistanceThreshold = 5
  let nearbyWheat = countNearbyThings(env, agent.pos, 4, {Wheat})
  let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
  if agent.homeAltar.x < 0 or
     max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) > 10:
    let (didMill, actMill) = controller.tryBuildNearResource(
      env, agent, agentId, state, teamId, Mill,
      nearbyWheat + nearbyFertile, 8,
      [Mill, Granary, TownCenter], dropoffDistanceThreshold
    )
    if didMill: return actMill

  let (didPlant, actPlant) = tryPlantFarmTiles(controller, env, agent, agentId, state, teamId)
  if didPlant: return actPlant

  let nearbyTrees = countNearbyThings(env, agent.pos, 4, {Tree})
  let (didLumber, actLumber) = controller.tryBuildCampThreshold(
    env, agent, agentId, state, teamId, LumberCamp,
    nearbyTrees, 6,
    [LumberCamp]
  )
  if didLumber: return actLumber

  let nearbyGold = countNearbyThings(env, agent.pos, 4, {Gold})
  let (didMining, actMining) = controller.tryBuildCampThreshold(
    env, agent, agentId, state, teamId, MiningCamp,
    nearbyGold, 6,
    [MiningCamp]
  )
  if didMining: return actMining

  let nearbyStone = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
  let (didQuarry, actQuarry) = controller.tryBuildCampThreshold(
    env, agent, agentId, state, teamId, Quarry,
    nearbyStone, 6,
    [Quarry]
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

  # Build a wall ring around the altar once core economy exists and wood is stockpiled.
  if agent.homeAltar.x >= 0 and
      controller.getBuildingCount(env, teamId, LumberCamp) > 0 and
      env.stockpileCount(teamId, ResourceWood) >= 3:
    let doorKey = thingItem("Door")
    let altarPos = agent.homeAltar
    var doorTarget = ivec2(-1, -1)
    var wallTarget = ivec2(-1, -1)
    block findDoor:
      for radius in WallRingRadii:
        let doorOffsets = [
          ivec2(0, -radius), ivec2(radius, 0), ivec2(0, radius), ivec2(-radius, 0),
          ivec2(radius, -radius), ivec2(radius, radius), ivec2(-radius, radius), ivec2(-radius, -radius)
        ]
        for offset in doorOffsets:
          let pos = altarPos + offset
          if not isValidPos(pos):
            continue
          if not env.canPlaceBuilding(pos):
            continue
          if env.terrain[pos.x][pos.y] == TerrainRoad:
            continue
          doorTarget = pos
          break findDoor
    block findWall:
      for radius in WallRingRadii:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if max(abs(dx), abs(dy)) != radius:
              continue
            let pos = altarPos + ivec2(dx.int32, dy.int32)
            let isDoorSlot = (dx == 0 or dy == 0 or abs(dx) == abs(dy))
            if isDoorSlot:
              continue
            if not isValidPos(pos):
              continue
            if not env.canPlaceBuilding(pos):
              continue
            if env.terrain[pos.x][pos.y] == TerrainRoad:
              continue
            wallTarget = pos
            break findWall
    let canDoor = doorTarget.x >= 0
    let canWall = wallTarget.x >= 0
    let buildDoorFirst = if canDoor and canWall: (env.currentStep mod 2) == 0 else: canDoor
    if buildDoorFirst and canDoor:
      if env.canAffordBuild(teamId, doorKey):
        let (didDoor, actDoor) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
        )
        if didDoor: return actDoor
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    var outpostTarget = ivec2(-1, -1)
    block findOutpost:
      for radius in WallRingRadii:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if max(abs(dx), abs(dy)) != radius:
              continue
            let doorPos = altarPos + ivec2(dx.int32, dy.int32)
            let isDoorSlot = (dx == 0 or dy == 0 or abs(dx) == abs(dy))
            if not isDoorSlot:
              continue
            if not env.hasDoor(doorPos):
              continue
            let stepX = if altarPos.x > doorPos.x: 1'i32 elif altarPos.x < doorPos.x: -1'i32 else: 0'i32
            let stepY = if altarPos.y > doorPos.y: 1'i32 elif altarPos.y < doorPos.y: -1'i32 else: 0'i32
            let outpostPos = doorPos + ivec2(stepX * 2, stepY * 2)
            if not isValidPos(outpostPos):
              continue
            if not env.canPlaceBuilding(outpostPos):
              continue
            if env.terrain[outpostPos.x][outpostPos.y] == TerrainRoad:
              continue
            outpostTarget = outpostPos
            break findOutpost
    if outpostTarget.x >= 0:
      let outpostKey = thingItem("Outpost")
      if env.canAffordBuild(teamId, outpostKey):
        let (didOutpost, actOutpost) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, outpostTarget, buildIndexFor(Outpost)
        )
        if didOutpost: return actOutpost
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if (not buildDoorFirst) and canWall:
      let wallKey = thingItem("Wall")
      if env.canAffordBuild(teamId, wallKey):
        let (did, act) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, wallTarget, BuildIndexWall
        )
        if did: return act
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood

  return controller.moveNextSearch(env, agent, agentId, state)
