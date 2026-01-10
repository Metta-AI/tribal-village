const
  WallRingRadius = 7
  WallRingRadiusSlack = 1
  WallRingRadii = [WallRingRadius, WallRingRadius - WallRingRadiusSlack, WallRingRadius + WallRingRadiusSlack]

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

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
  let popTarget = popCount + 1
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId != teamId:
      continue
    if isBuildingKind(thing.kind):
      let cap = buildingPopCap(thing.kind)
      if cap > 0:
        popCap += cap
        if popCap >= popTarget:
          break
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
            if isValidPos(stand) and not env.hasDoor(stand) and env.isEmpty(stand) and
                env.canAgentPassDoor(agent, stand) and
                not isTileFrozen(stand, env) and
                not isBlockedTerrain(env.terrain[stand.x][stand.y]):
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
  for kind in [Granary, LumberCamp, Quarry, MiningCamp]:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Remote dropoff buildings near resources.
  let farFromHome = agent.homeAltar.x < 0 or
    max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) > 10
  if farFromHome:
    let nearbyWheat = countNearbyThings(env, agent.pos, 4, {Wheat})
    let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
    let (didMill, actMill) = controller.tryBuildNearResource(
      env, agent, agentId, state, teamId, Mill,
      nearbyWheat + nearbyFertile, 8,
      [Mill, Granary, TownCenter], 5
    )
    if didMill: return actMill

  if controller.getBuildingCount(env, teamId, Mill) >= 2:
    let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
    if didPlant: return actPlant

  for entry in [
    (LumberCamp, {Tree}, 6),
    (MiningCamp, {Gold}, 6),
    (Quarry, {Stone, Stalagmite}, 6)
  ]:
    let (kind, nearbyKinds, minCount) = entry
    let nearbyCount = countNearbyThings(env, agent.pos, 4, nearbyKinds)
    let (did, act) = controller.tryBuildCampThreshold(
      env, agent, agentId, state, teamId, kind,
      nearbyCount, minCount,
      [kind]
    )
    if did: return act

  for kind in [WeavingLoom, ClayOven, Blacksmith,
               Barracks, ArcheryRange, Stable, SiegeWorkshop,
               Outpost, Castle]:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act

  # Build a wall ring around the altar once core economy exists and wood is stockpiled.
  if agent.homeAltar.x >= 0 and
      controller.getBuildingCount(env, teamId, LumberCamp) > 0 and
      env.stockpileCount(teamId, ResourceWood) >= 3:
    let altarPos = agent.homeAltar
    var doorTarget = ivec2(-1, -1)
    var wallTarget = ivec2(-1, -1)
    var outpostTarget = ivec2(-1, -1)
    block findRing:
      for radius in WallRingRadii:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if max(abs(dx), abs(dy)) != radius:
              continue
            let pos = altarPos + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if env.terrain[pos.x][pos.y] == TerrainRoad:
              continue
            let isDoorSlot = (dx == 0 or dy == 0 or abs(dx) == abs(dy))
            if isDoorSlot:
              if outpostTarget.x < 0 and env.hasDoor(pos):
                let stepX = signi(altarPos.x - pos.x)
                let stepY = signi(altarPos.y - pos.y)
                let outpostPos = pos + ivec2(stepX * 2, stepY * 2)
                if isValidPos(outpostPos) and env.terrain[outpostPos.x][outpostPos.y] != TerrainRoad and
                    env.canPlaceBuilding(outpostPos):
                  outpostTarget = outpostPos
              if doorTarget.x < 0 and env.canPlaceBuilding(pos):
                doorTarget = pos
            elif wallTarget.x < 0 and env.canPlaceBuilding(pos):
              wallTarget = pos
    let canDoor = doorTarget.x >= 0
    let canWall = wallTarget.x >= 0
    let buildDoorFirst = if canDoor and canWall: (env.currentStep mod 2) == 0 else: canDoor
    if buildDoorFirst and canDoor:
      if env.canAffordBuild(teamId, thingItem("Door")):
        let (didDoor, actDoor) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
        )
        if didDoor: return actDoor
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if outpostTarget.x >= 0:
      if env.canAffordBuild(teamId, thingItem("Outpost")):
        let (didOutpost, actOutpost) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, outpostTarget, buildIndexFor(Outpost)
        )
        if didOutpost: return actOutpost
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if (not buildDoorFirst) and canWall:
      if env.canAffordBuild(teamId, thingItem("Wall")):
        let (did, act) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, wallTarget, BuildIndexWall
        )
        if did: return act
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood

  return controller.moveNextSearch(env, agent, agentId, state)
