type GathererTask = enum
  TaskFood
  TaskWood
  TaskStone
  TaskGold
  TaskHearts

proc decideGatherer(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  var altarHearts = 0
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      altarHearts = homeAltar.hearts
  if altarHearts == 0:
    let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
    if not isNil(altar):
      altarHearts = altar.hearts

  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)
  var task = TaskFood
  if altarHearts < 10:
    task = TaskHearts
  else:
    let ordered = [
      (TaskHearts, altarHearts),
      (TaskFood, food),
      (TaskWood, wood),
      (TaskStone, stone),
      (TaskGold, gold)
    ]
    var best = ordered[0]
    for i in 1 ..< ordered.len:
      if ordered[i][1] < best[1]:
        best = ordered[i]
    task = best[0]
  let heartsPriority = task == TaskHearts
  var magmaGlobal: Thing = nil
  if heartsPriority:
    var bestDist = int.high
    for magma in env.thingsByKind[Magma]:
      let dist = abs(magma.pos.x - agent.pos.x) + abs(magma.pos.y - agent.pos.y)
      if dist < bestDist:
        bestDist = dist
        magmaGlobal = magma

  var carryingStockpile = false
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      carryingStockpile = true
      break

  if carryingStockpile:
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

  template tryBuildCamp(kind: ThingKind, nearbyCount, minCount: int,
                        nearbyKinds: openArray[ThingKind]): uint8 =
    if agent.unitClass == UnitVillager:
      let (didBuild, buildAct) = controller.tryBuildCampThreshold(
        env, agent, agentId, state, teamId, kind,
        nearbyCount, minCount,
        nearbyKinds
      )
      if didBuild: return buildAct
    0'u8

  case task
  of TaskHearts:
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
    let magmaKnown = state.closestMagmaPos.x >= 0 or not isNil(magmaGlobal)
    if not magmaKnown:
      return controller.moveNextSearch(env, agent, agentId, state)
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskGold, TaskWood, TaskStone:
    var campKind: ThingKind
    var nearbyCount = 0
    var minCount = 0
    case task
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
    let buildAct = tryBuildCamp(campKind, nearbyCount, minCount, [campKind])
    if buildAct != 0'u8: return buildAct
    case task
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
  of TaskFood:
    let nearbyWheat = countNearbyThings(env, agent.pos, 4, {Wheat})
    let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
    let buildGranary = tryBuildCamp(Granary, nearbyWheat + nearbyFertile, 8, [Granary])
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

    if state.closestFoodPos.x >= 0:
      let knownThing = env.getThing(state.closestFoodPos)
      if isNil(knownThing) or knownThing.kind notin {Wheat, Bush, Cow, Corpse}:
        state.closestFoodPos = ivec2(-1, -1)
      else:
        let verb = (if knownThing.kind == Cow: 2'u8 else: 3'u8)
        if isAdjacent(agent.pos, knownThing.pos):
          return controller.actAt(env, agent, agentId, state, knownThing.pos, verb)
        return controller.moveTo(env, agent, agentId, state, knownThing.pos)

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      updateClosestSeen(state, state.basePosition, wheat.pos, state.closestFoodPos)
      if isAdjacent(agent.pos, wheat.pos):
        return controller.useAt(env, agent, agentId, state, wheat.pos)
      return controller.moveTo(env, agent, agentId, state, wheat.pos)

    let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
    if didHunt: return actHunt
    return controller.moveNextSearch(env, agent, agentId, state)
