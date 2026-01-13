proc findFertileTarget(env: Environment, center: IVec2, radius: int, blocked: IVec2): IVec2 =
  let cx = center.x.int
  let cy = center.y.int
  let startX = max(0, cx - radius)
  let endX = min(MapWidth - 1, cx + radius)
  let startY = max(0, cy - radius)
  let endY = min(MapHeight - 1, cy + radius)
  var bestDist = int.high
  var bestPos = ivec2(-1, -1)
  for x in startX .. endX:
    for y in startY .. endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      let pos = ivec2(x.int32, y.int32)
      if pos == blocked:
        continue
      if not env.isEmpty(pos) or env.hasDoor(pos) or isTileFrozen(pos, env):
        continue
      let terrain = env.terrain[x][y]
      if terrain notin {Empty, Grass, Sand, Snow, Dune, Road}:
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < bestDist:
        bestDist = dist
        bestPos = pos
  bestPos

proc gathererAltarHearts(controller: Controller, env: Environment, agent: Thing,
                         state: var AgentState, teamId: int): int =
  var altarHearts = 0
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      altarHearts = homeAltar.hearts
  if altarHearts == 0:
    let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
    if not isNil(altar):
      altarHearts = altar.hearts
  altarHearts

proc updateGathererTask(controller: Controller, env: Environment, agent: Thing,
                        state: var AgentState) =
  let teamId = getTeamId(agent.agentId)
  let altarHearts = gathererAltarHearts(controller, env, agent, state, teamId)
  var task = TaskFood
  if altarHearts < 10:
    task = TaskHearts
  else:
    let ordered = [
      (TaskHearts, altarHearts),
      (TaskFood, env.stockpileCount(teamId, ResourceFood)),
      (TaskWood, env.stockpileCount(teamId, ResourceWood)),
      (TaskStone, env.stockpileCount(teamId, ResourceStone)),
      (TaskGold, env.stockpileCount(teamId, ResourceGold))
    ]
    var best = ordered[0]
    for i in 1 ..< ordered.len:
      if ordered[i][1] < best[1]:
        best = ordered[i]
    task = best[0]
  state.gathererTask = task

proc isCarryingStockpile(agent: Thing): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      return true
  false

proc gathererHasPlantInputs(agent: Thing): bool =
  agent.inventoryWheat > 0 or agent.inventoryWood > 0

proc findNearestMagma(env: Environment, agent: Thing): Thing =
  var bestDist = int.high
  var best: Thing = nil
  for magma in env.thingsByKind[Magma]:
    let dist = abs(magma.pos.x - agent.pos.x) + abs(magma.pos.y - agent.pos.y)
    if dist < bestDist:
      bestDist = dist
      best = magma
  best

proc gathererTryBuildCamp(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState,
                          teamId: int, kind: ThingKind,
                          nearbyCount, minCount: int,
                          nearbyKinds: openArray[ThingKind]): uint8 =
  if agent.unitClass != UnitVillager:
    return 0'u8
  let (didBuild, buildAct) = controller.tryBuildCampThreshold(
    env, agent, agentId, state, teamId, kind,
    nearbyCount, minCount,
    nearbyKinds
  )
  if didBuild: return buildAct
  0'u8

proc canStartGathererPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  gathererHasPlantInputs(agent)

proc optGathererPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartGathererCarrying(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  isCarryingStockpile(agent)

proc optGathererCarrying(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  if not isCarryingStockpile(agent):
    return 0'u8
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  let heartsPriority = state.gathererTask == TaskHearts
  var magmaGlobal: Thing = nil
  if heartsPriority:
    magmaGlobal = findNearestMagma(env, agent)

  if agent.inventoryGold > 0 and heartsPriority:
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
    if didKnown: return actKnown
    if not isNil(magmaGlobal):
      updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
      if isAdjacent(agent.pos, magmaGlobal.pos):
        return controller.useAt(env, agent, agentId, state, magmaGlobal.pos)
      return controller.moveTo(env, agent, agentId, state, magmaGlobal.pos)

  let (didDrop, dropAct) = controller.dropoffCarrying(
    env, agent, agentId, state,
    allowFood = true, allowWood = true, allowStone = true, allowGold = not heartsPriority
  )
  if didDrop: return dropAct
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, basePos,
      controller.rng, (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)).uint8))

proc canStartGathererHearts(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  state.gathererTask == TaskHearts

proc optGathererHearts(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  if state.gathererTask != TaskHearts:
    return 0'u8
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  let magmaGlobal = findNearestMagma(env, agent)

  if agent.inventoryBar > 0:
    var altarPos = agent.homeAltar
    if altarPos.x < 0:
      let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
      if not isNil(altar):
        altarPos = altar.pos
    if altarPos.x >= 0:
      if isAdjacent(agent.pos, altarPos):
        return controller.useAt(env, agent, agentId, state, altarPos)
      return controller.moveTo(env, agent, agentId, state, altarPos)
  if agent.inventoryGold > 0:
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
    if didKnown: return actKnown
    if not isNil(magmaGlobal):
      updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
      if isAdjacent(agent.pos, magmaGlobal.pos):
        return controller.useAt(env, agent, agentId, state, magmaGlobal.pos)
      return controller.moveTo(env, agent, agentId, state, magmaGlobal.pos)
    return controller.moveNextSearch(env, agent, agentId, state)
  if state.closestMagmaPos.x < 0 and isNil(magmaGlobal):
    return controller.moveNextSearch(env, agent, agentId, state)
  let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
  if didGold: return actGold
  return controller.moveNextSearch(env, agent, agentId, state)

proc canStartGathererResource(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  state.gathererTask in {TaskGold, TaskWood, TaskStone}

proc optGathererResource(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  if state.gathererTask notin {TaskGold, TaskWood, TaskStone}:
    return 0'u8
  let teamId = getTeamId(agent.agentId)
  var campKind: ThingKind
  var nearbyCount = 0
  var minCount = 0
  case state.gathererTask
  of TaskGold:
    campKind = MiningCamp
    nearbyCount = countNearbyThings(env, agent.pos, 4, {Gold})
    minCount = 6
  of TaskWood:
    campKind = LumberCamp
    nearbyCount = countNearbyThings(env, agent.pos, 4, {Tree})
    minCount = 6
  of TaskStone:
    campKind = Quarry
    nearbyCount = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
    minCount = 4
  else:
    discard
  let buildAct = gathererTryBuildCamp(
    controller, env, agent, agentId, state, teamId,
    campKind, nearbyCount, minCount, [campKind]
  )
  if buildAct != 0'u8: return buildAct
  case state.gathererTask
  of TaskGold:
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
  of TaskWood:
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
  of TaskStone:
    let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
    if didStone: return actStone
  else:
    discard
  return controller.moveNextSearch(env, agent, agentId, state)

proc canStartGathererFood(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  state.gathererTask == TaskFood

proc optGathererFood(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  if state.gathererTask != TaskFood:
    return 0'u8
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

  let buildGranary = gathererTryBuildCamp(
    controller, env, agent, agentId, state, teamId,
    Granary,
    countNearbyThings(env, agent.pos, 4, {Wheat, Stubble}) +
      countNearbyTerrain(env, agent.pos, 4, {Fertile}),
    8,
    [Granary]
  )
  if buildGranary != 0'u8: return buildGranary
  if agent.homeAltar.x < 0 or
     max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) > 10:
    let (didMill, actMill) = controller.tryBuildNearResource(
      env, agent, agentId, state, teamId, Mill,
      1, 1, [Mill], 6
    )
    if didMill: return actMill
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant

  block waterFertile:
    block:
      let cx = agent.pos.x.int
      let cy = agent.pos.y.int
      let radius = 4
      let startX = max(0, cx - radius)
      let endX = min(MapWidth - 1, cx + radius)
      let startY = max(0, cy - radius)
      let endY = min(MapHeight - 1, cy + radius)
      var hasNearbyFood = false
      for x in startX .. endX:
        for y in startY .. endY:
          if max(abs(x - cx), abs(y - cy)) > radius:
            continue
          let occ = env.grid[x][y]
          if not isNil(occ) and occ.kind in {Wheat, Stubble, Bush, Cow, Corpse}:
            hasNearbyFood = true
            break
          let overlay = env.overlayGrid[x][y]
          if not isNil(overlay) and overlay.kind in {Wheat, Stubble, Bush, Cow, Corpse}:
            hasNearbyFood = true
            break
        if hasNearbyFood:
          break
      if hasNearbyFood:
        break waterFertile
    let fertileRadius = 6
    let fertileCount = countNearbyTerrain(env, basePos, fertileRadius, {Fertile})
    var hasMill = false
    for mill in env.thingsByKind[Mill]:
      if mill.teamId == teamId and chebyshevDist(mill.pos, basePos) <= fertileRadius:
        hasMill = true
        break
    if fertileCount < 6 and not hasMill:
      if agent.inventoryWater > 0:
        var target = findFertileTarget(env, basePos, fertileRadius, state.pathBlockedTarget)
        if target.x < 0:
          target = findFertileTarget(env, agent.pos, fertileRadius, state.pathBlockedTarget)
        if target.x >= 0:
          if isAdjacent(agent.pos, target):
            return controller.useAt(env, agent, agentId, state, target)
          return controller.moveTo(env, agent, agentId, state, target)
      else:
        let (didWater, actWater) = controller.ensureWater(env, agent, agentId, state)
        if didWater: return actWater

  if state.closestFoodPos.x >= 0:
    if state.closestFoodPos == state.pathBlockedTarget:
      state.closestFoodPos = ivec2(-1, -1)
    else:
      let knownThing = env.getThing(state.closestFoodPos)
      if isNil(knownThing) or knownThing.kind notin {Wheat, Stubble, Bush, Cow, Corpse}:
        state.closestFoodPos = ivec2(-1, -1)
      else:
        if isAdjacent(agent.pos, knownThing.pos):
          return controller.actAt(env, agent, agentId, state, knownThing.pos,
            (if knownThing.kind == Cow: 2'u8 else: 3'u8))
        return controller.moveTo(env, agent, agentId, state, knownThing.pos)

  for kind in [Wheat, Stubble]:
    let wheat = env.findNearestThingSpiral(state, kind, controller.rng)
    if isNil(wheat):
      continue
    if wheat.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    updateClosestSeen(state, state.basePosition, wheat.pos, state.closestFoodPos)
    if isAdjacent(agent.pos, wheat.pos):
      return controller.useAt(env, agent, agentId, state, wheat.pos)
    return controller.moveTo(env, agent, agentId, state, wheat.pos)

  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)

proc optGathererFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

let GathererOptions = [
  OptionDef(
    name: "GathererPlantOnFertile",
    canStart: canStartGathererPlantOnFertile,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererPlantOnFertile,
    interruptible: true
  ),
  OptionDef(
    name: "GathererCarryingStockpile",
    canStart: canStartGathererCarrying,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererCarrying,
    interruptible: true
  ),
  OptionDef(
    name: "GathererHearts",
    canStart: canStartGathererHearts,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererHearts,
    interruptible: true
  ),
  OptionDef(
    name: "GathererResource",
    canStart: canStartGathererResource,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererResource,
    interruptible: true
  ),
  OptionDef(
    name: "GathererFood",
    canStart: canStartGathererFood,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererFood,
    interruptible: true
  ),
  OptionDef(
    name: "GathererFallbackSearch",
    canStart: optionsAlwaysCanStart,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererFallbackSearch,
    interruptible: true
  )
]

proc decideGatherer(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  updateGathererTask(controller, env, agent, state)
  return runOptions(controller, env, agent, agentId, state, GathererOptions)
