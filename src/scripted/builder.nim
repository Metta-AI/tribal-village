import coordination

const
  CoreInfrastructureKinds = [Granary, LumberCamp, Quarry, MiningCamp]
  TechBuildingKinds = [
    WeavingLoom, ClayOven, Blacksmith,
    Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
    Outpost, Castle, Market, Monastery
  ]
  # Coordination-requested building priority
  DefenseRequestBuildingKinds = [Barracks, Outpost]  # Buildings to prioritize when defense requested
  CampThresholds: array[3, tuple[kind: ThingKind, nearbyKinds: set[ThingKind], minCount: int]] = [
    (kind: LumberCamp, nearbyKinds: {Tree}, minCount: 6),
    (kind: MiningCamp, nearbyKinds: {Gold}, minCount: 6),
    (kind: Quarry, nearbyKinds: {Stone, Stalagmite}, minCount: 6)
  ]
  BuilderThreatRadius* = 15  # Distance from home altar to consider "under threat"
  BuilderFleeRadius* = 8    # Radius at which builders flee from enemies (same as gatherer)

proc getTotalBuildingCount(controller: Controller, env: Environment, teamId: int): int =
  ## Count total buildings for a team using the public getBuildingCount API.
  for kind in ThingKind:
    if isBuildingKind(kind):
      result += controller.getBuildingCount(env, teamId, kind)

proc calculateWallRingRadius(controller: Controller, env: Environment, teamId: int): int =
  ## Calculate adaptive wall radius based on building count.
  ## Starts at WallRingBaseRadius and grows by 1 for every WallRingBuildingsPerRadius buildings.
  let totalBuildings = getTotalBuildingCount(controller, env, teamId)
  let extraRadius = totalBuildings div WallRingBuildingsPerRadius
  result = min(WallRingMaxRadius, WallRingBaseRadius + extraRadius)

proc isBuilderUnderThreat*(env: Environment, agent: Thing): bool =
  ## Check if builder's home area is under threat (enemy agent/building within BuilderThreatRadius).
  let teamId = getTeamId(agent)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  if not findNearestEnemyAgentSpatial(env, basePos, teamId, BuilderThreatRadius).isNil:
    return true
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind): continue
    if thing.teamId < 0 or thing.teamId == teamId: continue
    if int(chebyshevDist(basePos, thing.pos)) <= BuilderThreatRadius:
      return true
  false

proc canStartBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  not isNil(findNearestEnemyAgentSpatial(env, agent.pos, getTeamId(agent), BuilderFleeRadius))

proc shouldTerminateBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  isNil(findNearestEnemyAgentSpatial(env, agent.pos, getTeamId(agent), BuilderFleeRadius))

proc optBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  ## Flee toward home altar when enemies are nearby.
  if isNil(findNearestEnemyAgentSpatial(env, agent.pos, getTeamId(agent), BuilderFleeRadius)):
    return 0'u8
  state.basePosition = agent.getBasePos()
  controller.moveTo(env, agent, agentId, state, state.basePosition)

proc findDamagedBuilding*(env: Environment, agent: Thing): Thing =
  ## Find nearest damaged friendly building (including walls/doors) that needs repair.
  let teamId = getTeamId(agent)
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or thing.teamId != teamId: continue
    if not (isBuildingKind(thing.kind) or thing.kind in {Wall, Door}): continue
    if thing.maxHp <= 0 or thing.hp >= thing.maxHp: continue
    let dist = int(chebyshevDist(thing.pos, agent.pos))
    if dist < bestDist:
      bestDist = dist
      result = thing

proc canStartBuilderRepair(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  not isNil(findDamagedBuilding(env, agent))

proc shouldTerminateBuilderRepair(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  isNil(findDamagedBuilding(env, agent))

proc optBuilderRepair(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  ## Move to and repair a damaged friendly building.
  let building = findDamagedBuilding(env, agent)
  if isNil(building):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)

proc anyMissingBuilding(controller: Controller, env: Environment, teamId: int,
                        kinds: openArray[ThingKind]): bool =
  for kind in kinds:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      return true
  false

proc buildFirstMissing(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState, teamId: int,
                       kinds: openArray[ThingKind]): uint8 =
  for kind in kinds:
    let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
    if did: return act
  0'u8

template millResourceCount(env: Environment, pos: IVec2): int =
  countNearbyThings(env, pos, 4, {Wheat, Stubble}) +
    countNearbyTerrain(env, pos, 4, {Fertile})

proc canStartBuilderPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                                   agentId: int, state: var AgentState): bool =
  agent.inventoryWheat > 0 or agent.inventoryWood > 0

proc shouldTerminateBuilderPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                                          agentId: int, state: var AgentState): bool =
  not canStartBuilderPlantOnFertile(controller, env, agent, agentId, state)

proc optBuilderPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartBuilderDropoffCarrying(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and (isFoodItem(key) or isStockpileResourceKey(key)):
      return true
  false

proc shouldTerminateBuilderDropoffCarrying(controller: Controller, env: Environment, agent: Thing,
                                           agentId: int, state: var AgentState): bool =
  not canStartBuilderDropoffCarrying(controller, env, agent, agentId, state)

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
  let teamId = getTeamId(agent)
  needsPopCapHouse(controller, env, teamId)

proc shouldTerminateBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  not needsPopCapHouse(controller, env, getTeamId(agent))

proc optBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  let (didHouse, houseAct) =
    tryBuildHouseForPopCap(controller, env, agent, agentId, state, teamId, basePos)
  if didHouse: return houseAct
  0'u8

proc canStartBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                       agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  anyMissingBuilding(controller, env, teamId, CoreInfrastructureKinds)

proc shouldTerminateBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                              agentId: int, state: var AgentState): bool =
  not anyMissingBuilding(controller, env, getTeamId(agent), CoreInfrastructureKinds)

proc optBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  buildFirstMissing(controller, env, agent, agentId, state, teamId, CoreInfrastructureKinds)

proc canStartBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                     agentId: int, state: var AgentState): bool =
  if agent.homeAltar.x >= 0 and
      max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) <= 10:
    return false
  let teamId = getTeamId(agent)
  let resourceCount = millResourceCount(env, agent.pos)
  if resourceCount < 8:
    return false
  nearestFriendlyBuildingDistance(env, teamId, [Mill, Granary, TownCenter], agent.pos) > 5

proc shouldTerminateBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                            agentId: int, state: var AgentState): bool =
  not canStartBuilderMillNearResource(controller, env, agent, agentId, state)

proc optBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let (didMill, actMill) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, Mill,
    millResourceCount(env, agent.pos),
    8,
    [Mill, Granary, TownCenter], 5
  )
  if didMill: return actMill
  0'u8

proc canStartBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if agent.inventoryWheat <= 0 and agent.inventoryWood <= 0:
    return false
  let teamId = getTeamId(agent)
  controller.getBuildingCount(env, teamId, Mill) >= 2

proc shouldTerminateBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                                        agentId: int, state: var AgentState): bool =
  agent.inventoryWheat <= 0 and agent.inventoryWood <= 0

proc optBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartBuilderCampThreshold(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  for entry in CampThresholds:
    let nearbyCount = countNearbyThings(env, agent.pos, 4, entry.nearbyKinds)
    if nearbyCount < entry.minCount:
      continue
    let dist = nearestFriendlyBuildingDistance(env, teamId, [entry.kind], agent.pos)
    if dist > 3:
      return true
  false

proc shouldTerminateBuilderCampThreshold(controller: Controller, env: Environment, agent: Thing,
                                         agentId: int, state: var AgentState): bool =
  not canStartBuilderCampThreshold(controller, env, agent, agentId, state)

proc optBuilderCampThreshold(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  for entry in CampThresholds:
    let nearbyCount = countNearbyThings(env, agent.pos, 4, entry.nearbyKinds)
    let (did, act) = controller.tryBuildCampThreshold(
      env, agent, agentId, state, teamId, entry.kind,
      nearbyCount, entry.minCount,
      [entry.kind]
    )
    if did: return act
  0'u8

proc canStartBuilderTechBuildings(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  anyMissingBuilding(controller, env, teamId, TechBuildingKinds)

proc shouldTerminateBuilderTechBuildings(controller: Controller, env: Environment, agent: Thing,
                                         agentId: int, state: var AgentState): bool =
  not anyMissingBuilding(controller, env, getTeamId(agent), TechBuildingKinds)

proc optBuilderTechBuildings(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  buildFirstMissing(controller, env, agent, agentId, state, teamId, TechBuildingKinds)

proc canStartBuilderWallRing(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  agent.homeAltar.x >= 0 and
    controller.getBuildingCount(env, teamId, LumberCamp) > 0 and
    env.stockpileCount(teamId, ResourceWood) >= 3

proc shouldTerminateBuilderWallRing(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  not canStartBuilderWallRing(controller, env, agent, agentId, state)

proc optBuilderWallRing(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  if not canStartBuilderWallRing(controller, env, agent, agentId, state):
    return 0'u8
  let teamId = getTeamId(agent)
  let altarPos = agent.homeAltar
  var wallTarget = ivec2(-1, -1)
  var doorTarget = ivec2(-1, -1)
  var ringDoorCount = 0
  var bestBlocked = int.high
  var bestDist = int.high
  # Calculate adaptive wall radius based on building count
  let baseRadius = calculateWallRingRadius(controller, env, teamId)
  let wallRingRadii = [baseRadius, baseRadius - WallRingRadiusSlack, baseRadius + WallRingRadiusSlack]
  for radius in wallRingRadii:
    var blocked = 0
    var doorCount = 0
    var candidateWall = ivec2(-1, -1)
    var candidateDoor = ivec2(-1, -1)
    var candidateWallDist = int.high
    var candidateDoorDist = int.high
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let pos = altarPos + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          inc blocked
          continue
        let posTerrain = env.terrain[pos.x][pos.y]
        if posTerrain == TerrainRoad or isRampTerrain(posTerrain):
          inc blocked
          continue
        let wallThing = env.getThing(pos)
        if not isNil(wallThing) and wallThing.kind == Wall:
          continue
        let doorThing = env.getBackgroundThing(pos)
        if not isNil(doorThing) and doorThing.kind == Door:
          inc doorCount
          continue
        if not env.canPlace(pos):
          inc blocked
          continue
        let dist = int(chebyshevDist(agent.pos, pos))
        let isDoorSlot = (dx == 0 or dy == 0 or abs(dx) == abs(dy))
        if isDoorSlot:
          if dist < candidateDoorDist:
            candidateDoorDist = dist
            candidateDoor = pos
        else:
          if dist < candidateWallDist:
            candidateWallDist = dist
            candidateWall = pos
    let candidateDist = min(candidateWallDist, candidateDoorDist)
    if candidateWall.x < 0 and candidateDoor.x < 0:
      continue
    if blocked < bestBlocked or (blocked == bestBlocked and candidateDist < bestDist):
      bestBlocked = blocked
      bestDist = candidateDist
      wallTarget = candidateWall
      doorTarget = candidateDoor
      ringDoorCount = doorCount
  if wallTarget.x >= 0:
    if env.canAffordBuild(agent, thingItem("Wall")):
      let (did, act) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, wallTarget, BuildIndexWall
      )
      if did: return act
    else:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
  if doorTarget.x >= 0:
    if ringDoorCount < WallRingMaxDoors and env.canAffordBuild(agent, thingItem("Door")):
      let (didDoor, actDoor) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, doorTarget, BuildIndexDoor
      )
      if didDoor: return actDoor
    if env.canAffordBuild(agent, thingItem("Wall")):
      let (didWall, actWall) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, doorTarget, BuildIndexWall
      )
      if didWall: return actWall
    else:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
  0'u8

proc canStartBuilderDefenseResponse(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  builderShouldPrioritizeDefense(teamId) and anyMissingBuilding(controller, env, teamId, DefenseRequestBuildingKinds)

proc shouldTerminateBuilderDefenseResponse(controller: Controller, env: Environment, agent: Thing,
                                           agentId: int, state: var AgentState): bool =
  not canStartBuilderDefenseResponse(controller, env, agent, agentId, state)

proc optBuilderDefenseResponse(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  ## Build military/defensive structures in response to coordination request
  let teamId = getTeamId(agent)
  for kind in DefenseRequestBuildingKinds:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, kind)
      if did:
        # Mark the defense request as fulfilled once we start building
        markDefenseRequestFulfilled(teamId)
        return act
  0'u8

proc canStartBuilderSiegeResponse(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  hasSiegeBuildRequest(teamId) and controller.getBuildingCount(env, teamId, SiegeWorkshop) == 0

proc shouldTerminateBuilderSiegeResponse(controller: Controller, env: Environment, agent: Thing,
                                         agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  not hasSiegeBuildRequest(teamId) or controller.getBuildingCount(env, teamId, SiegeWorkshop) > 0

proc optBuilderSiegeResponse(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  ## Build siege workshop in response to coordination request
  let teamId = getTeamId(agent)
  let (did, act) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, SiegeWorkshop)
  if did:
    markSiegeBuildRequestFulfilled(teamId)
    return act
  0'u8

proc minBasicStockpile(env: Environment, teamId: int): int =
  min(env.stockpileCount(teamId, ResourceFood),
      min(env.stockpileCount(teamId, ResourceWood), env.stockpileCount(teamId, ResourceStone)))

proc canStartBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and minBasicStockpile(env, getTeamId(agent)) < 5

proc shouldTerminateBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                                        agentId: int, state: var AgentState): bool =
  agent.unitClass != UnitVillager or minBasicStockpile(env, getTeamId(agent)) >= 5

proc optBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
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

proc canStartBuilderVisitTradingHub(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  if agent.inventory.len != 0:
    return false
  let hub = findNearestNeutralHub(env, agent.pos)
  not isNil(hub) and chebyshevDist(agent.pos, hub.pos) > 6'i32

proc shouldTerminateBuilderVisitTradingHub(controller: Controller, env: Environment, agent: Thing,
                                           agentId: int, state: var AgentState): bool =
  not canStartBuilderVisitTradingHub(controller, env, agent, agentId, state)

proc optBuilderVisitTradingHub(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  let hub = findNearestNeutralHub(env, agent.pos)
  if isNil(hub) or isAdjacent(agent.pos, hub.pos): return 0'u8
  controller.moveTo(env, agent, agentId, state, hub.pos)

proc optBuilderFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

# Shared option constants for options identical between BuilderOptions and BuilderOptionsThreat
let
  OptFlee = OptionDef(name: "BuilderFlee", canStart: canStartBuilderFlee,
    shouldTerminate: shouldTerminateBuilderFlee, act: optBuilderFlee, interruptible: false)
  OptPlantOnFertile = OptionDef(name: "BuilderPlantOnFertile",
    canStart: canStartBuilderPlantOnFertile, shouldTerminate: shouldTerminateBuilderPlantOnFertile,
    act: optBuilderPlantOnFertile, interruptible: true)
  OptMillNearResource = OptionDef(name: "BuilderMillNearResource",
    canStart: canStartBuilderMillNearResource, shouldTerminate: shouldTerminateBuilderMillNearResource,
    act: optBuilderMillNearResource, interruptible: true)
  OptPlantIfMills = OptionDef(name: "BuilderPlantIfMills",
    canStart: canStartBuilderPlantIfMills, shouldTerminate: shouldTerminateBuilderPlantIfMills,
    act: optBuilderPlantIfMills, interruptible: true)
  OptCampThreshold = OptionDef(name: "BuilderCampThreshold",
    canStart: canStartBuilderCampThreshold, shouldTerminate: shouldTerminateBuilderCampThreshold,
    act: optBuilderCampThreshold, interruptible: true)
  OptRepair = OptionDef(name: "BuilderRepair", canStart: canStartBuilderRepair,
    shouldTerminate: shouldTerminateBuilderRepair, act: optBuilderRepair, interruptible: true)
  OptWallRing = OptionDef(name: "BuilderWallRing", canStart: canStartBuilderWallRing,
    shouldTerminate: shouldTerminateBuilderWallRing, act: optBuilderWallRing, interruptible: true)
  OptDefenseResponse = OptionDef(name: "BuilderDefenseResponse",
    canStart: canStartBuilderDefenseResponse, shouldTerminate: shouldTerminateBuilderDefenseResponse,
    act: optBuilderDefenseResponse, interruptible: true)
  OptSiegeResponse = OptionDef(name: "BuilderSiegeResponse",
    canStart: canStartBuilderSiegeResponse, shouldTerminate: shouldTerminateBuilderSiegeResponse,
    act: optBuilderSiegeResponse, interruptible: true)
  OptMarketTrade = OptionDef(name: "BuilderMarketTrade", canStart: canStartMarketTrade,
    shouldTerminate: shouldTerminateMarketTrade, act: optMarketTrade, interruptible: true)
  OptVisitTradingHub = OptionDef(name: "BuilderVisitTradingHub",
    canStart: canStartBuilderVisitTradingHub, shouldTerminate: shouldTerminateBuilderVisitTradingHub,
    act: optBuilderVisitTradingHub, interruptible: true)
  OptFallbackSearch = OptionDef(name: "BuilderFallbackSearch",
    canStart: optionsAlwaysCanStart, shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderFallbackSearch, interruptible: true)

let BuilderOptions* = [
  OptFlee, EmergencyHealOption, OptPlantOnFertile,
  OptionDef(name: "BuilderDropoffCarrying", canStart: canStartBuilderDropoffCarrying,
    shouldTerminate: shouldTerminateBuilderDropoffCarrying, act: optBuilderDropoffCarrying, interruptible: true),
  OptionDef(name: "BuilderPopCap", canStart: canStartBuilderPopCap,
    shouldTerminate: shouldTerminateBuilderPopCap, act: optBuilderPopCap, interruptible: true),
  OptionDef(name: "BuilderCoreInfrastructure", canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: shouldTerminateBuilderCoreInfrastructure, act: optBuilderCoreInfrastructure, interruptible: true),
  OptMillNearResource, OptPlantIfMills, OptCampThreshold, OptRepair,
  OptionDef(name: "BuilderTechBuildings", canStart: canStartBuilderTechBuildings,
    shouldTerminate: shouldTerminateBuilderTechBuildings, act: optBuilderTechBuildings, interruptible: true),
  OptDefenseResponse, OptSiegeResponse, OptWallRing,
  OptionDef(name: "BuilderGatherScarce", canStart: canStartBuilderGatherScarce,
    shouldTerminate: shouldTerminateBuilderGatherScarce, act: optBuilderGatherScarce, interruptible: true),
  OptMarketTrade, OptVisitTradingHub,
  SmeltGoldOption, CraftBreadOption, StoreValuablesOption, OptFallbackSearch
]

# BuilderOptionsThreat: Reordered priorities for when under threat.
# Threat order: Flee -> WallRing -> Defense -> TechBuildings -> Infrastructure
let BuilderOptionsThreat* = [
  OptFlee, EmergencyHealOption, OptPlantOnFertile,
  # Threat mode: use optionsAlwaysTerminate for faster task switching
  OptionDef(name: "BuilderDropoffCarrying", canStart: canStartBuilderDropoffCarrying,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderDropoffCarrying, interruptible: true),
  OptionDef(name: "BuilderPopCap", canStart: canStartBuilderPopCap,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderPopCap, interruptible: true),
  OptWallRing, OptDefenseResponse, OptSiegeResponse, OptRepair,
  OptionDef(name: "BuilderTechBuildings", canStart: canStartBuilderTechBuildings,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderTechBuildings, interruptible: true),
  OptionDef(name: "BuilderCoreInfrastructure", canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderCoreInfrastructure, interruptible: true),
  OptMillNearResource, OptPlantIfMills, OptCampThreshold,
  OptionDef(name: "BuilderGatherScarce", canStart: canStartBuilderGatherScarce,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderGatherScarce, interruptible: true),
  OptMarketTrade, OptVisitTradingHub,
  SmeltGoldOption, CraftBreadOption, StoreValuablesOption, OptFallbackSearch
]
