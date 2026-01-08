const
  WallRingRadius = 7
  WallRingRadiusSlack = 1
  WallRingRadii = [WallRingRadius, WallRingRadius - WallRingRadiusSlack, WallRingRadius + WallRingRadiusSlack]

proc isWallRingDoorSlot(altar, pos: IVec2, radius: int): bool =
  let dx = int(pos.x - altar.x)
  let dy = int(pos.y - altar.y)
  # Doors at cardinals and diagonals (8 total).
  (dx == 0 and dy == -radius) or
  (dx == radius and dy == 0) or
  (dx == 0 and dy == radius) or
  (dx == -radius and dy == 0) or
  (dx == radius and dy == -radius) or
  (dx == radius and dy == radius) or
  (dx == -radius and dy == radius) or
  (dx == -radius and dy == -radius)

proc doorInnerPos(altar, doorPos: IVec2, radius: int): IVec2 =
  let step = ivec2(signi(altar.x - doorPos.x), signi(altar.y - doorPos.y))
  doorPos + ivec2(step.x * 2, step.y * 2)

proc findWallRingTarget(env: Environment, altar: IVec2): IVec2 =
  for radius in WallRingRadii:
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let pos = altar + ivec2(dx.int32, dy.int32)
        if isWallRingDoorSlot(altar, pos, radius):
          continue
        if not isValidPos(pos):
          continue
        if not env.canPlaceBuilding(pos):
          continue
        if env.terrain[pos.x][pos.y] == TerrainRoad:
          continue
        return pos
  ivec2(-1, -1)

proc findHouseTarget(env: Environment, agent: Thing, anchor: IVec2,
                     minDist, maxDist: int): tuple[buildPos, standPos: IVec2] =
  ## Find any buildable single-tile house spot between min/max range of the altar.
  result.buildPos = ivec2(-1, -1)
  result.standPos = ivec2(-1, -1)
  let minX = max(0, anchor.x - maxDist)
  let maxX = min(MapWidth - 1, anchor.x + maxDist)
  let minY = max(0, anchor.y - maxDist)
  let maxY = min(MapHeight - 1, anchor.y + maxDist)

  proc isBuildableHouseTile(pos: IVec2): bool =
    if not isValidPos(pos):
      return false
    if env.hasDoor(pos):
      return false
    if isTileFrozen(pos, env):
      return false
    if not isBuildableTerrain(env.terrain[pos.x][pos.y]):
      return false
    if env.terrain[pos.x][pos.y] == TerrainRoad:
      return false
    if not env.isEmpty(pos):
      return false
    true

  for x in minX .. maxX:
    for y in minY .. maxY:
      let pos = ivec2(x.int32, y.int32)
      let dist = chebyshevDist(anchor, pos).int
      if dist < minDist or dist > maxDist:
        continue
      if not isBuildableHouseTile(pos):
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
        result.buildPos = pos
        result.standPos = stand
        return result
  result

proc findDoorRingTarget(env: Environment, altar: IVec2): IVec2 =
  for radius in WallRingRadii:
    let doorOffsets = [
      ivec2(0, -radius), ivec2(radius, 0), ivec2(0, radius), ivec2(-radius, 0),
      ivec2(radius, -radius), ivec2(radius, radius), ivec2(-radius, radius), ivec2(-radius, -radius)
    ]
    for offset in doorOffsets:
      let pos = altar + offset
      if not isValidPos(pos):
        continue
      if not env.canPlaceBuilding(pos):
        continue
      if env.terrain[pos.x][pos.y] == TerrainRoad:
        continue
      return pos
  ivec2(-1, -1)

proc findDoorRingOutpostTarget(env: Environment, altar: IVec2): IVec2 =
  for radius in WallRingRadii:
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let doorPos = altar + ivec2(dx.int32, dy.int32)
        if not isWallRingDoorSlot(altar, doorPos, radius):
          continue
        if not env.hasDoor(doorPos):
          continue
        let outpostPos = doorInnerPos(altar, doorPos, radius)
        if not isValidPos(outpostPos):
          continue
        if not env.canPlaceBuilding(outpostPos):
          continue
        if env.terrain[outpostPos.x][outpostPos.y] == TerrainRoad:
          continue
        return outpostPos
  ivec2(-1, -1)

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
  let popCap = env.teamPopCap(teamId)
  if popCap > 0 and popCount >= popCap - 1:
    let anchor = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
    let target = findHouseTarget(env, agent, anchor, 5, 15)
    if target.buildPos.x >= 0:
      let idx = buildIndexFor(House)
      if idx >= 0:
        let (did, act) = goToStandAndBuild(
          controller, env, agent, agentId, state,
          target.standPos, target.buildPos, idx
        )
        if did: return act

  # Build a wall ring around the altar.
  if agent.homeAltar.x >= 0:
    let doorKey = thingItem("Door")
    let doorTarget = findDoorRingTarget(env, agent.homeAltar)
    let wallTarget = findWallRingTarget(env, agent.homeAltar)
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
    let outpostTarget = findDoorRingOutpostTarget(env, agent.homeAltar)
    if outpostTarget.x >= 0:
      let outpostKey = thingItem("Outpost")
      if env.canAffordBuild(teamId, outpostKey):
        let idx = buildIndexFor(Outpost)
        if idx >= 0:
          let (didOutpost, actOutpost) = goToAdjacentAndBuild(
            controller, env, agent, agentId, state, outpostTarget, idx
          )
          if didOutpost: return actOutpost
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if (not buildDoorFirst) and canWall:
      let target = wallTarget
      let wallKey = thingItem("Wall")
      if env.canAffordBuild(teamId, wallKey):
        let idx = buildIndexFor(Wall)
        if idx >= 0:
          let (did, act) = goToAdjacentAndBuild(
            controller, env, agent, agentId, state, target, idx
          )
          if did: return act
      else:
        let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
        if didStone: return actStone

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

  let nearbyTrees = countNearbyThings(env, agent.pos, 4, {Pine, Palm})
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

  return controller.moveNextSearch(env, agent, agentId, state)
