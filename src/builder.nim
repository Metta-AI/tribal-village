const
  WallRingRadius = 7
  WallRingRadiusSlack = 1
  WallRingRadii = [WallRingRadius, WallRingRadius - WallRingRadiusSlack, WallRingRadius + WallRingRadiusSlack]

proc builderHasPlantInputs(agent: Thing): bool =
  agent.inventoryWheat > 0 or agent.inventoryWood > 0

proc builderHasDropoffItems(agent: Thing): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and (isFoodItem(key) or isStockpileResourceKey(key)):
      return true
  false

proc builderNeedsPopCap(env: Environment, teamId: int): bool =
  var popCount = 0
  for otherAgent in env.agents:
    if not isAgentAlive(env, otherAgent):
      continue
    if getTeamId(otherAgent.agentId) == teamId:
      inc popCount
  var popCap = 0
  var hasBase = false
  for thing in env.things:
    if thing.isNil or thing.teamId != teamId:
      continue
    if isBuildingKind(thing.kind):
      hasBase = true
      let cap = buildingPopCap(thing.kind)
      if cap > 0:
        popCap += cap
  let buffer = HousePopCap
  (popCap > 0 and popCount >= popCap - buffer) or
    (popCap == 0 and hasBase and popCount >= buffer)

proc canStartBuilderPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                                   agentId: int, state: var AgentState): bool =
  builderHasPlantInputs(agent)

proc optBuilderPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartBuilderDropoffCarrying(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  builderHasDropoffItems(agent)

proc optBuilderDropoffCarrying(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  let (didDrop, dropAct) = controller.dropoffCarrying(
    env, agent, agentId, state,
    allowFood = true,
    allowWood = true,
    allowStone = true,
    allowGold = true
  )
  if didDrop: return dropAct
  0'u8

proc canStartBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent.agentId)
  builderNeedsPopCap(env, teamId)

proc optBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  let (didHouse, houseAct) =
    tryBuildHouseForPopCap(controller, env, agent, agentId, state, teamId, basePos)
  if didHouse: return houseAct
  0'u8

proc canStartBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                       agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent.agentId)
  for kind in [Granary, LumberCamp, Quarry, MiningCamp]:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      return true
  false

proc optBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  for kind in [Granary, LumberCamp, Quarry, MiningCamp]:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act
  0'u8

proc canStartBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                     agentId: int, state: var AgentState): bool =
  if agent.homeAltar.x >= 0 and
      max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) <= 10:
    return false
  let teamId = getTeamId(agent.agentId)
  let resourceCount =
    countNearbyThings(env, agent.pos, 4, {Wheat, Stubble}) +
      countNearbyTerrain(env, agent.pos, 4, {Fertile})
  if resourceCount < 8:
    return false
  nearestFriendlyBuildingDistance(env, teamId, [Mill, Granary, TownCenter], agent.pos) > 5

proc optBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let (didMill, actMill) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, Mill,
    countNearbyThings(env, agent.pos, 4, {Wheat, Stubble}) +
      countNearbyTerrain(env, agent.pos, 4, {Fertile}),
    8,
    [Mill, Granary, TownCenter], 5
  )
  if didMill: return actMill
  0'u8

proc canStartBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if not builderHasPlantInputs(agent):
    return false
  let teamId = getTeamId(agent.agentId)
  controller.getBuildingCount(env, teamId, Mill) >= 2

proc optBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartBuilderCampThreshold(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent.agentId)
  for entry in [
    (LumberCamp, {Tree}, 6),
    (MiningCamp, {Gold}, 6),
    (Quarry, {Stone, Stalagmite}, 6)
  ]:
    let (kind, nearbyKinds, minCount) = entry
    let nearbyCount = countNearbyThings(env, agent.pos, 4, nearbyKinds)
    if nearbyCount < minCount:
      continue
    let dist = nearestFriendlyBuildingDistance(env, teamId, [kind], agent.pos)
    if dist > 3:
      return true
  false

proc optBuilderCampThreshold(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
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
  0'u8

proc canStartBuilderTechBuildings(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent.agentId)
  for kind in [WeavingLoom, ClayOven, Blacksmith,
               Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
               Outpost, Castle]:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      return true
  false

proc optBuilderTechBuildings(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  for kind in [WeavingLoom, ClayOven, Blacksmith,
               Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
               Outpost, Castle]:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act
  0'u8

proc canStartBuilderWallRing(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent.agentId)
  agent.homeAltar.x >= 0 and
    controller.getBuildingCount(env, teamId, LumberCamp) > 0 and
    env.stockpileCount(teamId, ResourceWood) >= 3

proc optBuilderWallRing(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
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
                    env.canPlace(outpostPos):
                  outpostTarget = outpostPos
              if doorTarget.x < 0 and env.canPlace(pos):
                doorTarget = pos
            elif wallTarget.x < 0 and env.canPlace(pos):
              wallTarget = pos
    let buildDoorFirst = if doorTarget.x >= 0 and wallTarget.x >= 0:
      (env.currentStep mod 2) == 0
    else:
      doorTarget.x >= 0
    if buildDoorFirst and doorTarget.x >= 0:
      if env.canAffordBuild(agent, thingItem("Door")):
        let (didDoor, actDoor) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
        )
        if didDoor: return actDoor
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if outpostTarget.x >= 0:
      if env.canAffordBuild(agent, thingItem("Outpost")):
        let (didOutpost, actOutpost) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, outpostTarget, buildIndexFor(Outpost)
        )
        if didOutpost: return actOutpost
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
    if (not buildDoorFirst) and wallTarget.x >= 0:
      if env.canAffordBuild(agent, thingItem("Wall")):
        let (did, act) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, wallTarget, BuildIndexWall
        )
        if did: return act
      else:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
  0'u8

proc canStartBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent.agentId)
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  var best = food
  if wood < best:
    best = wood
  if stone < best:
    best = stone
  best < 5

proc optBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  var targetRes = ResourceFood
  var best = food
  if wood < best:
    best = wood
    targetRes = ResourceWood
  if stone < best:
    best = stone
    targetRes = ResourceStone
  if best < 5:
    case targetRes
    of ResourceFood:
      let (didFood, actFood) = controller.ensureWheat(env, agent, agentId, state)
      if didFood: return actFood
    of ResourceWood:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
    of ResourceStone:
      let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
      if didStone: return actStone
    else:
      discard
  0'u8

proc optBuilderFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

let BuilderOptions = [
  OptionDef(
    name: "BuilderPlantOnFertile",
    canStart: canStartBuilderPlantOnFertile,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderPlantOnFertile,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderDropoffCarrying",
    canStart: canStartBuilderDropoffCarrying,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderDropoffCarrying,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderPopCap",
    canStart: canStartBuilderPopCap,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderPopCap,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderCoreInfrastructure",
    canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderCoreInfrastructure,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderMillNearResource",
    canStart: canStartBuilderMillNearResource,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderMillNearResource,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderPlantIfMills",
    canStart: canStartBuilderPlantIfMills,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderPlantIfMills,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderCampThreshold",
    canStart: canStartBuilderCampThreshold,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderCampThreshold,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderTechBuildings",
    canStart: canStartBuilderTechBuildings,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderTechBuildings,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderWallRing",
    canStart: canStartBuilderWallRing,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderWallRing,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderGatherScarce",
    canStart: canStartBuilderGatherScarce,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderGatherScarce,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderFallbackSearch",
    canStart: optionsAlwaysCanStart,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderFallbackSearch,
    interruptible: true
  )
]

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  return runOptions(controller, env, agent, agentId, state, BuilderOptions)
