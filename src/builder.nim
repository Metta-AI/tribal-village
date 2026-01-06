proc findWallRingTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if max(abs(dx), abs(dy)) != radius:
        continue
      let pos = altar + ivec2(dx.int32, dy.int32)
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
  let candidates = [
    altar + ivec2(0, radius.int32),
    altar + ivec2(radius.int32, 0),
    altar + ivec2(0, -radius.int32),
    altar + ivec2(-radius.int32, 0)
  ]
  for pos in candidates:
    if not isValidPos(pos):
      continue
    if not env.canPlaceBuilding(pos):
      continue
    if env.terrain[pos.x][pos.y] == TerrainRoad:
      continue
    return pos
  ivec2(-1, -1)

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
    allowGold = isNil(armorNeedy)
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
    if env.teamStockpiles[teamId].counts[ResourceWood] > 0:
      let doorTarget = findDoorRingTarget(env, agent.homeAltar, 5)
      if doorTarget.x >= 0:
        let (didDoor, actDoor) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
        )
        if didDoor: return actDoor
    let target = findWallRingTarget(env, agent.homeAltar, 5)
    if target.x >= 0:
      let idx = buildIndexFor(Wall)
      if idx >= 0:
        let (did, act) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, target, idx
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

  let nearbyTrees = countNearbyTrees(env, agent.pos, 4)
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

  # Plant wheat/trees around existing mills once the economy is established.
  if agent.unitClass == UnitVillager:
    let millCount = controller.getBuildingCount(env, teamId, Mill)
    if millCount >= 4:
      let mill = env.findNearestFriendlyThingSpiral(state, teamId, Mill, controller.rng)
      if not isNil(mill):
        let millDist = chebyshevDist(agent.pos, mill.pos).int
        if millDist <= 12:
          let radius = max(1, buildingFertileRadius(Mill))
          var target = ivec2(-1, -1)
          var bestDist = int.high
          for dx in -radius .. radius:
            for dy in -radius .. radius:
              if max(abs(dx), abs(dy)) > radius:
                continue
              let pos = mill.pos + ivec2(dx.int32, dy.int32)
              if not isValidPos(pos):
                continue
              if env.terrain[pos.x][pos.y] != Fertile:
                continue
              if not env.isEmpty(pos) or env.hasDoor(pos) or isTileFrozen(pos, env):
                continue
              let dist = abs(pos.x - agent.pos.x) + abs(pos.y - agent.pos.y)
              if dist < bestDist:
                bestDist = dist
                target = pos
          if target.x >= 0:
            if agent.inventoryWheat > 0 or agent.inventoryWood > 0:
              let dx = abs(target.x - agent.pos.x)
              let dy = abs(target.y - agent.pos.y)
              if max(dx, dy) == 1'i32 and (dx == 0 or dy == 0):
                let dirIdx = getCardinalDirIndex(agent.pos, target)
                let plantArg = (if agent.inventoryWheat > 0: dirIdx else: dirIdx + 4)
                return saveStateAndReturn(controller, agentId, state,
                  encodeAction(7'u8, plantArg.uint8))
              return saveStateAndReturn(controller, agentId, state,
                encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, target, controller.rng).uint8))
            let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
            if not isNil(wheat):
              return controller.useOrMove(env, agent, agentId, state, wheat.pos)
            let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
            if didWood: return actWood

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
  let (didArmor, actArmor) =
    controller.deliverEquipment(env, agent, agentId, state, teamId, NeedArmor, agent.inventoryArmor)
  if didArmor: return actArmor
  let (didSpear, actSpear) =
    controller.deliverEquipment(env, agent, agentId, state, teamId, NeedSpear, agent.inventorySpear)
  if didSpear: return actSpear

  # Craft armor at the blacksmith when bars are available.
  if not isNil(armorNeedy):
    if agent.inventoryBar > 0:
      let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
      if not isNil(smith):
        return controller.useOrMove(env, agent, agentId, state, smith.pos)
    elif agent.inventoryGold > 0:
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if not isNil(magma):
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    else:
      let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
      if didGold: return actGold

  # Craft spears at the blacksmith if fighters are out.
  let spearNeedy = findNearestTeammateNeeding(env, agent, NeedSpear)
  if not isNil(spearNeedy):
    if agent.inventoryWood == 0:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if not isNil(smith):
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  return controller.moveNextSearch(env, agent, agentId, state)
