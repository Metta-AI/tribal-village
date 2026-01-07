type GathererTask = enum
  TaskFood
  TaskWood
  TaskStone
  TaskGold
  TaskHearts

proc chooseGathererTask(controller: Controller, env: Environment, teamId: int,
                        altarHearts: int): GathererTask =
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)

  if altarHearts < 10:
    return TaskHearts

  let lowest = min(food, min(wood, min(stone, min(gold, altarHearts))))
  let ordered = [TaskHearts, TaskFood, TaskWood, TaskStone, TaskGold]
  for task in ordered:
    case task
    of TaskHearts:
      if altarHearts == lowest: return TaskHearts
    of TaskFood:
      if food == lowest: return TaskFood
    of TaskWood:
      if wood == lowest: return TaskWood
    of TaskStone:
      if stone == lowest: return TaskStone
    of TaskGold:
      if gold == lowest: return TaskGold
  TaskFood

proc decideGatherer(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  var altarHearts = 0
  if agent.homeAltar.x >= 0:
    for thing in env.things:
      if thing.kind == Altar and thing.teamId == teamId and thing.pos == agent.homeAltar:
        altarHearts = thing.hearts
        break
  if altarHearts == 0:
    let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
    if not isNil(altar):
      altarHearts = altar.hearts

  let task = chooseGathererTask(controller, env, teamId, altarHearts)
  let heartsPriority = task == TaskHearts

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
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if not isNil(magma):
        updateClosestSeen(state, state.basePosition, magma.pos, state.closestMagmaPos)
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    let (didDrop, dropAct) =
      controller.dropoffGathererCarrying(env, agent, agentId, state, allowGold = not heartsPriority)
    if didDrop: return dropAct
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, basePos, controller.rng).uint8))

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
      if agent.homeAltar.x >= 0:
        return controller.useOrMove(env, agent, agentId, state, agent.homeAltar)
      let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
      if not isNil(altar):
        return controller.useOrMove(env, agent, agentId, state, altar.pos)
    if agent.inventoryGold > 0:
      let (didKnown, actKnown) = controller.tryMoveToKnownResource(
        env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
      if didKnown: return actKnown
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if not isNil(magma):
        updateClosestSeen(state, state.basePosition, magma.pos, state.closestMagmaPos)
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskGold:
    let nearbyGold = countNearbyThings(env, agent.pos, 4, {Gold})
    let buildAct = tryBuildCamp(MiningCamp, nearbyGold, 6, [MiningCamp])
    if buildAct != 0'u8: return buildAct
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
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
      if not isNil(knownThing) and knownThing.kind in {Wheat, Bush, Cow, Corpse}:
        if knownThing.kind == Cow:
          return controller.attackOrMove(env, agent, agentId, state, knownThing.pos)
        return controller.useOrMove(env, agent, agentId, state, knownThing.pos)
      state.closestFoodPos = ivec2(-1, -1)

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      updateClosestSeen(state, state.basePosition, wheat.pos, state.closestFoodPos)
      return controller.useOrMove(env, agent, agentId, state, wheat.pos)

    let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
    if didHunt: return actHunt
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskWood:
    let nearbyTrees = countNearbyThings(env, agent.pos, 4, {Pine, Palm})
    let buildAct = tryBuildCamp(LumberCamp, nearbyTrees, 6, [LumberCamp])
    if buildAct != 0'u8: return buildAct
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskStone:
    let nearbyStone = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
    let buildAct = tryBuildCamp(Quarry, nearbyStone, 4, [Quarry])
    if buildAct != 0'u8: return buildAct
    let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
    if didStone: return actStone
    return controller.moveNextSearch(env, agent, agentId, state)
