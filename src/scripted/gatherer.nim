# coordination is already imported by ai_core.nim (included before this file)

template gathererGuard(canName, termName: untyped, body: untyped) {.dirty.} =
  ## Generate a canStart/shouldTerminate pair from a single boolean expression.
  ## shouldTerminate is the logical negation of canStart.
  proc canName(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState): bool = body
  proc termName(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): bool = not (body)

# Game phase resource weights (not balance-tunable, just weighting tables)
const
  # Weights: lower value = higher priority (divides the stockpile count)
  # Order: [Food, Wood, Stone, Gold]
  EarlyGameWeights = [0.5, 0.75, 1.0, 1.5]   # Food prioritized
  LateGameWeights = [1.5, 1.0, 0.75, 0.5]    # Gold prioritized
  MidGameWeights = [1.0, 1.0, 1.0, 1.0]      # Equal priority

proc gathererFindNearbyEnemy(env: Environment, agent: Thing): Thing =
  ## Find nearest enemy agent within flee radius using spatial index
  findNearbyEnemyForFlee(env, agent, GathererFleeRadius)

gathererGuard(canStartGathererFlee, shouldTerminateGathererFlee):
  not isNil(gathererFindNearbyEnemy(env, agent))

proc optGathererFlee(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  ## Flee toward home altar when enemies are nearby
  let enemy = gathererFindNearbyEnemy(env, agent)
  if isNil(enemy):
    return 0'u8
  # Request protection from nearby fighters via coordination system
  requestProtectionFromFighter(env, agent, enemy.pos)
  # Move toward home altar for safety
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  controller.moveTo(env, agent, agentId, state, basePos)

proc findFertileTarget(env: Environment, center: IVec2, radius: int, blocked: IVec2): IVec2 =
  let (startX, endX, startY, endY) = radiusBounds(center, radius)
  let cx = center.x.int
  let cy = center.y.int
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
      if not isBuildableExcludingRoads(terrain):
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < bestDist:
        bestDist = dist
        bestPos = pos
  bestPos

const FoodKinds = {Wheat, Stubble, Fish, Bush, Cow, Corpse}

proc gathererStockpileTotal(agent: Thing): int =
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      result += count

proc hasNearbyFood(env: Environment, pos: IVec2, radius: int): bool =
  ## Optimized: uses thingsByKind iteration instead of grid scan
  for kind in FoodKinds:
    for thing in env.thingsByKind[kind]:
      if thing.isNil:
        continue
      if chebyshevDist(pos, thing.pos) <= radius.int32:
        return true
  false

proc tryDeliverGoldToMagma(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState,
                           magmaGlobal: Thing): (bool, uint8) =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
  if didKnown: return (true, actKnown)
  if not isNil(magmaGlobal):
    updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
    return (true, actOrMove(controller, env, agent, agentId, state, magmaGlobal.pos, 3'u8))
  (false, 0'u8)

proc findTeamAltar(env: Environment, agent: Thing, teamId: int): (IVec2, int) =
  ## Find the nearest team altar, preferring the agent's home altar.
  ## Returns (position, hearts) or (ivec2(-1,-1), 0) if none found.
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      return (homeAltar.pos, homeAltar.hearts)
  # Use spatial query instead of O(n) altar scan
  let nearestAltar = findNearestFriendlyThingSpatial(env, agent.pos, teamId, Altar, 1000)
  if not nearestAltar.isNil:
    return (nearestAltar.pos, nearestAltar.hearts)
  (ivec2(-1, -1), 0)

proc updateGathererTask(controller: Controller, env: Environment, agent: Thing,
                        state: var AgentState) =
  let teamId = getTeamId(agent)
  let (altarPos, altarHearts) = findTeamAltar(env, agent, teamId)
  let altarFound = altarPos.x >= 0
  var task = TaskFood

  # Check economy state for critical resource bottlenecks
  let bottleneck = getCurrentBottleneck(teamId)
  if bottleneck == FoodCritical:
    state.gathererTask = TaskFood
    return
  elif bottleneck == WoodCritical:
    state.gathererTask = TaskWood
    return

  if altarFound and altarHearts < 10:
    task = TaskHearts
  else:
    # Determine game phase and select appropriate weights
    let gameProgress = if env.config.maxSteps > 0:
      env.currentStep.float / env.config.maxSteps.float
    else:
      0.5  # Default to mid-game if maxSteps not set
    let weights = if gameProgress < EarlyGameThreshold:
      EarlyGameWeights
    elif gameProgress >= LateGameThreshold:
      LateGameWeights
    else:
      MidGameWeights

    # Get flow rates from economy system to adjust priorities
    # If a resource is decreasing fast, reduce its weight (prioritize it)
    let flowRate = getFlowRate(teamId)
    proc flowAdj(rate: float): float =
      if rate < -0.1: rate * 2.0 else: 0.0
    let flowAdjust = [flowAdj(flowRate.foodPerStep), flowAdj(flowRate.woodPerStep),
                      flowAdj(flowRate.stonePerStep), flowAdj(flowRate.goldPerStep)]

    # Apply weights: lower weighted score = higher priority
    # Weight < 1.0 makes resource appear more scarce (prioritized)
    # Flow adjustment makes declining resources appear more scarce
    var ordered: seq[(GathererTask, float)] = @[
      (TaskFood, max(0.0, env.stockpileCount(teamId, ResourceFood).float + flowAdjust[0] * 10.0) * weights[0]),
      (TaskWood, max(0.0, env.stockpileCount(teamId, ResourceWood).float + flowAdjust[1] * 10.0) * weights[1]),
      (TaskStone, max(0.0, env.stockpileCount(teamId, ResourceStone).float + flowAdjust[2] * 10.0) * weights[2]),
      (TaskGold, max(0.0, env.stockpileCount(teamId, ResourceGold).float + flowAdjust[3] * 10.0) * weights[3])
    ]
    if altarFound:
      ordered.insert((TaskHearts, altarHearts.float), 0)
    var best = ordered[0]
    for i in 1 ..< ordered.len:
      if ordered[i][1] < best[1]:
        best = ordered[i]
    # Anti-oscillation hysteresis: only switch task if difference is significant
    let currentTask = state.gathererTask
    if best[1] <= 0.0:
      task = best[0]
    elif currentTask != TaskHearts:  # Hearts task handled separately above
      var currentScore = float.high
      for item in ordered:
        if item[0] == currentTask:
          currentScore = item[1]
          break
      # Only switch if new best is significantly better than current
      if best[1] > currentScore - TaskSwitchHysteresis:
        task = currentTask  # Keep current task
      else:
        task = best[0]
    else:
      task = best[0]
  state.gathererTask = task

proc gathererTryBuildCamp(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState,
                          teamId: int, kind: ThingKind,
                          nearbyCount, minCount: int,
                          nearbyKinds: openArray[ThingKind]): uint8 =
  if agent.unitClass != UnitVillager:
    return 0'u8
  let (didBuild, buildAct) = controller.tryBuildCampThreshold(
    env, agent, agentId, state, teamId, kind,
    nearbyCount, minCount, nearbyKinds)
  if didBuild: buildAct else: 0'u8

gathererGuard(canStartGathererPlantOnFertile, shouldTerminateGathererPlantOnFertile):
  state.gathererTask != TaskHearts and (agent.inventoryWheat > 0 or agent.inventoryWood > 0)

gathererGuard(canStartGathererCarrying, shouldTerminateGathererCarrying):
  gathererStockpileTotal(agent) > 0

proc optGathererCarrying(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  let heartsPriority = state.gathererTask == TaskHearts
  var magmaGlobal: Thing = nil
  if heartsPriority:
    magmaGlobal = findNearestThing(env, agent.pos, Magma, maxDist = int.high)

  if agent.inventoryGold > 0 and heartsPriority:
    let (didDeliver, deliverAct) = tryDeliverGoldToMagma(controller, env, agent, agentId, state, magmaGlobal)
    if didDeliver: return deliverAct

  let (didDrop, dropAct) = controller.dropoffCarrying(
    env, agent, agentId, state,
    allowFood = true, allowWood = true, allowStone = true, allowGold = not heartsPriority
  )
  if didDrop: return dropAct
  let dir = getMoveTowards(env, agent, agent.pos, basePos,
    controller.rng, (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1))
  if dir < 0:
    return saveStateAndReturn(controller, agentId, state, 0'u8)  # Noop when blocked
  return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dir.uint8))

gathererGuard(canStartGathererHearts, shouldTerminateGathererHearts):
  state.gathererTask == TaskHearts

proc optGathererHearts(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  let magmaGlobal = findNearestThing(env, agent.pos, Magma, maxDist = int.high)

  if agent.inventoryBar > 0:
    var altarPos = agent.homeAltar
    if altarPos.x < 0:
      let altar = env.findNearestThingSpiral(state, Altar)
      if not isNil(altar):
        altarPos = altar.pos
    if altarPos.x >= 0:
      return actOrMove(controller, env, agent, agentId, state, altarPos, 3'u8)
  if agent.inventoryGold > 0:
    let (didDeliver, deliverAct) = tryDeliverGoldToMagma(controller, env, agent, agentId, state, magmaGlobal)
    if didDeliver: return deliverAct
    return controller.moveNextSearch(env, agent, agentId, state)
  if state.closestMagmaPos.x < 0 and isNil(magmaGlobal):
    return controller.moveNextSearch(env, agent, agentId, state)
  let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
  if didGold: return actGold
  return controller.moveNextSearch(env, agent, agentId, state)

gathererGuard(canStartGathererResource, shouldTerminateGathererResource):
  state.gathererTask in {TaskGold, TaskWood, TaskStone}

proc optGathererResource(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  var campKind: ThingKind
  var nearbyCount, minCount: int
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
  let (didGather, actGather) = case state.gathererTask
    of TaskGold: controller.ensureGold(env, agent, agentId, state)
    of TaskWood: controller.ensureWood(env, agent, agentId, state)
    of TaskStone: controller.ensureStone(env, agent, agentId, state)
    else: (false, 0'u8)
  if didGather: return actGather
  return controller.moveNextSearch(env, agent, agentId, state)

gathererGuard(canStartGathererFood, shouldTerminateGathererFood):
  state.gathererTask == TaskFood

proc optGathererFood(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
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

  if not hasNearbyFood(env, agent.pos, 4):
    let fertileRadius = 6
    let fertileCount = countNearbyTerrain(env, basePos, fertileRadius, {Fertile})
    # Use spatial query instead of O(n) mill scan
    let nearbyMill = findNearestFriendlyThingSpatial(env, basePos, teamId, Mill, fertileRadius)
    let hasMill = not nearbyMill.isNil
    if fertileCount < 6 and not hasMill:
      if agent.inventoryWater > 0:
        var target = findFertileTarget(env, basePos, fertileRadius, state.pathBlockedTarget)
        if target.x < 0:
          target = findFertileTarget(env, agent.pos, fertileRadius, state.pathBlockedTarget)
        if target.x >= 0:
          return actOrMove(controller, env, agent, agentId, state, target, 3'u8)
      else:
        let (didWater, actWater) = controller.ensureWater(env, agent, agentId, state)
        if didWater: return actWater

  if state.closestFoodPos.x >= 0:
    if state.closestFoodPos == state.pathBlockedTarget or
       isResourceReserved(teamId, state.closestFoodPos, agent.agentId):
      state.closestFoodPos = ivec2(-1, -1)
    else:
      let knownThing = env.getThing(state.closestFoodPos)
      if isNil(knownThing) or knownThing.kind notin FoodKinds or isThingFrozen(knownThing, env):
        state.closestFoodPos = ivec2(-1, -1)
      else:
        # For cows: milk (interact) if healthy and food not critical, kill (attack) otherwise
        let verb = if knownThing.kind == Cow:
          let foodCritical = env.stockpileCount(teamId, ResourceFood) < 3
          let cowHealthy = knownThing.hp * 2 >= knownThing.maxHp
          if cowHealthy and not foodCritical: 3'u8 else: 2'u8
        else:
          3'u8
        discard reserveResource(teamId, agent.agentId, knownThing.pos, env.currentStep)
        return actOrMove(controller, env, agent, agentId, state, knownThing.pos, verb)

  for kind in [Wheat, Stubble]:
    let wheat = env.findNearestThingSpiral(state, kind)
    if isNil(wheat):
      continue
    if wheat.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    # Skip if reserved by another agent
    if isResourceReserved(teamId, wheat.pos, agent.agentId):
      continue
    updateClosestSeen(state, state.basePosition, wheat.pos, state.closestFoodPos)
    discard reserveResource(teamId, agent.agentId, wheat.pos, env.currentStep)
    return actOrMove(controller, env, agent, agentId, state, wheat.pos, 3'u8)

  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)

gathererGuard(canStartGathererIrrigate, shouldTerminateGathererIrrigate):
  agent.inventoryWater > 0

proc optGathererIrrigate(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let target = findIrrigationTarget(env, basePos, 6)
  if target.x < 0:
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, target, 3'u8)

gathererGuard(canStartGathererScavenge, shouldTerminateGathererScavenge):
  gathererStockpileTotal(agent) < ResourceCarryCapacity and env.thingsByKind[Skeleton].len > 0

proc optGathererScavenge(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let skeleton = env.findNearestThingSpiral(state, Skeleton)
  if isNil(skeleton):
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, skeleton.pos, 3'u8)

gathererGuard(canStartGathererPredatorFlee, shouldTerminateGathererPredatorFlee):
  not isNil(findNearestPredatorInRadius(env, agent.pos, GathererFleeRadius))

proc optGathererPredatorFlee(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  ## Flee away from predators toward friendly structures
  let predator = findNearestPredatorInRadius(env, agent.pos, GathererFleeRadius)
  if isNil(predator):
    return 0'u8

  let basePos = agent.getBasePos()
  state.basePosition = basePos

  # Try all directions and pick the one that maximizes distance from predator
  var bestDir = -1
  var bestScore = int.low
  for dirIdx in 0 .. 7:
    let delta = Directions8[dirIdx]
    let newPos = agent.pos + delta
    if not canEnterForMove(env, agent, agent.pos, newPos):
      continue
    # Score: distance from predator + proximity to base
    let distFromPredator = max(abs(newPos.x - predator.pos.x), abs(newPos.y - predator.pos.y))
    let distToBase = max(abs(newPos.x - basePos.x), abs(newPos.y - basePos.y))
    let score = distFromPredator * 2 - distToBase  # Prioritize getting away from predator
    if score > bestScore:
      bestScore = score
      bestDir = dirIdx

  if bestDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, bestDir.uint8))

  # If can't move, just noop
  return saveStateAndReturn(controller, agentId, state, 0'u8)

let GathererOptions* = [
  OptionDef(
    name: "GathererFlee",
    canStart: canStartGathererFlee,
    shouldTerminate: shouldTerminateGathererFlee,
    act: optGathererFlee,
    interruptible: false  # Flee is not interruptible - survival is priority
  ),
  OptionDef(
    name: "GathererPredatorFlee",
    canStart: canStartGathererPredatorFlee,
    shouldTerminate: shouldTerminateGathererPredatorFlee,
    act: optGathererPredatorFlee,
    interruptible: false  # Flee is not interruptible - survival is priority
  ),
  EmergencyHealOption,
  OptionDef(
    name: "GathererPlantOnFertile",
    canStart: canStartGathererPlantOnFertile,
    shouldTerminate: shouldTerminateGathererPlantOnFertile,
    act: optPlantOnFertile,
    interruptible: true
  ),
  MarketTradeOption,
  OptionDef(
    name: "GathererCarryingStockpile",
    canStart: canStartGathererCarrying,
    shouldTerminate: shouldTerminateGathererCarrying,
    act: optGathererCarrying,
    interruptible: true
  ),
  OptionDef(
    name: "GathererHearts",
    canStart: canStartGathererHearts,
    shouldTerminate: shouldTerminateGathererHearts,
    act: optGathererHearts,
    interruptible: true
  ),
  OptionDef(
    name: "GathererResource",
    canStart: canStartGathererResource,
    shouldTerminate: shouldTerminateGathererResource,
    act: optGathererResource,
    interruptible: true
  ),
  OptionDef(
    name: "GathererFood",
    canStart: canStartGathererFood,
    shouldTerminate: shouldTerminateGathererFood,
    act: optGathererFood,
    interruptible: true
  ),
  OptionDef(
    name: "GathererIrrigate",
    canStart: canStartGathererIrrigate,
    shouldTerminate: shouldTerminateGathererIrrigate,
    act: optGathererIrrigate,
    interruptible: true
  ),
  OptionDef(
    name: "GathererScavenge",
    canStart: canStartGathererScavenge,
    shouldTerminate: shouldTerminateGathererScavenge,
    act: optGathererScavenge,
    interruptible: true
  ),
  StoreValuablesOption,
  FallbackSearchOption
]
