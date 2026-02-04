# coordination is already imported by ai_core.nim (included before this file)

template builderGuard(canName, termName: untyped, body: untyped) {.dirty.} =
  ## Generate a canStart/shouldTerminate pair from a single boolean expression.
  ## shouldTerminate is the logical negation of canStart.
  proc canName(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState): bool = body
  proc termName(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): bool = not (body)

const
  CoreInfrastructureKinds = [Granary, LumberCamp, Quarry, MiningCamp]
  TechBuildingKinds = [
    WeavingLoom, ClayOven, Blacksmith,
    Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
    Outpost, Castle, Market, Monastery
  ]
  DefenseRequestBuildingKinds = [Barracks, Outpost]
  CampThresholds: array[3, tuple[kind: ThingKind, nearbyKinds: set[ThingKind], minCount: int]] = [
    (kind: LumberCamp, nearbyKinds: {Tree}, minCount: 6),
    (kind: MiningCamp, nearbyKinds: {Gold}, minCount: 6),
    (kind: Quarry, nearbyKinds: {Stone, Stalagmite}, minCount: 6)
  ]
  BuilderThreatRadius* = 15
  BuilderFleeRadius* = 8
  BuilderFleeRadiusConst = BuilderFleeRadius

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
  ## Check if the builder's home area is under threat from enemies.
  let teamId = getTeamId(agent)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  let nearestEnemy = findNearestEnemyAgentSpatial(env, basePos, teamId, BuilderThreatRadius)
  if not nearestEnemy.isNil:
    return true
  not findNearestEnemyBuildingSpatial(env, basePos, teamId, BuilderThreatRadius).isNil

builderGuard(canStartBuilderFlee, shouldTerminateBuilderFlee):
  not isNil(findNearbyEnemyForFlee(env, agent, BuilderFleeRadiusConst))

proc optBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  ## Flee toward home altar when enemies are nearby.
  ## This causes builders to abandon construction when threatened.
  let enemy = findNearbyEnemyForFlee(env, agent, BuilderFleeRadiusConst)
  if isNil(enemy):
    return 0'u8
  # Move toward home altar for safety
  fleeToBase(controller, env, agent, agentId, state)

proc refreshDamagedBuildingCache*(controller: Controller, env: Environment) =
  ## Refresh the per-team damaged building cache if stale.
  ## Called once per step, caches all damaged building positions by team.
  if controller.damagedBuildingCacheStep == env.currentStep:
    return  # Cache is fresh
  controller.damagedBuildingCacheStep = env.currentStep
  # Clear counts
  for t in 0 ..< MapRoomObjectsTeams:
    controller.damagedBuildingCounts[t] = 0
  # Optimized: iterate only building kinds via thingsByKind instead of all env.things
  # TeamBuildingKinds already includes Wall and Door
  for bKind in TeamBuildingKinds:
    for thing in env.thingsByKind[bKind]:
      if thing.teamId < 0 or thing.teamId >= MapRoomObjectsTeams:
        continue
      if thing.maxHp <= 0 or thing.hp >= thing.maxHp:
        continue  # Not damaged or doesn't have hp
      let t = thing.teamId
      if controller.damagedBuildingCounts[t] < MaxDamagedBuildingsPerTeam:
        controller.damagedBuildingPositions[t][controller.damagedBuildingCounts[t]] = thing.pos
        controller.damagedBuildingCounts[t] += 1

proc findDamagedBuilding*(controller: Controller, env: Environment, agent: Thing): Thing =
  ## Find nearest damaged friendly building that needs repair.
  ## Returns nil if no damaged building found.
  ## Uses per-step cache to avoid redundant O(n) scans of env.things.
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return nil
  # Ensure cache is fresh
  refreshDamagedBuildingCache(controller, env)
  # Find nearest from cached positions
  var best: Thing = nil
  var bestDist = int.high
  for i in 0 ..< controller.damagedBuildingCounts[teamId]:
    let pos = controller.damagedBuildingPositions[teamId][i]
    let thing = env.getThing(pos)
    if thing.isNil:
      # Also check background grid for doors
      let bgThing = env.getBackgroundThing(pos)
      if bgThing.isNil:
        continue
      if bgThing.maxHp <= 0 or bgThing.hp >= bgThing.maxHp:
        continue  # No longer damaged
      let dist = int(chebyshevDist(pos, agent.pos))
      if dist < bestDist:
        bestDist = dist
        best = bgThing
    else:
      # Verify still damaged (may have been repaired since cache was built)
      if thing.maxHp <= 0 or thing.hp >= thing.maxHp:
        continue
      let dist = int(chebyshevDist(pos, agent.pos))
      if dist < bestDist:
        bestDist = dist
        best = thing
  best

builderGuard(canStartBuilderRepair, shouldTerminateBuilderRepair):
  not isNil(findDamagedBuilding(controller, env, agent))

proc optBuilderRepair(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  ## Move to and repair a damaged friendly building.
  let building = findDamagedBuilding(controller, env, agent)
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

builderGuard(canStartBuilderPlantOnFertile, shouldTerminateBuilderPlantOnFertile):
  agent.inventoryWheat > 0 or agent.inventoryWood > 0

proc hasCarryingResources(agent: Thing): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and (isFoodItem(key) or isStockpileResourceKey(key)):
      return true
  false

builderGuard(canStartBuilderDropoffCarrying, shouldTerminateBuilderDropoffCarrying):
  hasCarryingResources(agent)

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

builderGuard(canStartBuilderPopCap, shouldTerminateBuilderPopCap):
  needsPopCapHouse(controller, env, getTeamId(agent))

proc optBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  let (didHouse, houseAct) =
    tryBuildHouseForPopCap(controller, env, agent, agentId, state, teamId, basePos)
  if didHouse: return houseAct
  0'u8

builderGuard(canStartBuilderCoreInfrastructure, shouldTerminateBuilderCoreInfrastructure):
  anyMissingBuilding(controller, env, getTeamId(agent), CoreInfrastructureKinds)

proc optBuilderCoreInfrastructure(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  buildFirstMissing(controller, env, agent, agentId, state, teamId, CoreInfrastructureKinds)

proc millResourceCount(env: Environment, pos: IVec2): int =
  countNearbyThings(env, pos, 4, {Wheat, Stubble}) + countNearbyTerrain(env, pos, 4, {Fertile})

proc canStartBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                     agentId: int, state: var AgentState): bool =
  if agent.homeAltar.x >= 0 and
      max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) <= 10:
    return false
  let teamId = getTeamId(agent)
  if millResourceCount(env, agent.pos) < 8:
    return false
  nearestFriendlyBuildingDistance(env, teamId, [Mill, Granary, TownCenter], agent.pos) > 5

proc shouldTerminateBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                            agentId: int, state: var AgentState): bool =
  not canStartBuilderMillNearResource(controller, env, agent, agentId, state)

proc optBuilderMillNearResource(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let (didMill, actMill) = controller.tryBuildNearResource(
    env, agent, agentId, state, teamId, Mill, millResourceCount(env, agent.pos),
    8, [Mill, Granary, TownCenter], 5)
  if didMill: return actMill
  0'u8

proc canStartBuilderPlantIfMills(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  (agent.inventoryWheat > 0 or agent.inventoryWood > 0) and
    controller.getBuildingCount(env, getTeamId(agent), Mill) >= 2

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
  ## Terminate when camp built nearby or conditions no longer met
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

builderGuard(canStartBuilderTechBuildings, shouldTerminateBuilderTechBuildings):
  anyMissingBuilding(controller, env, getTeamId(agent), TechBuildingKinds)

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

# Coordination-responsive behavior: respond to defense requests by building military structures
proc canStartBuilderDefenseResponse(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  ## Check if there's a defense request and we can respond by building
  let teamId = getTeamId(agent)
  if not builderShouldPrioritizeDefense(teamId):
    return false
  # Check if we're missing any defense buildings
  for kind in DefenseRequestBuildingKinds:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      return true
  false

proc shouldTerminateBuilderDefenseResponse(controller: Controller, env: Environment, agent: Thing,
                                           agentId: int, state: var AgentState): bool =
  ## Terminate when no more defense requests or defense buildings built
  let teamId = getTeamId(agent)
  if not builderShouldPrioritizeDefense(teamId):
    return true
  # Check if all defense buildings exist
  for kind in DefenseRequestBuildingKinds:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      return false
  true

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

proc builderShouldBuildSiege(controller: Controller, env: Environment, teamId: int): bool =
  ## Check if builder should build siege workshop due to request
  if not hasSiegeBuildRequest(teamId):
    return false
  # Only if we don't already have one
  controller.getBuildingCount(env, teamId, SiegeWorkshop) == 0

builderGuard(canStartBuilderSiegeResponse, shouldTerminateBuilderSiegeResponse):
  builderShouldBuildSiege(controller, env, getTeamId(agent))

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
  ## Returns the minimum stockpile count among food, wood, and stone.
  result = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  if wood < result: result = wood
  if stone < result: result = stone

builderGuard(canStartBuilderGatherScarce, shouldTerminateBuilderGatherScarce):
  agent.unitClass == UnitVillager and minBasicStockpile(env, getTeamId(agent)) < 5

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
  if isNil(hub):
    return 0'u8
  if isAdjacent(agent.pos, hub.pos):
    return 0'u8
  controller.moveTo(env, agent, agentId, state, hub.pos)

# Shared OptionDefs used in both BuilderOptions and BuilderOptionsThreat
let BuilderFleeOption = OptionDef(
  name: "BuilderFlee", canStart: canStartBuilderFlee,
  shouldTerminate: shouldTerminateBuilderFlee, act: optBuilderFlee,
  interruptible: false)
let BuilderPlantOnFertileOption = OptionDef(
  name: "BuilderPlantOnFertile", canStart: canStartBuilderPlantOnFertile,
  shouldTerminate: shouldTerminateBuilderPlantOnFertile, act: optPlantOnFertile,
  interruptible: true)
let BuilderWallRingOption = OptionDef(
  name: "BuilderWallRing", canStart: canStartBuilderWallRing,
  shouldTerminate: shouldTerminateBuilderWallRing, act: optBuilderWallRing,
  interruptible: true)
let BuilderDefenseResponseOption = OptionDef(
  name: "BuilderDefenseResponse", canStart: canStartBuilderDefenseResponse,
  shouldTerminate: shouldTerminateBuilderDefenseResponse, act: optBuilderDefenseResponse,
  interruptible: true)
let BuilderSiegeResponseOption = OptionDef(
  name: "BuilderSiegeResponse", canStart: canStartBuilderSiegeResponse,
  shouldTerminate: shouldTerminateBuilderSiegeResponse, act: optBuilderSiegeResponse,
  interruptible: true)
let BuilderRepairOption = OptionDef(
  name: "BuilderRepair", canStart: canStartBuilderRepair,
  shouldTerminate: shouldTerminateBuilderRepair, act: optBuilderRepair,
  interruptible: true)
let BuilderMillNearResourceOption = OptionDef(
  name: "BuilderMillNearResource", canStart: canStartBuilderMillNearResource,
  shouldTerminate: shouldTerminateBuilderMillNearResource, act: optBuilderMillNearResource,
  interruptible: true)
let BuilderPlantIfMillsOption = OptionDef(
  name: "BuilderPlantIfMills", canStart: canStartBuilderPlantIfMills,
  shouldTerminate: shouldTerminateBuilderPlantIfMills, act: optBuilderPlantIfMills,
  interruptible: true)
let BuilderCampThresholdOption = OptionDef(
  name: "BuilderCampThreshold", canStart: canStartBuilderCampThreshold,
  shouldTerminate: shouldTerminateBuilderCampThreshold, act: optBuilderCampThreshold,
  interruptible: true)
let BuilderVisitTradingHubOption = OptionDef(
  name: "BuilderVisitTradingHub", canStart: canStartBuilderVisitTradingHub,
  shouldTerminate: shouldTerminateBuilderVisitTradingHub, act: optBuilderVisitTradingHub,
  interruptible: true)

let BuilderOptions* = [
  BuilderFleeOption,
  EmergencyHealOption,
  BuilderPlantOnFertileOption,
  OptionDef(name: "BuilderDropoffCarrying", canStart: canStartBuilderDropoffCarrying,
    shouldTerminate: shouldTerminateBuilderDropoffCarrying, act: optBuilderDropoffCarrying,
    interruptible: true),
  OptionDef(name: "BuilderPopCap", canStart: canStartBuilderPopCap,
    shouldTerminate: shouldTerminateBuilderPopCap, act: optBuilderPopCap,
    interruptible: true),
  OptionDef(name: "BuilderCoreInfrastructure", canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: shouldTerminateBuilderCoreInfrastructure, act: optBuilderCoreInfrastructure,
    interruptible: true),
  BuilderMillNearResourceOption,
  BuilderPlantIfMillsOption,
  BuilderCampThresholdOption,
  BuilderRepairOption,
  OptionDef(name: "BuilderTechBuildings", canStart: canStartBuilderTechBuildings,
    shouldTerminate: shouldTerminateBuilderTechBuildings, act: optBuilderTechBuildings,
    interruptible: true),
  BuilderDefenseResponseOption,
  BuilderSiegeResponseOption,
  BuilderWallRingOption,
  OptionDef(name: "BuilderGatherScarce", canStart: canStartBuilderGatherScarce,
    shouldTerminate: shouldTerminateBuilderGatherScarce, act: optBuilderGatherScarce,
    interruptible: true),
  MarketTradeOption,
  BuilderVisitTradingHubOption,
  SmeltGoldOption,
  CraftBreadOption,
  StoreValuablesOption,
  FallbackSearchOption
]

# BuilderOptionsThreat: Reordered priorities for when under threat.
# Priority order: Flee -> WallRing -> Defense -> TechBuildings -> Infrastructure
let BuilderOptionsThreat* = [
  BuilderFleeOption,
  EmergencyHealOption,
  BuilderPlantOnFertileOption,
  OptionDef(name: "BuilderDropoffCarrying", canStart: canStartBuilderDropoffCarrying,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderDropoffCarrying,
    interruptible: true),
  OptionDef(name: "BuilderPopCap", canStart: canStartBuilderPopCap,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderPopCap,
    interruptible: true),
  BuilderWallRingOption,        # WallRing prioritized in threat mode
  BuilderDefenseResponseOption,
  BuilderSiegeResponseOption,
  BuilderRepairOption,          # Repair prioritized in threat mode
  OptionDef(name: "BuilderTechBuildings", canStart: canStartBuilderTechBuildings,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderTechBuildings,
    interruptible: true),
  OptionDef(name: "BuilderCoreInfrastructure", canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderCoreInfrastructure,
    interruptible: true),
  BuilderMillNearResourceOption,
  BuilderPlantIfMillsOption,
  BuilderCampThresholdOption,
  OptionDef(name: "BuilderGatherScarce", canStart: canStartBuilderGatherScarce,
    shouldTerminate: optionsAlwaysTerminate, act: optBuilderGatherScarce,
    interruptible: true),
  MarketTradeOption,
  BuilderVisitTradingHubOption,
  SmeltGoldOption,
  CraftBreadOption,
  StoreValuablesOption,
  FallbackSearchOption
]
