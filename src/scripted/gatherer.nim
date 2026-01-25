const GathererFleeRadius = 8  # Smaller than fighter detection - flee early to survive

proc gathererFindNearbyEnemy(env: Environment, agent: Thing): Thing =
  ## Find nearest enemy agent within flee radius
  let teamId = getTeamId(agent)
  let fleeRadius = GathererFleeRadius.int32
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

proc canStartGathererFlee(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  not isNil(gathererFindNearbyEnemy(env, agent))

proc shouldTerminateGathererFlee(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  isNil(gathererFindNearbyEnemy(env, agent))

proc optGathererFlee(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  ## Flee toward home altar when enemies are nearby
  let enemy = gathererFindNearbyEnemy(env, agent)
  if isNil(enemy):
    return 0'u8
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
      if terrain notin BuildableTerrain or terrain == Road:
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < bestDist:
        bestDist = dist
        bestPos = pos
  bestPos

const FoodKinds = {Wheat, Stubble, Fish, Bush, Cow, Corpse}

proc updateGathererTask(controller: Controller, env: Environment, agent: Thing,
                        state: var AgentState) =
  let teamId = getTeamId(agent)
  var altarPos = ivec2(-1, -1)
  var altarHearts = 0
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      altarPos = homeAltar.pos
      altarHearts = homeAltar.hearts
  if altarPos.x < 0:
    var bestDist = int.high
    for altar in env.thingsByKind[Altar]:
      if altar.teamId != teamId:
        continue
      let dist = abs(altar.pos.x - agent.pos.x) + abs(altar.pos.y - agent.pos.y)
      if dist < bestDist:
        bestDist = dist
        altarPos = altar.pos
        altarHearts = altar.hearts
  let altarFound = altarPos.x >= 0
  var task = TaskFood
  if altarFound and altarHearts < 10:
    task = TaskHearts
  else:
    var ordered: seq[(GathererTask, int)] = @[
      (TaskFood, env.stockpileCount(teamId, ResourceFood)),
      (TaskWood, env.stockpileCount(teamId, ResourceWood)),
      (TaskStone, env.stockpileCount(teamId, ResourceStone)),
      (TaskGold, env.stockpileCount(teamId, ResourceGold))
    ]
    if altarFound:
      ordered.insert((TaskHearts, altarHearts), 0)
    var best = ordered[0]
    for i in 1 ..< ordered.len:
      if ordered[i][1] < best[1]:
        best = ordered[i]
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
    nearbyCount, minCount,
    nearbyKinds
  )
  if didBuild: return buildAct
  0'u8

proc canStartGathererPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  state.gathererTask != TaskHearts and (agent.inventoryWheat > 0 or agent.inventoryWood > 0)

proc optGathererPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): uint8 =
  let (didPlant, actPlant) = controller.tryPlantOnFertile(env, agent, agentId, state)
  if didPlant: return actPlant
  0'u8

proc canStartGathererCarrying(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      return true
  false

proc canStartGathererMarket(controller: Controller, env: Environment, agent: Thing,
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

proc optGathererMarket(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  state.basePosition = agent.getBasePos()
  let market = env.findNearestFriendlyThingSpiral(state, teamId, Market)
  if isNil(market) or market.cooldown != 0:
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, market.pos, 3'u8)

proc optGathererCarrying(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  let heartsPriority = state.gathererTask == TaskHearts
  var magmaGlobal: Thing = nil
  if heartsPriority:
    magmaGlobal = findNearestThing(env, agent.pos, Magma, maxDist = int.high)

  if agent.inventoryGold > 0 and heartsPriority:
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
    if didKnown: return actKnown
    if not isNil(magmaGlobal):
      updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
      return actOrMove(controller, env, agent, agentId, state, magmaGlobal.pos, 3'u8)

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

proc canStartGathererHearts(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
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
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
    if didKnown: return actKnown
    if not isNil(magmaGlobal):
      updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
      return actOrMove(controller, env, agent, agentId, state, magmaGlobal.pos, 3'u8)
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
  let teamId = getTeamId(agent)
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

  block waterFertile:
    block:
      let radius = 4
      let (startX, endX, startY, endY) = radiusBounds(agent.pos, radius)
      let cx = agent.pos.x.int
      let cy = agent.pos.y.int
      var hasNearbyFood = false
      for x in startX .. endX:
        for y in startY .. endY:
          if max(abs(x - cx), abs(y - cy)) > radius:
            continue
          let occ = env.grid[x][y]
          if not isNil(occ) and occ.kind in FoodKinds:
            hasNearbyFood = true
            break
          let background = env.backgroundGrid[x][y]
          if not isNil(background) and background.kind in FoodKinds:
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
          return actOrMove(controller, env, agent, agentId, state, target, 3'u8)
      else:
        let (didWater, actWater) = controller.ensureWater(env, agent, agentId, state)
        if didWater: return actWater

  if state.closestFoodPos.x >= 0:
    if state.closestFoodPos == state.pathBlockedTarget:
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
        return actOrMove(controller, env, agent, agentId, state, knownThing.pos, verb)

  for kind in [Wheat, Stubble]:
    let wheat = env.findNearestThingSpiral(state, kind)
    if isNil(wheat):
      continue
    if wheat.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    updateClosestSeen(state, state.basePosition, wheat.pos, state.closestFoodPos)
    return actOrMove(controller, env, agent, agentId, state, wheat.pos, 3'u8)

  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)

proc canStartGathererIrrigate(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  agent.inventoryWater > 0

proc optGathererIrrigate(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let basePos = agent.getBasePos()
  let target = findIrrigationTarget(env, basePos, 6)
  if target.x < 0:
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, target, 3'u8)

proc canStartGathererScavenge(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  var total = 0
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      total += count
  max(0, ResourceCarryCapacity - total) > 0 and env.thingsByKind[Skeleton].len > 0

proc optGathererScavenge(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  let skeleton = env.findNearestThingSpiral(state, Skeleton)
  if isNil(skeleton):
    return 0'u8
  return actOrMove(controller, env, agent, agentId, state, skeleton.pos, 3'u8)

proc optGathererFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

proc findNearestPredatorInRadius(env: Environment, pos: IVec2, radius: int): Thing =
  ## Find the nearest wolf or bear within the given radius
  var best: Thing = nil
  var bestDist = int.high
  for kind in [Wolf, Bear]:
    for thing in env.thingsByKind[kind]:
      let dist = int(max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y)))
      if dist <= radius and dist < bestDist:
        bestDist = dist
        best = thing
  best

proc canStartGathererPredatorFlee(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  ## Gatherers flee when a predator is within the flee radius
  let predator = findNearestPredatorInRadius(env, agent.pos, GathererFleeRadius)
  not isNil(predator)

proc shouldTerminateGathererPredatorFlee(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  ## Stop fleeing when no predators are within the flee radius
  let predator = findNearestPredatorInRadius(env, agent.pos, GathererFleeRadius)
  isNil(predator)

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
  OptionDef(
    name: "GathererPlantOnFertile",
    canStart: canStartGathererPlantOnFertile,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererPlantOnFertile,
    interruptible: true
  ),
  OptionDef(
    name: "GathererMarketTrade",
    canStart: canStartGathererMarket,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererMarket,
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
    name: "GathererIrrigate",
    canStart: canStartGathererIrrigate,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererIrrigate,
    interruptible: true
  ),
  OptionDef(
    name: "GathererScavenge",
    canStart: canStartGathererScavenge,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererScavenge,
    interruptible: true
  ),
  StoreValuablesOption,
  OptionDef(
    name: "GathererFallbackSearch",
    canStart: optionsAlwaysCanStart,
    shouldTerminate: optionsAlwaysTerminate,
    act: optGathererFallbackSearch,
    interruptible: true
  )
]
