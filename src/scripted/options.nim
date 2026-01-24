# Minimal RL-style options: initiation, termination, and per-tick policy step.

proc optionsAlwaysCanStart*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  true

proc optionsAlwaysTerminate*(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

type OptionDef* = object
  name*: string
  canStart*: proc(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): bool
  shouldTerminate*: proc(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool
  act*: proc(controller: Controller, env: Environment, agent: Thing,
             agentId: int, state: var AgentState): uint8
  interruptible*: bool

const
  EnemyWallFortifyRadius = 12

template resetActiveOption(state: var AgentState) =
  state.activeOptionId = -1
  state.activeOptionTicks = 0

proc actOrMove(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState,
               targetPos: IVec2, verb: uint8): uint8 =
  if isAdjacent(agent.pos, targetPos):
    return controller.actAt(env, agent, agentId, state, targetPos, verb)
  controller.moveTo(env, agent, agentId, state, targetPos)

proc runOptions*(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState,
                 roleOptions: openArray[OptionDef]): uint8 =
  let optionCount = roleOptions.len
  # Handle active option first (if any).
  if state.activeOptionId in 0 ..< optionCount:
    let activeIdx = state.activeOptionId
    if roleOptions[activeIdx].interruptible:
      for i in 0 ..< activeIdx:
        if roleOptions[i].canStart(controller, env, agent, agentId, state):
          state.activeOptionId = i
          state.activeOptionTicks = 0
          break
    inc state.activeOptionTicks
    let action = roleOptions[state.activeOptionId].act(
      controller, env, agent, agentId, state)
    if action != 0'u8:
      if roleOptions[state.activeOptionId].shouldTerminate(
          controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  # Otherwise, scan options in priority order and use the first that acts.
  for i, opt in roleOptions:
    if not opt.canStart(controller, env, agent, agentId, state):
      continue
    state.activeOptionId = i
    state.activeOptionTicks = 1
    let action = opt.act(controller, env, agent, agentId, state)
    if action != 0'u8:
      if opt.shouldTerminate(controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  return 0'u8

proc agentHasAnyItem*(agent: Thing, keys: openArray[ItemKey]): bool =
  for key in keys:
    if getInv(agent, key) > 0:
      return true
  false

proc canStartStoreValuables*(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if controller.getBuildingCount(env, teamId, Blacksmith) > 0 and
      agentHasAnyItem(agent, buildingStorageItems(Blacksmith)):
    return true
  if controller.getBuildingCount(env, teamId, Granary) > 0 and
      agentHasAnyItem(agent, buildingStorageItems(Granary)):
    return true
  if controller.getBuildingCount(env, teamId, Barrel) > 0 and
      agentHasAnyItem(agent, buildingStorageItems(Barrel)):
    return true
  false

proc optStoreValuables*(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  var target: Thing = nil
  if agentHasAnyItem(agent, buildingStorageItems(Blacksmith)):
    target = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith)
  if isNil(target) and agentHasAnyItem(agent, buildingStorageItems(Granary)):
    target = env.findNearestFriendlyThingSpiral(state, teamId, Granary)
  if isNil(target) and agentHasAnyItem(agent, buildingStorageItems(Barrel)):
    target = env.findNearestFriendlyThingSpiral(state, teamId, Barrel)
  if isNil(target):
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, target.pos, 3'u8)

proc canStartCraftBread*(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  agent.inventoryWheat > 0 and agent.inventoryBread < MapObjectAgentMaxInventory and
    controller.getBuildingCount(env, teamId, ClayOven) > 0

proc optCraftBread*(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let oven = env.findNearestFriendlyThingSpiral(state, teamId, ClayOven)
  if isNil(oven) or oven.cooldown != 0:
    return 0'u8
  if isAdjacent(agent.pos, oven.pos):
    return controller.useAt(env, agent, agentId, state, oven.pos)
  controller.moveTo(env, agent, agentId, state, oven.pos)

proc canStartSmeltGold*(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): bool =
  agent.inventoryGold > 0 and agent.inventoryBar < MapObjectAgentMaxInventory and
    env.thingsByKind[Magma].len > 0

proc optSmeltGold*(controller: Controller, env: Environment, agent: Thing,
                   agentId: int, state: var AgentState): uint8 =
  state.basePosition = agent.getBasePos()
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
  if didKnown:
    return actKnown
  let magmaGlobal = findNearestThing(env, agent.pos, Magma, maxDist = int.high)
  if isNil(magmaGlobal):
    return 0'u8
  updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
  if isAdjacent(agent.pos, magmaGlobal.pos):
    return controller.useAt(env, agent, agentId, state, magmaGlobal.pos)
  controller.moveTo(env, agent, agentId, state, magmaGlobal.pos)

proc findNearestEnemyBuilding(env: Environment, pos: IVec2, teamId: int): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if thing.teamId < 0 or thing.teamId == teamId:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < bestDist:
      bestDist = dist
      best = thing
  best

proc findNearestEnemyPresence(env: Environment, pos: IVec2,
                              teamId: int): tuple[target: IVec2, dist: int] =
  var bestPos = ivec2(-1, -1)
  var bestDist = int.high
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if getTeamId(agent) == teamId:
      continue
    let dist = int(chebyshevDist(agent.pos, pos))
    if dist < bestDist:
      bestDist = dist
      bestPos = agent.pos
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if thing.teamId < 0 or thing.teamId == teamId:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < bestDist:
      bestDist = dist
      bestPos = thing.pos
  (target: bestPos, dist: bestDist)

proc findNearestNeutralHub(env: Environment, pos: IVec2): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or thing.teamId >= 0 or not isBuildingKind(thing.kind):
      continue
    if thing.kind notin {Castle, Market, Outpost, University, Blacksmith, Barracks,
                         ArcheryRange, Stable, SiegeWorkshop, Monastery, TownCenter,
                         Mill, Granary, LumberCamp, Quarry, MiningCamp, Dock}:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < bestDist:
      bestDist = dist
      best = thing
  best

proc findLanternFrontierCandidate(env: Environment, state: var AgentState,
                                  teamId: int, basePos: IVec2): IVec2 =
  var farthest = 0
  for thing in env.thingsByKind[Lantern]:
    if not thing.lanternHealthy or thing.teamId != teamId:
      continue
    let dist = int(chebyshevDist(basePos, thing.pos))
    if dist > farthest:
      farthest = dist
  let desired = max(ObservationRadius + 2, farthest + 3)
  for _ in 0 ..< 24:
    let candidate = getNextSpiralPoint(state)
    if chebyshevDist(candidate, basePos) < desired:
      continue
    if not isLanternPlacementValid(env, candidate):
      continue
    if hasTeamLanternNear(env, teamId, candidate):
      continue
    return candidate
  ivec2(-1, -1)

proc findLanternGapCandidate(env: Environment, agentPos: IVec2,
                             teamId: int): IVec2 =
  var best = ivec2(-1, -1)
  var bestDist = int.high
  for thing in env.things:
    if thing.isNil or thing.teamId != teamId or not isBuildingKind(thing.kind):
      continue
    if hasTeamLanternNear(env, teamId, thing.pos):
      continue
    for dx in -2 .. 2:
      for dy in -2 .. 2:
        if abs(dx) + abs(dy) > 2:
          continue
        let cand = thing.pos + ivec2(dx.int32, dy.int32)
        if not isLanternPlacementValid(env, cand):
          continue
        if hasTeamLanternNear(env, teamId, cand):
          continue
        let dist = abs(cand.x - agentPos.x).int + abs(cand.y - agentPos.y).int
        if dist < bestDist:
          bestDist = dist
          best = cand
  best

proc findWallChokeCandidate(env: Environment, basePos: IVec2): IVec2 =
  let radius = 8
  for x in max(0, basePos.x.int - radius) .. min(MapWidth - 1, basePos.x.int + radius):
    for y in max(0, basePos.y.int - radius) .. min(MapHeight - 1, basePos.y.int + radius):
      let pos = ivec2(x.int32, y.int32)
      if env.terrain[x][y] == TerrainRoad:
        continue
      if not env.canPlace(pos):
        continue
      let north = env.getThing(pos + ivec2(0, -1))
      let south = env.getThing(pos + ivec2(0, 1))
      let east = env.getThing(pos + ivec2(1, 0))
      let west = env.getThing(pos + ivec2(-1, 0))
      let northDoor = env.getBackgroundThing(pos + ivec2(0, -1))
      let southDoor = env.getBackgroundThing(pos + ivec2(0, 1))
      let eastDoor = env.getBackgroundThing(pos + ivec2(1, 0))
      let westDoor = env.getBackgroundThing(pos + ivec2(-1, 0))
      let northWall = (not isNil(north) and north.kind == Wall) or
        (not isNil(northDoor) and northDoor.kind == Door)
      let southWall = (not isNil(south) and south.kind == Wall) or
        (not isNil(southDoor) and southDoor.kind == Door)
      let eastWall = (not isNil(east) and east.kind == Wall) or
        (not isNil(eastDoor) and eastDoor.kind == Door)
      let westWall = (not isNil(west) and west.kind == Wall) or
        (not isNil(westDoor) and westDoor.kind == Door)
      if northWall or southWall or eastWall or westWall:
        return pos
  ivec2(-1, -1)

proc findDoorChokeCandidate(env: Environment, basePos: IVec2): IVec2 =
  let radius = 8
  for x in max(0, basePos.x.int - radius) .. min(MapWidth - 1, basePos.x.int + radius):
    for y in max(0, basePos.y.int - radius) .. min(MapHeight - 1, basePos.y.int + radius):
      let pos = ivec2(x.int32, y.int32)
      if env.terrain[x][y] == TerrainRoad:
        continue
      if not env.canPlace(pos):
        continue
      let north = env.getThing(pos + ivec2(0, -1))
      let south = env.getThing(pos + ivec2(0, 1))
      let east = env.getThing(pos + ivec2(1, 0))
      let west = env.getThing(pos + ivec2(-1, 0))
      let nsWall = (not isNil(north) and north.kind == Wall) and
                   (not isNil(south) and south.kind == Wall)
      let ewWall = (not isNil(east) and east.kind == Wall) and
                   (not isNil(west) and west.kind == Wall)
      if nsWall or ewWall:
        return pos
  ivec2(-1, -1)

proc findDirectionalBuildPos(env: Environment, basePos: IVec2, targetPos: IVec2,
                             minStep, maxStep: int): IVec2 =
  if targetPos.x < 0:
    return ivec2(-1, -1)
  let dx = signi(targetPos.x - basePos.x)
  let dy = signi(targetPos.y - basePos.y)
  for step in minStep .. maxStep:
    let pos = basePos + ivec2(dx * step.int32, dy * step.int32)
    if not isValidPos(pos):
      continue
    if env.terrain[pos.x][pos.y] == TerrainRoad:
      continue
    if env.canPlace(pos):
      return pos
  ivec2(-1, -1)

proc findIrrigationTarget(env: Environment, center: IVec2, radius: int): IVec2 =
  let (startX, endX, startY, endY) = radiusBounds(center, radius)
  let cx = center.x.int
  let cy = center.y.int
  var bestDist = int.high
  var bestPos = ivec2(-1, -1)
  for x in startX .. endX:
    for y in startY .. endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      if env.terrain[x][y] notin {Empty, Grass, Dune, Sand, Snow}:
        continue
      let pos = ivec2(x.int32, y.int32)
      if not env.isEmpty(pos) or env.hasDoor(pos) or not isNil(env.getBackgroundThing(pos)):
        continue
      if isTileFrozen(pos, env):
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < bestDist:
        bestDist = dist
        bestPos = pos
  bestPos

proc findNearestPredator(env: Environment, pos: IVec2): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for kind in [Bear, Wolf]:
    for thing in env.thingsByKind[kind]:
      let dist = int(chebyshevDist(thing.pos, pos))
      if dist < bestDist:
        bestDist = dist
        best = thing
  best

proc findNearestGoblinStructure(env: Environment, pos: IVec2): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for kind in [GoblinHive, GoblinHut, GoblinTotem]:
    for thing in env.thingsByKind[kind]:
      let dist = int(chebyshevDist(thing.pos, pos))
      if dist < bestDist:
        bestDist = dist
        best = thing
  best

proc canStartLanternFrontierPush(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  agent.inventoryLantern > 0

proc optLanternFrontierPush(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
  let target = findLanternFrontierCandidate(env, state, teamId, basePos)
  if target.x < 0:
    return 0'u8
  if isAdjacent(agent.pos, target):
    return controller.actAt(env, agent, agentId, state, target, 6'u8)
  controller.moveTo(env, agent, agentId, state, target)

proc canStartLanternGapFill(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  agent.inventoryLantern > 0

proc optLanternGapFill(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let target = findLanternGapCandidate(env, agent.pos, teamId)
  if target.x < 0:
    return 0'u8
  if isAdjacent(agent.pos, target):
    return controller.actAt(env, agent, agentId, state, target, 6'u8)
  controller.moveTo(env, agent, agentId, state, target)

proc canStartLanternRecovery(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  agent.inventoryLantern > 0

proc optLanternRecovery(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  # Find frozen edge candidate (inlined)
  var target = ivec2(-1, -1)
  let radius = 8
  block search:
    for x in max(0, basePos.x.int - radius) .. min(MapWidth - 1, basePos.x.int + radius):
      for y in max(0, basePos.y.int - radius) .. min(MapHeight - 1, basePos.y.int + radius):
        let pos = ivec2(x.int32, y.int32)
        if not isTileFrozen(pos, env):
          continue
        for d in AdjacentOffsets8:
          let cand = pos + d
          if isLanternPlacementValid(env, cand):
            target = cand
            break search
  if target.x < 0:
    return 0'u8
  if isAdjacent(agent.pos, target):
    return controller.actAt(env, agent, agentId, state, target, 6'u8)
  controller.moveTo(env, agent, agentId, state, target)

proc canStartLanternLogistics(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.inventoryLantern == 0 and agent.unitClass == UnitVillager

proc optLanternLogistics(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom)
  if agent.inventoryWood > 0 or agent.inventoryWheat > 0:
    if not isNil(loom):
      return (if isAdjacent(agent.pos, loom.pos):
        controller.useAt(env, agent, agentId, state, loom.pos)
      else:
        controller.moveTo(env, agent, agentId, state, loom.pos))
  if agent.inventoryWood == 0:
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
  let (didWheat, actWheat) = controller.ensureWheat(env, agent, agentId, state)
  if didWheat: return actWheat
  0'u8

proc canStartAntiTumorPatrol(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  env.thingsByKind[Tumor].len > 0

proc optAntiTumorPatrol(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let tumor = env.findNearestThingSpiral(state, Tumor)
  if isNil(tumor):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, tumor.pos, 2'u8)

proc canStartSpawnerHunter(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  env.thingsByKind[Spawner].len > 0

proc optSpawnerHunter(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let spawner = env.findNearestThingSpiral(state, Spawner)
  if isNil(spawner):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, spawner.pos, 2'u8)

proc canStartFrozenEdgeBreaker(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): bool =
  for tumor in env.thingsByKind[Tumor]:
    if isTileFrozen(tumor.pos, env):
      return true
    for d in AdjacentOffsets8:
      if isTileFrozen(tumor.pos + d, env):
        return true
  false

proc optFrozenEdgeBreaker(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): uint8 =
  var best: Thing = nil
  var bestDist = int.high
  for tumor in env.thingsByKind[Tumor]:
    var touchesFrozen = isTileFrozen(tumor.pos, env)
    if not touchesFrozen:
      for d in AdjacentOffsets8:
        if isTileFrozen(tumor.pos + d, env):
          touchesFrozen = true
          break
    if not touchesFrozen:
      continue
    let dist = int(chebyshevDist(agent.pos, tumor.pos))
    if dist < bestDist:
      bestDist = dist
      best = tumor
  if isNil(best):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, best.pos, 2'u8)

proc canStartGuardTowerBorder(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("GuardTower"))

proc optGuardTowerBorder(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let enemy = findNearestEnemyBuilding(env, basePos, getTeamId(agent))
  let target = findDirectionalBuildPos(env, basePos,
    (if not isNil(enemy): enemy.pos else: basePos + ivec2(6, 0)), 4, 7)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, buildIndexFor(GuardTower)
  )
  if did: return act
  0'u8

proc canStartOutpostNetwork(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Outpost"))

proc optOutpostNetwork(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let enemy = findNearestEnemyBuilding(env, basePos, getTeamId(agent))
  let target = findDirectionalBuildPos(env, basePos,
    (if not isNil(enemy): enemy.pos else: basePos + ivec2(0, 6)), 3, 6)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, buildIndexFor(Outpost)
  )
  if did: return act
  0'u8

proc canStartEnemyWallFortify(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  if not env.canAffordBuild(agent, thingItem("Wall")):
    return false
  let basePos = agent.getBasePos()
  let (enemyPos, dist) = findNearestEnemyPresence(env, basePos, getTeamId(agent))
  enemyPos.x >= 0 and dist <= EnemyWallFortifyRadius

proc optEnemyWallFortify(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let (enemyPos, dist) = findNearestEnemyPresence(env, basePos, getTeamId(agent))
  if enemyPos.x < 0 or dist > EnemyWallFortifyRadius:
    return 0'u8
  let target = findDirectionalBuildPos(env, basePos, enemyPos, 2, 6)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, BuildIndexWall
  )
  if did: return act
  0'u8

proc canStartWallChokeFortify(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Wall"))

proc optWallChokeFortify(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let target = findWallChokeCandidate(env, basePos)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, BuildIndexWall
  )
  if did: return act
  0'u8

proc canStartDoorChokeFortify(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Door"))

proc optDoorChokeFortify(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let target = findDoorChokeCandidate(env, basePos)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, buildIndexFor(Door)
  )
  if did: return act
  0'u8

proc canStartRoadExpansion(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Road"))

proc optRoadExpansion(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let enemy = findNearestEnemyBuilding(env, basePos, getTeamId(agent))
  let target = findDirectionalBuildPos(env, basePos,
    (if not isNil(enemy): enemy.pos else: basePos + ivec2(8, 0)), 2, 5)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, BuildIndexRoad
  )
  if did: return act
  0'u8

proc canStartCastleAnchor(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Castle"))

proc optCastleAnchor(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let enemy = findNearestEnemyBuilding(env, basePos, getTeamId(agent))
  let target = findDirectionalBuildPos(env, basePos,
    (if not isNil(enemy): enemy.pos else: basePos + ivec2(0, -8)), 5, 9)
  let (did, act) = goToAdjacentAndBuild(
    controller, env, agent, agentId, state, target, buildIndexFor(Castle)
  )
  if did: return act
  0'u8

proc canStartSiegeBreacher(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and
    controller.getBuildingCount(env, getTeamId(agent), SiegeWorkshop) > 0 and
    not isNil(findNearestEnemyBuilding(env, agent.pos, getTeamId(agent))) and
    env.canSpendStockpile(getTeamId(agent), buildingTrainCosts(SiegeWorkshop))

proc optSiegeBreacher(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let building = env.findNearestFriendlyThingSpiral(state, teamId, SiegeWorkshop)
  if isNil(building) or building.cooldown != 0:
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)

proc canStartMangonelSuppression(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and
    controller.getBuildingCount(env, getTeamId(agent), MangonelWorkshop) > 0 and
    env.canSpendStockpile(getTeamId(agent), buildingTrainCosts(MangonelWorkshop))

proc optMangonelSuppression(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let building = env.findNearestFriendlyThingSpiral(state, teamId, MangonelWorkshop)
  if isNil(building) or building.cooldown != 0:
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)

proc canStartUnitPromotionFocus(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  for kind in [Castle, Monastery, Barracks, ArcheryRange, Stable]:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      continue
    if env.canSpendStockpile(teamId, buildingTrainCosts(kind)):
      return true
  false

proc optUnitPromotionFocus(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  for kind in [Castle, Monastery, Barracks, ArcheryRange, Stable]:
    if controller.getBuildingCount(env, teamId, kind) == 0:
      continue
    if not env.canSpendStockpile(teamId, buildingTrainCosts(kind)):
      continue
    let building = env.findNearestFriendlyThingSpiral(state, teamId, kind)
    if isNil(building) or building.cooldown != 0:
      continue
    return actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)
  0'u8

proc canStartRelicRaider(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  agent.inventoryRelic == 0 and env.thingsByKind[Relic].len > 0

proc optRelicRaider(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let relic = env.findNearestThingSpiral(state, Relic)
  if isNil(relic):
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, relic.pos, 3'u8)

proc canStartRelicCourier(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  agent.inventoryRelic > 0

proc optRelicCourier(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let monastery = env.findNearestFriendlyThingSpiral(state, teamId, Monastery)
  let target =
    if not isNil(monastery): monastery.pos
    elif agent.homeAltar.x >= 0: agent.homeAltar
    else: agent.pos
  if target == agent.pos:
    return 0'u8
  controller.moveTo(env, agent, agentId, state, target)

proc canStartPredatorCull(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  agent.hp * 2 >= agent.maxHp and not isNil(findNearestPredator(env, agent.pos))

proc optPredatorCull(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let target = findNearestPredator(env, agent.pos)
  if isNil(target):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)

proc canStartGoblinNestClear(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  not isNil(findNearestGoblinStructure(env, agent.pos))

proc optGoblinNestClear(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let target = findNearestGoblinStructure(env, agent.pos)
  if isNil(target):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)

proc canStartFertileExpansion(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.inventoryWheat > 0 or agent.inventoryWood > 0 or agent.inventoryWater > 0

proc optFertileExpansion(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  if agent.inventoryWheat > 0 or agent.inventoryWood > 0:
    let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
    if didPlant: return actPlant
  if agent.inventoryWater > 0:
    let basePos = agent.getBasePos()
    let target = findIrrigationTarget(env, basePos, 6)
    if target.x >= 0:
      return actOrMove(controller, env, agent, agentId, state, target, 3'u8)
  0'u8

proc canStartMarketManipulator(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): bool =
  let teamId = getTeamId(agent)
  if controller.getBuildingCount(env, teamId, Market) == 0:
    return false
  if agent.inventoryGold > 0 and env.stockpileCount(teamId, ResourceFood) < 10:
    return true
  var hasNonFood = false
  for key, count in agent.inventory.pairs:
    if count <= 0 or not isStockpileResourceKey(key):
      continue
    let res = stockpileResourceForItem(key)
    if res notin {ResourceFood, ResourceWater, ResourceGold}:
      hasNonFood = true
      break
  hasNonFood and env.stockpileCount(teamId, ResourceGold) < 5

proc optMarketManipulator(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let market = env.findNearestFriendlyThingSpiral(state, teamId, Market)
  if isNil(market) or market.cooldown != 0:
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, market.pos, 3'u8)

proc canStartStockpileDistributor(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  canStartStoreValuables(controller, env, agent, agentId, state)

proc optStockpileDistributor(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  optStoreValuables(controller, env, agent, agentId, state)

proc canStartDockControl(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  if agent.unitClass == UnitBoat:
    return env.thingsByKind[Fish].len > 0
  agent.unitClass == UnitVillager and env.canAffordBuild(agent, thingItem("Dock"))

proc optDockControl(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  if agent.unitClass == UnitBoat:
    let fish = env.findNearestThingSpiral(state, Fish)
    if isNil(fish):
      return 0'u8
    return actOrMove(controller, env, agent, agentId, state, fish.pos, 3'u8)

  # Find water and adjacent standing position (inlined from findNearestWaterEdge)
  let water = findNearestWaterSpiral(env, state)
  if water.x < 0:
    return 0'u8
  var stand = ivec2(-1, -1)
  for d in AdjacentOffsets8:
    let pos = water + d
    if not isValidPos(pos) or env.terrain[pos.x][pos.y] == Water:
      continue
    if env.isEmpty(pos) and not env.hasDoor(pos) and
        not isBlockedTerrain(env.terrain[pos.x][pos.y]) and
        not isTileFrozen(pos, env):
      stand = pos
      break
  if stand.x < 0:
    return 0'u8
  if stand == agent.pos:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(8'u8, buildIndexFor(Dock).uint8))
  controller.moveTo(env, agent, agentId, state, stand)

proc canStartTerritorySweeper(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.inventoryLantern > 0 or not isNil(findNearestEnemyBuilding(env, agent.pos, getTeamId(agent)))

proc optTerritorySweeper(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let enemy = findNearestEnemyBuilding(env, agent.pos, getTeamId(agent))
  if not isNil(enemy):
    return actOrMove(controller, env, agent, agentId, state, enemy.pos, 2'u8)
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
  let target = findLanternFrontierCandidate(env, state, teamId, basePos)
  if target.x < 0 or agent.inventoryLantern <= 0:
    return 0'u8
  if isAdjacent(agent.pos, target):
    return controller.actAt(env, agent, agentId, state, target, 6'u8)
  controller.moveTo(env, agent, agentId, state, target)

proc canStartTempleFusion(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitVillager and env.thingsByKind[Temple].len > 0 and
    randChance(controller.rng, 0.01)

proc optTempleFusion(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let temple = env.findNearestThingSpiral(state, Temple)
  if isNil(temple):
    return 0'u8
  if isAdjacent(agent.pos, temple.pos):
    return controller.useAt(env, agent, agentId, state, temple.pos)
  controller.moveTo(env, agent, agentId, state, temple.pos)

let MetaBehaviorOptions* = [
  OptionDef(
    name: "BehaviorLanternFrontierPush",
    canStart: canStartLanternFrontierPush,
    shouldTerminate: optionsAlwaysTerminate,
    act: optLanternFrontierPush,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorLanternGapFill",
    canStart: canStartLanternGapFill,
    shouldTerminate: optionsAlwaysTerminate,
    act: optLanternGapFill,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorLanternRecovery",
    canStart: canStartLanternRecovery,
    shouldTerminate: optionsAlwaysTerminate,
    act: optLanternRecovery,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorLanternLogistics",
    canStart: canStartLanternLogistics,
    shouldTerminate: optionsAlwaysTerminate,
    act: optLanternLogistics,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorAntiTumorPatrol",
    canStart: canStartAntiTumorPatrol,
    shouldTerminate: optionsAlwaysTerminate,
    act: optAntiTumorPatrol,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorSpawnerHunter",
    canStart: canStartSpawnerHunter,
    shouldTerminate: optionsAlwaysTerminate,
    act: optSpawnerHunter,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorFrozenEdgeBreaker",
    canStart: canStartFrozenEdgeBreaker,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFrozenEdgeBreaker,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorGuardTowerBorder",
    canStart: canStartGuardTowerBorder,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGuardTowerBorder,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorOutpostNetwork",
    canStart: canStartOutpostNetwork,
    shouldTerminate: optionsAlwaysTerminate,
    act: optOutpostNetwork,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorEnemyWallFortify",
    canStart: canStartEnemyWallFortify,
    shouldTerminate: optionsAlwaysTerminate,
    act: optEnemyWallFortify,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorWallChokeFortify",
    canStart: canStartWallChokeFortify,
    shouldTerminate: optionsAlwaysTerminate,
    act: optWallChokeFortify,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorDoorChokeFortify",
    canStart: canStartDoorChokeFortify,
    shouldTerminate: optionsAlwaysTerminate,
    act: optDoorChokeFortify,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorRoadExpansion",
    canStart: canStartRoadExpansion,
    shouldTerminate: optionsAlwaysTerminate,
    act: optRoadExpansion,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorCastleAnchor",
    canStart: canStartCastleAnchor,
    shouldTerminate: optionsAlwaysTerminate,
    act: optCastleAnchor,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorSiegeBreacher",
    canStart: canStartSiegeBreacher,
    shouldTerminate: optionsAlwaysTerminate,
    act: optSiegeBreacher,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorMangonelSuppression",
    canStart: canStartMangonelSuppression,
    shouldTerminate: optionsAlwaysTerminate,
    act: optMangonelSuppression,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorUnitPromotionFocus",
    canStart: canStartUnitPromotionFocus,
    shouldTerminate: optionsAlwaysTerminate,
    act: optUnitPromotionFocus,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorRelicRaider",
    canStart: canStartRelicRaider,
    shouldTerminate: optionsAlwaysTerminate,
    act: optRelicRaider,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorRelicCourier",
    canStart: canStartRelicCourier,
    shouldTerminate: optionsAlwaysTerminate,
    act: optRelicCourier,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorPredatorCull",
    canStart: canStartPredatorCull,
    shouldTerminate: optionsAlwaysTerminate,
    act: optPredatorCull,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorGoblinNestClear",
    canStart: canStartGoblinNestClear,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGoblinNestClear,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorFertileExpansion",
    canStart: canStartFertileExpansion,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFertileExpansion,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorBreadSupply",
    canStart: canStartCraftBread,
    shouldTerminate: optionsAlwaysTerminate,
    act: optCraftBread,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorMarketManipulator",
    canStart: canStartMarketManipulator,
    shouldTerminate: optionsAlwaysTerminate,
    act: optMarketManipulator,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorStockpileDistributor",
    canStart: canStartStockpileDistributor,
    shouldTerminate: optionsAlwaysTerminate,
    act: optStockpileDistributor,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorDockControl",
    canStart: canStartDockControl,
    shouldTerminate: optionsAlwaysTerminate,
    act: optDockControl,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorTerritorySweeper",
    canStart: canStartTerritorySweeper,
    shouldTerminate: optionsAlwaysTerminate,
    act: optTerritorySweeper,
    interruptible: true
  ),
  OptionDef(
    name: "BehaviorTempleFusion",
    canStart: canStartTempleFusion,
    shouldTerminate: optionsAlwaysTerminate,
    act: optTempleFusion,
    interruptible: true
  )
]
