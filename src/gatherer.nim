type GathererTask = enum
  TaskFood
  TaskWood
  TaskStone
  TaskGold
  TaskHearts

proc chooseGathererTask(controller: Controller, env: Environment, teamId: int): GathererTask =
  let townCenters = controller.getBuildingCount(env, teamId, TownCenter)
  let houses = controller.getBuildingCount(env, teamId, House)
  let baseScale = max(1, townCenters + houses)
  let targets = (
    food: 8 + baseScale * 2,
    wood: 6 + baseScale,
    stone: 6 + baseScale,
    gold: 4 + baseScale div 2
  )
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)

  let foodDef = targets.food - food
  let woodDef = targets.wood - wood
  let stoneDef = targets.stone - stone
  let goldDef = targets.gold - gold

  if foodDef <= 0 and woodDef <= 0 and stoneDef <= 0 and goldDef <= 0:
    return TaskHearts

  var bestTask = TaskFood
  var bestDef = foodDef
  if woodDef > bestDef:
    bestDef = woodDef
    bestTask = TaskWood
  if stoneDef > bestDef:
    bestDef = stoneDef
    bestTask = TaskStone
  if goldDef > bestDef:
    bestDef = goldDef
    bestTask = TaskGold
  bestTask

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
    if altar != nil:
      altarHearts = altar.hearts

  # Drop off any carried stockpile resources first.
  var magmaFound = false
  for thing in env.things:
    if thing.kind == Magma:
      magmaFound = true
      break
  let allowGoldDropoff = altarHearts >= 10 or not magmaFound
  let (didDrop, dropAct) =
    controller.dropoffGathererCarrying(env, agent, agentId, state, allowGoldDropoff)
  if didDrop: return dropAct

  var task = chooseGathererTask(controller, env, teamId)
  if altarHearts < 10:
    task = TaskHearts

  case task
  of TaskHearts:
    if agent.inventoryBar > 0:
      if agent.homeAltar.x >= 0:
        return controller.useOrMove(env, agent, agentId, state, agent.homeAltar)
      let altar = env.findNearestThingSpiral(state, Altar, controller.rng)
      if altar != nil:
        return controller.useOrMove(env, agent, agentId, state, altar.pos)
    if agent.inventoryGold > 0:
      let magma = env.findNearestThingSpiral(state, Magma, controller.rng)
      if magma != nil:
        return controller.useOrMove(env, agent, agentId, state, magma.pos)
    # Fall through to gold gathering.
  of TaskGold:
    if agent.unitClass == UnitVillager:
      let nearbyGold = countNearbyThings(env, agent.pos, 4, {Gold})
      let (didBuild, buildAct) = controller.tryBuildNearResource(
        env, agent, agentId, state, teamId, MiningCamp,
        nearbyGold, 6,
        [MiningCamp], 6
      )
      if didBuild: return buildAct
  of TaskFood:
    if agent.unitClass == UnitVillager:
      let nearbyWheat = countNearbyThings(env, agent.pos, 4, {Wheat})
      let nearbyFertile = countNearbyTerrain(env, agent.pos, 4, {Fertile})
      let (didGranary, actGranary) = controller.tryBuildNearResource(
        env, agent, agentId, state, teamId, Granary,
        nearbyWheat + nearbyFertile, 8,
        [Granary], 8
      )
      if didGranary: return actGranary
      if agent.homeAltar.x < 0 or
         max(abs(agent.pos.x - agent.homeAltar.x), abs(agent.pos.y - agent.homeAltar.y)) > 10:
        let (didMill, actMill) = controller.tryBuildNearResource(
          env, agent, agentId, state, teamId, Mill,
          1, 1,
          [Mill], 6
        )
        if didMill: return actMill
    let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
    if didPlant: return actPlant

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if wheat != nil:
      return controller.useOrMove(env, agent, agentId, state, wheat.pos)

    let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
    if didHunt: return actHunt
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskWood:
    if agent.unitClass == UnitVillager:
      let nearbyTrees = countNearbyTrees(env, agent.pos, 4)
      let (didBuild, buildAct) = controller.tryBuildNearResource(
        env, agent, agentId, state, teamId, LumberCamp,
        nearbyTrees, 6,
        [LumberCamp], 6
      )
      if didBuild: return buildAct
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskStone:
    if agent.unitClass == UnitVillager:
      let nearbyStone = countNearbyThings(env, agent.pos, 4, {Stone, Stalagmite})
      let (didBuild, buildAct) = controller.tryBuildNearResource(
        env, agent, agentId, state, teamId, Quarry,
        nearbyStone, 4,
        [Quarry], 6
      )
      if didBuild: return buildAct
    let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
    if didStone: return actStone
    return controller.moveNextSearch(env, agent, agentId, state)

  # Gold gathering (shared by TaskGold / TaskHearts fallback)
  let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
  if didGold: return actGold
  return controller.moveNextSearch(env, agent, agentId, state)
