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

  var lowest = min(food, min(wood, min(stone, min(gold, altarHearts))))
  var choices: seq[GathererTask] = @[]
  if food == lowest: choices.add(TaskFood)
  if wood == lowest: choices.add(TaskWood)
  if stone == lowest: choices.add(TaskStone)
  if gold == lowest: choices.add(TaskGold)
  if altarHearts == lowest: choices.add(TaskHearts)
  choices[randIntExclusive(controller.rng, 0, choices.len)]

proc decideGatherer(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
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

  # Drop off any carried stockpile resources first.
  let allowGoldDropoff = altarHearts >= 10 or env.thingsByKind[Magma].len == 0
  let (didDrop, dropAct) =
    controller.dropoffGathererCarrying(env, agent, agentId, state, allowGoldDropoff)
  if didDrop: return dropAct

  let task = chooseGathererTask(controller, env, teamId, altarHearts)

  template tryBuildCamp(kind: ThingKind, nearbyCount, minCount: int,
                        nearbyKinds: openArray[ThingKind], distanceThreshold: int): uint8 =
    if agent.unitClass == UnitVillager:
      let (didBuild, buildAct) = controller.tryBuildNearResource(
        env, agent, agentId, state, teamId, kind,
        nearbyCount, minCount,
        nearbyKinds, distanceThreshold
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
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if not isNil(magma):
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskGold:
    let nearbyGold = countNearbyThings(env, agent.pos, 4, {Gold})
    let buildAct = tryBuildCamp(MiningCamp, nearbyGold, 6, [MiningCamp], 6)
    if buildAct != 0'u8: return buildAct
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return actGold
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskFood:
    let nearbyWheat = countNearbyThings(env, agent.pos, 4, {Wheat})
    let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
    let buildGranary = tryBuildCamp(Granary, nearbyWheat + nearbyFertile, 8, [Granary], 8)
    if buildGranary != 0'u8: return buildGranary
    if agent.homeAltar.x < 0 or
       max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) > 10:
      let buildMill = tryBuildCamp(Mill, 1, 1, [Mill], 6)
      if buildMill != 0'u8: return buildMill
    let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
    if didPlant: return actPlant

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      return controller.useOrMove(env, agent, agentId, state, wheat.pos)

    let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
    if didHunt: return actHunt
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskWood:
    let nearbyTrees = countNearbyThings(env, agent.pos, 4, {Pine, Palm})
    let buildAct = tryBuildCamp(LumberCamp, nearbyTrees, 6, [LumberCamp], 6)
    if buildAct != 0'u8: return buildAct
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskStone:
    let nearbyStone = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
    let buildAct = tryBuildCamp(Quarry, nearbyStone, 4, [Quarry], 6)
    if buildAct != 0'u8: return buildAct
    let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
    if didStone: return actStone
    return controller.moveNextSearch(env, agent, agentId, state)
