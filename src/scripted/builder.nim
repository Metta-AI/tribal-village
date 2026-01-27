const
  WallRingBaseRadius = 5       # Starting radius for small villages
  WallRingMaxRadius = 12       # Maximum wall ring radius
  WallRingBuildingsPerRadius = 4  # Buildings needed to increase radius by 1
  WallRingRadiusSlack = 1
  WallRingMaxDoors = 2
  CoreInfrastructureKinds = [Granary, LumberCamp, Quarry, MiningCamp]
  TechBuildingKinds = [
    WeavingLoom, ClayOven, Blacksmith,
    Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
    Outpost, Castle, Market, Monastery
  ]
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
  ## Check if the builder's home area is under threat from enemies.
  ## Returns true if any enemy agent or building is within BuilderThreatRadius of home altar.
  let teamId = getTeamId(agent)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  # Check for enemy agents
  for other in env.agents:
    if not isAgentAlive(env, other):
      continue
    let otherTeamId = getTeamId(other)
    if otherTeamId == teamId or otherTeamId < 0:
      continue
    let dist = int(chebyshevDist(basePos, other.pos))
    if dist <= BuilderThreatRadius:
      return true
  # Check for enemy buildings
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if thing.teamId < 0 or thing.teamId == teamId:
      continue
    let dist = int(chebyshevDist(basePos, thing.pos))
    if dist <= BuilderThreatRadius:
      return true
  false

proc builderFindNearbyEnemy(env: Environment, agent: Thing): Thing =
  ## Find nearest enemy agent within flee radius
  let teamId = getTeamId(agent)
  let fleeRadius = BuilderFleeRadius.int32
  var bestEnemyDist = int.high
  var bestEnemy: Thing = nil
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) == teamId:
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist > fleeRadius.int:
      continue
    if dist < bestEnemyDist:
      bestEnemyDist = dist
      bestEnemy = other
  bestEnemy

proc canStartBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  not isNil(builderFindNearbyEnemy(env, agent))

proc shouldTerminateBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  isNil(builderFindNearbyEnemy(env, agent))

proc optBuilderFlee(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  ## Flee toward home altar when enemies are nearby.
  ## This causes builders to abandon construction when threatened.
  let enemy = builderFindNearbyEnemy(env, agent)
  if isNil(enemy):
    return 0'u8
  # Move toward home altar for safety
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  controller.moveTo(env, agent, agentId, state, basePos)

proc findDamagedBuilding*(env: Environment, agent: Thing): Thing =
  ## Find nearest damaged friendly building that needs repair.
  ## Returns nil if no damaged building found.
  ## Includes walls and doors which have hp but aren't in BuildingRegistry.
  let teamId = getTeamId(agent)
  var best: Thing = nil
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil:
      continue
    # Check if it's a repairable structure (building, wall, or door)
    let isRepairable = isBuildingKind(thing.kind) or thing.kind in {Wall, Door}
    if not isRepairable:
      continue
    if thing.teamId != teamId:
      continue
    if thing.maxHp <= 0 or thing.hp >= thing.maxHp:
      continue  # Not damaged or doesn't have hp
    let dist = int(chebyshevDist(thing.pos, agent.pos))
    if dist < bestDist:
      bestDist = dist
      best = thing
  best

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
  # Terminate when no longer carrying resources
  for key, count in agent.inventory.pairs:
    if count > 0 and (isFoodItem(key) or isStockpileResourceKey(key)):
      return false
  true

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
  needsPopCapHouse(env, teamId)

proc shouldTerminateBuilderPopCap(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  # Terminate when pop cap house no longer needed
  let teamId = getTeamId(agent)
  not needsPopCapHouse(env, teamId)

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
  # Terminate when all core infrastructure is built
  let teamId = getTeamId(agent)
  not anyMissingBuilding(controller, env, teamId, CoreInfrastructureKinds)

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
  # Terminate when all tech buildings are built
  let teamId = getTeamId(agent)
  not anyMissingBuilding(controller, env, teamId, TechBuildingKinds)

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

proc canStartBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  var best = food
  if wood < best:
    best = wood
  if stone < best:
    best = stone
  best < 5

proc shouldTerminateBuilderGatherScarce(controller: Controller, env: Environment, agent: Thing,
                                        agentId: int, state: var AgentState): bool =
  # Terminate when resources are no longer scarce or not a villager
  if agent.unitClass != UnitVillager:
    return true
  let teamId = getTeamId(agent)
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  var best = food
  if wood < best:
    best = wood
  if stone < best:
    best = stone
  best >= 5

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

proc optBuilderVisitTradingHub(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  let hub = findNearestNeutralHub(env, agent.pos)
  if isNil(hub):
    return 0'u8
  if isAdjacent(agent.pos, hub.pos):
    return 0'u8
  controller.moveTo(env, agent, agentId, state, hub.pos)

proc optBuilderFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

let BuilderOptions* = [
  OptionDef(
    name: "BuilderFlee",
    canStart: canStartBuilderFlee,
    shouldTerminate: shouldTerminateBuilderFlee,
    act: optBuilderFlee,
    interruptible: false  # Flee is not interruptible - survival is priority
  ),
  EmergencyHealOption,
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
    shouldTerminate: shouldTerminateBuilderDropoffCarrying,
    act: optBuilderDropoffCarrying,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderPopCap",
    canStart: canStartBuilderPopCap,
    shouldTerminate: shouldTerminateBuilderPopCap,
    act: optBuilderPopCap,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderCoreInfrastructure",
    canStart: canStartBuilderCoreInfrastructure,
    shouldTerminate: shouldTerminateBuilderCoreInfrastructure,
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
    name: "BuilderRepair",
    canStart: canStartBuilderRepair,
    shouldTerminate: shouldTerminateBuilderRepair,
    act: optBuilderRepair,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderTechBuildings",
    canStart: canStartBuilderTechBuildings,
    shouldTerminate: shouldTerminateBuilderTechBuildings,
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
    shouldTerminate: shouldTerminateBuilderGatherScarce,
    act: optBuilderGatherScarce,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderMarketTrade",
    canStart: canStartMarketTrade,
    shouldTerminate: optionsAlwaysTerminate,
    act: optMarketTrade,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderVisitTradingHub",
    canStart: canStartBuilderVisitTradingHub,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderVisitTradingHub,
    interruptible: true
  ),
  SmeltGoldOption,
  CraftBreadOption,
  StoreValuablesOption,
  OptionDef(
    name: "BuilderFallbackSearch",
    canStart: optionsAlwaysCanStart,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderFallbackSearch,
    interruptible: true
  )
]

# BuilderOptionsThreat: Reordered priorities for when under threat.
# Priority order: Flee -> WallRing -> TechBuildings -> Infrastructure
# (vs safe mode: Flee -> Infrastructure -> TechBuildings -> WallRing)
let BuilderOptionsThreat* = [
  OptionDef(
    name: "BuilderFlee",
    canStart: canStartBuilderFlee,
    shouldTerminate: shouldTerminateBuilderFlee,
    act: optBuilderFlee,
    interruptible: false  # Flee is not interruptible - survival is priority
  ),
  EmergencyHealOption,
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
  # Threat mode: WallRing first (defensive priority)
  OptionDef(
    name: "BuilderWallRing",
    canStart: canStartBuilderWallRing,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderWallRing,
    interruptible: true
  ),
  # Threat mode: Repair second (maintain defensive structures)
  OptionDef(
    name: "BuilderRepair",
    canStart: canStartBuilderRepair,
    shouldTerminate: shouldTerminateBuilderRepair,
    act: optBuilderRepair,
    interruptible: true
  ),
  # Threat mode: TechBuildings third (military capability)
  OptionDef(
    name: "BuilderTechBuildings",
    canStart: canStartBuilderTechBuildings,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderTechBuildings,
    interruptible: true
  ),
  # Threat mode: CoreInfrastructure deprioritized
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
    name: "BuilderGatherScarce",
    canStart: canStartBuilderGatherScarce,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderGatherScarce,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderMarketTrade",
    canStart: canStartMarketTrade,
    shouldTerminate: optionsAlwaysTerminate,
    act: optMarketTrade,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderVisitTradingHub",
    canStart: canStartBuilderVisitTradingHub,
    shouldTerminate: optionsAlwaysTerminate,
    act: optBuilderVisitTradingHub,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderSmeltGold",
    canStart: canStartSmeltGold,
    shouldTerminate: optionsAlwaysTerminate,
    act: optSmeltGold,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderCraftBread",
    canStart: canStartCraftBread,
    shouldTerminate: optionsAlwaysTerminate,
    act: optCraftBread,
    interruptible: true
  ),
  OptionDef(
    name: "BuilderStoreValuables",
    canStart: canStartStoreValuables,
    shouldTerminate: optionsAlwaysTerminate,
    act: optStoreValuables,
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
