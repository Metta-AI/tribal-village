const
  # Door slots along the wall ring; offset avoids corners on common radii.
  WallRingDoorSpacing = 5
  WallRingDoorOffset = 2

proc wallRingIndex(dx, dy, radius: int): int =
  if max(abs(dx), abs(dy)) != radius:
    return -1
  if dy == -radius:
    return dx + radius
  if dx == radius:
    return (2 * radius + 1) + (dy + radius - 1)
  if dy == radius:
    return (4 * radius + 1) + (radius - 1 - dx)
  if dx == -radius:
    return (6 * radius + 1) + (radius - 1 - dy)
  -1

proc isWallRingDoorSlot(altar, pos: IVec2, radius: int): bool =
  let dx = int(pos.x - altar.x)
  let dy = int(pos.y - altar.y)
  let idx = wallRingIndex(dx, dy, radius)
  if idx < 0:
    return false
  ((idx + WallRingDoorOffset) mod WallRingDoorSpacing) == 0

proc doorInnerPos(altar, doorPos: IVec2, radius: int): IVec2 =
  let dx = int(doorPos.x - altar.x)
  let dy = int(doorPos.y - altar.y)
  if dx == radius and abs(dy) < radius:
    return doorPos + ivec2(-1, 0)
  if dx == -radius and abs(dy) < radius:
    return doorPos + ivec2(1, 0)
  if dy == radius and abs(dx) < radius:
    return doorPos + ivec2(0, -1)
  if dy == -radius and abs(dx) < radius:
    return doorPos + ivec2(0, 1)
  let step = ivec2(signi(altar.x - doorPos.x), signi(altar.y - doorPos.y))
  doorPos + step

proc findWallRingTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
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

proc findHouseClusterTarget(env: Environment, agent: Thing, anchor: IVec2,
                            minDist, maxDist: int): tuple[buildPos, standPos: IVec2] =
  ## Find an empty tile inside a 2x2 house block near the anchor, plus a stand position.
  result.buildPos = ivec2(-1, -1)
  result.standPos = ivec2(-1, -1)
  let minX = max(0, anchor.x - maxDist - 1)
  let maxX = min(MapWidth - 2, anchor.x + maxDist + 1)
  let minY = max(0, anchor.y - maxDist - 1)
  let maxY = min(MapHeight - 2, anchor.y + maxDist + 1)
  var bestScore = -1

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
    true

  for x in minX .. maxX:
    for y in minY .. maxY:
      let p0 = ivec2(x.int32, y.int32)
      let p1 = ivec2((x + 1).int32, y.int32)
      let p2 = ivec2(x.int32, (y + 1).int32)
      let p3 = ivec2((x + 1).int32, (y + 1).int32)
      let tiles = [p0, p1, p2, p3]

      var existingHouses = 0
      var emptyTiles: seq[IVec2] = @[]
      var blocked = false
      for t in tiles:
        let dist = chebyshevDist(anchor, t).int
        if dist < minDist or dist > maxDist:
          blocked = true
          break
        if not isBuildableHouseTile(t):
          blocked = true
          break
        let occ = env.getThing(t)
        if not isNil(occ):
          if occ.kind == House:
            inc existingHouses
          else:
            blocked = true
            break
        else:
          emptyTiles.add(t)
      if blocked or emptyTiles.len == 0:
        continue

      var bestTile = ivec2(-1, -1)
      var bestStand = ivec2(-1, -1)
      for t in emptyTiles:
        for d in [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]:
          let stand = t + d
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
          bestTile = t
          bestStand = stand
          break
        if bestTile.x >= 0:
          break
      if bestTile.x < 0:
        continue

      let score = existingHouses * 10
      if score > bestScore:
        bestScore = score
        result.buildPos = bestTile
        result.standPos = bestStand

  result

proc findDoorRingTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if max(abs(dx), abs(dy)) != radius:
        continue
      let pos = altar + ivec2(dx.int32, dy.int32)
      if not isWallRingDoorSlot(altar, pos, radius):
        continue
      if not env.canPlaceBuilding(pos):
        continue
      if env.terrain[pos.x][pos.y] == TerrainRoad:
        continue
      return pos
  ivec2(-1, -1)

proc findDoorRingOutpostTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
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
  const CoreEconomy = [Granary, LumberCamp, Quarry, MiningCamp]
  const ProductionBuildings = [WeavingLoom, ClayOven, Blacksmith]
  const MilitaryBuildings = [Barracks, ArcheryRange, Stable, SiegeWorkshop]
  const DefenseBuildings = [Outpost, Castle]

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
    let target = findHouseClusterTarget(env, agent, anchor, 3, 5)
    if target.buildPos.x >= 0:
      let idx = buildIndexFor(House)
      if idx >= 0:
        let (did, act) = goToStandAndBuild(
          controller, env, agent, agentId, state,
          target.standPos, target.buildPos, idx
        )
        if did: return act

  # Ensure a town center exists if the starter one is lost.
  if controller.getBuildingCount(env, teamId, TownCenter) == 0:
    let idx = buildIndexFor(TownCenter)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Build a wall ring around the altar.
  if agent.homeAltar.x >= 0:
    let doorKey = thingItem("Door")
    let doorTarget = findDoorRingTarget(env, agent.homeAltar, 5)
    if doorTarget.x >= 0:
      if env.canAffordBuild(teamId, doorKey):
        let (didDoor, actDoor) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
        )
        if didDoor: return actDoor
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    let outpostTarget = findDoorRingOutpostTarget(env, agent.homeAltar, 5)
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
    let target = findWallRingTarget(env, agent.homeAltar, 5)
    if target.x >= 0:
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
  let (didLumber, actLumber) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, LumberCamp,
    nearbyTrees, 6,
    [LumberCamp, TownCenter], dropoffDistanceThreshold
  )
  if didLumber: return actLumber

  let nearbyGold = countNearbyThings(env, agent.pos, 4, {Gold})
  let (didMining, actMining) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, MiningCamp,
    nearbyGold, 6,
    [MiningCamp, TownCenter], dropoffDistanceThreshold
  )
  if didMining: return actMining

  let nearbyStone = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
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

  return controller.moveNextSearch(env, agent, agentId, state)
