type GathererTask = enum
  TaskFood
  TaskWood
  TaskStone
  TaskGold
  TaskHearts

proc chooseGathererTask(env: Environment, teamId: int): GathererTask =
  # Simple stockpile-driven priorities (tune later).
  const
    TargetFood = 6
    TargetWood = 6
    TargetStone = 4
    TargetGold = 4

  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)

  if food >= TargetFood and wood >= TargetWood and stone >= TargetStone and gold >= TargetGold:
    return TaskHearts

  let ratios = [
    (task: TaskFood, ratio: food.float / TargetFood.float),
    (task: TaskWood, ratio: wood.float / TargetWood.float),
    (task: TaskStone, ratio: stone.float / TargetStone.float),
    (task: TaskGold, ratio: gold.float / TargetGold.float)
  ]

  var best = ratios[0]
  for entry in ratios[1 .. ^1]:
    if entry.ratio < best.ratio:
      best = entry
  best.task

proc dropoffIfCarrying(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent.agentId)

  if hasFoodCargo(agent):
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Mill, controller.rng)
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

  if agent.inventoryStone > 0 or agent.inventoryGold > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  (false, 0'u8)

proc decideGatherer(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Drop off any carried stockpile resources first.
  let (didDrop, dropAct) = dropoffIfCarrying(controller, env, agent, agentId, state)
  if didDrop: return dropAct

  let task = chooseGathererTask(env, teamId)

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
    discard
  of TaskFood:
    let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if didWheat: return actWheat
    let (didCow, actCow) = controller.findAndUseBuilding(env, agent, agentId, state, Cow)
    if didCow: return actCow
    let (didAnimal, actAnimal) = controller.findAndHarvest(env, agent, agentId, state, Animal)
    if didAnimal: return actAnimal
    let (didPlant, actPlant) = controller.findAndHarvest(env, agent, agentId, state, Bush)
    if didPlant: return actPlant
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskWood:
    let (did, act) = controller.findAndHarvestThings(env, agent, agentId, state, [Pine, Palm])
    if did: return act
    return controller.moveNextSearch(env, agent, agentId, state)
  of TaskStone:
    let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Rock)
    if did: return act
    return controller.moveNextSearch(env, agent, agentId, state)

  # Gold gathering (shared by TaskGold / TaskHearts fallback)
  let goldPos = env.findNearestTerrainSpiral(state, TerrainType.Gold, controller.rng)
  if goldPos.x >= 0:
    return controller.useOrMove(env, agent, agentId, state, goldPos)

  return controller.moveNextSearch(env, agent, agentId, state)
