type GathererTask = enum
  TaskFood
  TaskWood
  TaskStone
  TaskGold
  TaskHearts

proc countNearbyTrees(env: Environment, center: IVec2, radius: int): int =
  for thing in env.things:
    if thing.kind notin {Pine, Palm}:
      continue
    if max(abs(thing.pos.x - center.x), abs(thing.pos.y - center.y)) <= radius:
      inc result

proc countNearbyTerrain(env: Environment, center: IVec2, radius: int, allowed: set[TerrainType]): int =
  let cx = center.x.int
  let cy = center.y.int
  let startX = max(0, cx - radius)
  let endX = min(MapWidth - 1, cx + radius)
  let startY = max(0, cy - radius)
  let endY = min(MapHeight - 1, cy + radius)
  for x in startX..endX:
    for y in startY..endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      if env.terrain[x][y] in allowed:
        inc result

proc hasFriendlyBuildingNearby(env: Environment, teamId: int, kind: ThingKind,
                               center: IVec2, radius: int): bool =
  for thing in env.things:
    if thing.kind != kind:
      continue
    if thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - center.x), abs(thing.pos.y - center.y)) <= radius:
      return true
  false

proc gathererTargets(env: Environment, teamId: int): tuple[food, wood, stone, gold: int] =
  ## AoE-like priority: keep food/wood higher, scale a bit with base size.
  let townCenters = env.countTeamBuildings(teamId, TownCenter)
  let houses = env.countTeamBuildings(teamId, House)
  let baseScale = max(1, townCenters + houses)
  result.food = 8 + baseScale * 2
  result.wood = 6 + baseScale
  result.stone = 4 + baseScale div 2
  result.gold = 4 + baseScale div 2

proc chooseGathererTask(env: Environment, teamId: int): GathererTask =
  let targets = gathererTargets(env, teamId)
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

proc dropoffIfCarrying(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState,
                       allowGoldDropoff: bool): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent.agentId)

  if hasFoodCargo(agent):
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Granary, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  if agent.inventoryWood > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  if agent.inventoryStone > 0 or (allowGoldDropoff and agent.inventoryGold > 0):
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  (false, 0'u8)

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
  let allowGoldDropoff = altarHearts >= 10
  let (didDrop, dropAct) = dropoffIfCarrying(controller, env, agent, agentId, state, allowGoldDropoff)
  if didDrop: return dropAct

  var task = chooseGathererTask(env, teamId)
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
      let nearbyGold = countNearbyTerrain(env, agent.pos, 4, {Gold})
      if nearbyGold >= 6 and not hasFriendlyBuildingNearby(env, teamId, MiningCamp, agent.pos, 6):
        let (didBuild, buildAct) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMiningCamp)
        if didBuild: return buildAct
  of TaskFood:
    let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
    if didPlant: return actPlant
    let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if didWheat: return actWheat
    let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
    if didCow: return actCow
    let (didAnimal, actAnimal) = controller.findAndHarvest(env, agent, agentId, state, Animal)
    if didAnimal: return actAnimal
    let (didBush, actBush) = controller.findAndHarvest(env, agent, agentId, state, Bush)
    if didBush: return actBush
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskWood:
    if agent.unitClass == UnitVillager:
      let nearbyTrees = countNearbyTrees(env, agent.pos, 4)
      if nearbyTrees >= 6 and not hasFriendlyBuildingNearby(env, teamId, LumberCamp, agent.pos, 6):
        let (didBuild, buildAct) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexLumberCamp)
        if didBuild: return buildAct
    let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
    if did: return act
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskStone:
    if agent.unitClass == UnitVillager:
      let nearbyStone = countNearbyTerrain(env, agent.pos, 4, {Rock, Stalagmite})
      if nearbyStone >= 6 and not hasFriendlyBuildingNearby(env, teamId, MiningCamp, agent.pos, 6):
        let (didBuild, buildAct) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMiningCamp)
        if didBuild: return buildAct
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Rock)
    if did: return act
    return controller.moveNextSearch(env, agent, agentId, state)

  # Gold gathering (shared by TaskGold / TaskHearts fallback)
  let goldPos = env.findNearestTerrainSpiral(state, TerrainType.Gold, controller.rng)
  if goldPos.x >= 0:
    return controller.useOrMoveToTerrain(env, agent, agentId, state, goldPos)

  return controller.moveNextSearch(env, agent, agentId, state)
