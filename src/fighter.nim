const
  DividerDoorSpacing = 5
  DividerDoorOffset = 0
  DividerHalfLengthMin = 6
  DividerHalfLengthMax = 18
  DividerInvSqrt2 = 0.70710677'f32

proc fighterHasExit(env: Environment, agent: Thing): bool =
  for _, d in Directions8:
    let np = agent.pos + d
    if canEnterForMove(env, agent, agent.pos, np):
      return true
  false

proc fighterIsEnclosed(env: Environment, agent: Thing): bool =
  not fighterHasExit(env, agent)

proc fighterFindNearbyEnemy(controller: Controller, env: Environment, agent: Thing,
                            state: var AgentState): Thing =
  let enemyRadius = ObservationRadius.int32 * 2
  if state.fighterEnemyStep == env.currentStep and
      state.fighterEnemyAgentId >= 0 and state.fighterEnemyAgentId < MapAgents:
    let cached = env.agents[state.fighterEnemyAgentId]
    if cached.agentId != agent.agentId and
        isAgentAlive(env, cached) and
        not sameTeam(agent, cached) and
        int(chebyshevDist(agent.pos, cached.pos)) <= enemyRadius.int:
      return cached

  var bestEnemyDist = int.high
  var bestEnemyId = -1
  for idx, other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if sameTeam(agent, other):
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist > enemyRadius.int:
      continue
    if dist < bestEnemyDist:
      bestEnemyDist = dist
      bestEnemyId = idx

  state.fighterEnemyStep = env.currentStep
  state.fighterEnemyAgentId = bestEnemyId
  if bestEnemyId >= 0:
    return env.agents[bestEnemyId]

proc fighterHasFood(agent: Thing): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and isFoodItem(key):
      return true
  false

proc fighterIsCautious(env: Environment, agent: Thing): bool =
  var cautious = agent.hp * 2 < agent.maxHp
  if cautious:
    for other in env.agents:
      if other.agentId == agent.agentId:
        continue
      if not isAgentAlive(env, other):
        continue
      if not sameTeam(agent, other):
        continue
      if chebyshevDist(agent.pos, other.pos) <= 4'i32:
        cautious = false
        break
  cautious

proc fighterActOrMove(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState,
                      targetPos: IVec2, verb: uint8): uint8 =
  if isAdjacent(agent.pos, targetPos):
    return controller.actAt(env, agent, agentId, state, targetPos, verb)
  return controller.moveTo(env, agent, agentId, state, targetPos)

proc canStartFighterBreakout(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  fighterIsEnclosed(env, agent)

proc shouldTerminateFighterBreakout(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  not fighterIsEnclosed(env, agent)

proc optFighterBreakout(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  for dirIdx in 0 .. 7:
    let targetPos = agent.pos + Directions8[dirIdx]
    if not isValidPos(targetPos):
      continue
    if env.hasDoor(targetPos):
      return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, dirIdx.uint8))
    let blocker = env.getThing(targetPos)
    if not isNil(blocker) and blocker.kind in {Wall, Skeleton, Spawner, Tumor}:
      return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, dirIdx.uint8))
  0'u8

proc canStartFighterRetreat(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  agent.hp * 3 <= agent.maxHp

proc shouldTerminateFighterRetreat(controller: Controller, env: Environment, agent: Thing,
                                   agentId: int, state: var AgentState): bool =
  agent.hp * 3 > agent.maxHp

proc optFighterRetreat(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): uint8 =
  if agent.hp * 3 > agent.maxHp:
    return 0'u8
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  var safePos = basePos
  for kind in [Outpost, Barracks, TownCenter, Monastery]:
    let safe = env.findNearestFriendlyThingSpiral(state, teamId, kind, controller.rng)
    if not isNil(safe):
      safePos = safe.pos
      break
  controller.moveTo(env, agent, agentId, state, safePos)

proc canStartFighterDividerDefense(controller: Controller, env: Environment, agent: Thing,
                                   agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
  not isNil(enemy)

proc shouldTerminateFighterDividerDefense(controller: Controller, env: Environment, agent: Thing,
                                          agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return true
  let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
  isNil(enemy)

proc optFighterDividerDefense(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
  if isNil(enemy):
    return 0'u8
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

  var enemyBase: Thing = nil
  var bestAltarDist = int.high
  for altar in env.thingsByKind[Altar]:
    if altar.teamId == teamId:
      continue
    let dist = abs(altar.pos.x - basePos.x) + abs(altar.pos.y - basePos.y)
    if dist < bestAltarDist:
      bestAltarDist = dist
      enemyBase = altar
  let enemyPos = if not isNil(enemyBase): enemyBase.pos else: enemy.pos

  let dx = float32(enemyPos.x - basePos.x)
  let dy = float32(enemyPos.y - basePos.y)
  var lineDir = ivec2(1, 0)
  var bestScore = abs(dx * float32(lineDir.x) + dy * float32(lineDir.y))
  let candidates = [
    (ivec2(1, 0), 1.0'f32),
    (ivec2(0, 1), 1.0'f32),
    (ivec2(1, 1), DividerInvSqrt2),
    (ivec2(1, -1), DividerInvSqrt2)
  ]
  for entry in candidates:
    let dot = abs(dx * float32(entry[0].x) + dy * float32(entry[0].y))
    let score = dot * entry[1]
    if score < bestScore:
      bestScore = score
      lineDir = entry[0]

  let midPos = ivec2(
    (basePos.x + enemyPos.x) div 2,
    (basePos.y + enemyPos.y) div 2
  )

  var n1 = ivec2(0, 0)
  var n2 = ivec2(0, 0)
  if lineDir.x != 0 and lineDir.y == 0:
    n1 = ivec2(0, 1)
    n2 = ivec2(0, -1)
  elif lineDir.x == 0 and lineDir.y != 0:
    n1 = ivec2(1, 0)
    n2 = ivec2(-1, 0)
  elif lineDir.x == 1 and lineDir.y == 1:
    n1 = ivec2(1, -1)
    n2 = ivec2(-1, 1)
  else:
    n1 = ivec2(1, 1)
    n2 = ivec2(-1, -1)
  let toBase = basePos - midPos
  let normal = if toBase.x * n1.x + toBase.y * n1.y >= 0: n1 else: n2

  let dist = max(abs(enemyPos.x - basePos.x), abs(enemyPos.y - basePos.y))
  let halfLen = max(DividerHalfLengthMin, min(DividerHalfLengthMax, dist div 2))

  var bestDoor = ivec2(-1, -1)
  var bestDoorDist = int.high
  var bestOutpost = ivec2(-1, -1)
  var bestOutpostDist = int.high
  var bestWall = ivec2(-1, -1)
  var bestWallDist = int.high

  for offset in -halfLen .. halfLen:
    let pos = midPos + ivec2(lineDir.x * offset, lineDir.y * offset)
    if not isValidPos(pos):
      continue
    if env.terrain[pos.x][pos.y] == TerrainRoad:
      continue
    let distToAgent = int(chebyshevDist(agent.pos, pos))
    let raw = (offset + DividerDoorOffset) mod DividerDoorSpacing
    let normalized = if raw < 0: raw + DividerDoorSpacing else: raw
    let isDoorSlot = normalized == 0
    if isDoorSlot:
      if env.hasDoor(pos):
        let outpostPos = pos + normal
        if isValidPos(outpostPos) and env.terrain[outpostPos.x][outpostPos.y] != TerrainRoad and
            env.canPlace(outpostPos):
          let outDist = int(chebyshevDist(agent.pos, outpostPos))
          if outDist < bestOutpostDist:
            bestOutpostDist = outDist
            bestOutpost = outpostPos
      else:
        if env.canPlace(pos):
          if distToAgent < bestDoorDist:
            bestDoorDist = distToAgent
            bestDoor = pos
    else:
      if env.canPlace(pos):
        if distToAgent < bestWallDist:
          bestWallDist = distToAgent
          bestWall = pos

  var targetKind = Wall
  if bestDoor.x >= 0:
    targetKind = Door
  elif bestOutpost.x >= 0:
    targetKind = Outpost
  let targetPos = (if targetKind == Door: bestDoor elif targetKind == Outpost: bestOutpost else: bestWall)
  if targetPos.x >= 0:
    case targetKind
    of Door:
      if not env.canAffordBuild(agent, thingItem("Door")):
        let (didDrop, actDrop) = controller.dropoffCarrying(
          env, agent, agentId, state,
          allowWood = true,
          allowStone = true,
          allowGold = true
        )
        if didDrop: return actDrop
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
      let (didDoor, doorAct) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, targetPos, BuildIndexDoor
      )
      if didDoor: return doorAct
    of Outpost:
      if not env.canAffordBuild(agent, thingItem("Outpost")):
        let (didDrop, actDrop) = controller.dropoffCarrying(
          env, agent, agentId, state,
          allowWood = true,
          allowStone = true,
          allowGold = true
        )
        if didDrop: return actDrop
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
      let idx = buildIndexFor(Outpost)
      if idx >= 0:
        let (didOutpost, outpostAct) = goToAdjacentAndBuild(
          controller, env, agent, agentId, state, targetPos, idx
        )
        if didOutpost: return outpostAct
    else:
      if not env.canAffordBuild(agent, thingItem("Wall")):
        let (didDrop, actDrop) = controller.dropoffCarrying(
          env, agent, agentId, state,
          allowWood = true,
          allowStone = true,
          allowGold = true
        )
        if didDrop: return actDrop
        let (didStone, actStone) = controller.ensureStone(env, agent, agentId, state)
        if didStone: return actStone
      let (didWall, wallAct) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, targetPos, BuildIndexWall
      )
      if didWall: return wallAct
    return controller.moveTo(env, agent, agentId, state, enemy.pos)
  0'u8

proc canStartFighterLanterns(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

proc optFighterLanterns(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  var target = ivec2(-1, -1)
  var unlit: Thing = nil
  var bestUnlitDist = int.high
  for thing in env.things:
    if thing.teamId != teamId:
      continue
    if not isBuildingKind(thing.kind) or thing.kind in {ThingKind.Barrel, Door}:
      continue
    if hasTeamLanternNear(env, teamId, thing.pos):
      continue
    let dist = abs(thing.pos.x - agent.pos.x).int + abs(thing.pos.y - agent.pos.y).int
    if dist < bestUnlitDist:
      bestUnlitDist = dist
      unlit = thing

  if not isNil(unlit):
    var bestPos = ivec2(-1, -1)
    var bestDist = int.high
    for dx in -2 .. 2:
      for dy in -2 .. 2:
        if abs(dx) + abs(dy) > 2:
          continue
        let cand = unlit.pos + ivec2(dx.int32, dy.int32)
        if not isLanternPlacementValid(env, cand):
          continue
        if hasTeamLanternNear(env, teamId, cand):
          continue
        let dist = abs(cand.x - agent.pos.x).int + abs(cand.y - agent.pos.y).int
        if dist < bestDist:
          bestDist = dist
          bestPos = cand
    if bestPos.x >= 0:
      target = bestPos
  if target.x < 0:
    var lanternCount = 0
    var farthest = 0
    for thing in env.thingsByKind[Lantern]:
      if not thing.lanternHealthy or thing.teamId != teamId:
        continue
      inc lanternCount
      let dist = int(chebyshevDist(basePos, thing.pos))
      if dist > farthest:
        farthest = dist

    let desiredRadius = max(ObservationRadius + 1, max(3, farthest + 2 + lanternCount div 6))
    for _ in 0 ..< 18:
      let candidate = getNextSpiralPoint(state, controller.rng)
      if chebyshevDist(candidate, basePos) < desiredRadius:
        continue
      if not isLanternPlacementValid(env, candidate):
        continue
      if hasTeamLanternNear(env, teamId, candidate):
        continue
      target = candidate
      break

  if target.x >= 0:
    if agent.inventoryLantern > 0:
      return fighterActOrMove(controller, env, agent, agentId, state, target, 6'u8)

    if controller.getBuildingCount(env, teamId, WeavingLoom) == 0 and agent.unitClass == UnitVillager:
      if chebyshevDist(agent.pos, basePos) > 2'i32:
        let avoidDir = (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, basePos,
            controller.rng, avoidDir).uint8))
      let (didBuild, buildAct) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, WeavingLoom)
      if didBuild: return buildAct

    let hasLanternInput = agent.inventoryWheat > 0 or agent.inventoryWood > 0
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if hasLanternInput:
      if not isNil(loom):
        return fighterActOrMove(controller, env, agent, agentId, state, loom.pos, 3'u8)
      return controller.moveNextSearch(env, agent, agentId, state)

    let food = env.stockpileCount(teamId, ResourceFood)
    let wood = env.stockpileCount(teamId, ResourceWood)
    if wood <= food:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
      return controller.moveNextSearch(env, agent, agentId, state)

    for kind in [Wheat, Stubble]:
      let wheat = env.findNearestThingSpiral(state, kind, controller.rng)
      if isNil(wheat):
        continue
      return fighterActOrMove(controller, env, agent, agentId, state, wheat.pos, 3'u8)
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

  0'u8

proc canStartFighterDropoffFood(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  fighterHasFood(agent)

proc optFighterDropoffFood(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  let (didFoodDrop, foodDropAct) =
    controller.dropoffCarrying(env, agent, agentId, state, allowFood = true)
  if didFoodDrop: return foodDropAct
  0'u8

proc canStartFighterTrain(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent.agentId)
  controller.getBuildingCount(env, teamId, Barracks) > 0

proc optFighterTrain(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
  if not isNil(barracks):
    return fighterActOrMove(controller, env, agent, agentId, state, barracks.pos, 3'u8)
  0'u8

proc canStartFighterMaintainGear(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if agent.inventoryArmor < ArmorPoints:
    return true
  agent.unitClass == UnitManAtArms and agent.inventorySpear == 0

proc optFighterMaintainGear(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  if agent.inventoryArmor < ArmorPoints:
    let (didSmith, actSmith) = controller.moveToNearestSmith(env, agent, agentId, state, teamId)
    if didSmith: return actSmith
    return 0'u8

  if agent.unitClass == UnitManAtArms and agent.inventorySpear == 0:
    if agent.inventoryWood == 0:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
    let (didSmith, actSmith) = controller.moveToNearestSmith(env, agent, agentId, state, teamId)
    if didSmith: return actSmith
  0'u8

proc canStartFighterAggressive(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): bool =
  not fighterIsCautious(env, agent)

proc optFighterAggressive(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): uint8 =
  for kind in [Tumor, Spawner]:
    let target = env.findNearestThingSpiral(state, kind, controller.rng)
    if not isNil(target):
      return fighterActOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)
  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  0'u8

proc optFighterFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

let FighterOptions = [
  OptionDef(
    name: "FighterBreakout",
    canStart: canStartFighterBreakout,
    shouldTerminate: shouldTerminateFighterBreakout,
    act: optFighterBreakout,
    interruptible: true
  ),
  OptionDef(
    name: "FighterRetreat",
    canStart: canStartFighterRetreat,
    shouldTerminate: shouldTerminateFighterRetreat,
    act: optFighterRetreat,
    interruptible: true
  ),
  OptionDef(
    name: "FighterDividerDefense",
    canStart: canStartFighterDividerDefense,
    shouldTerminate: shouldTerminateFighterDividerDefense,
    act: optFighterDividerDefense,
    interruptible: true
  ),
  OptionDef(
    name: "FighterLanterns",
    canStart: canStartFighterLanterns,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterLanterns,
    interruptible: true
  ),
  OptionDef(
    name: "FighterDropoffFood",
    canStart: canStartFighterDropoffFood,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterDropoffFood,
    interruptible: true
  ),
  OptionDef(
    name: "FighterTrain",
    canStart: canStartFighterTrain,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterTrain,
    interruptible: true
  ),
  OptionDef(
    name: "FighterMaintainGear",
    canStart: canStartFighterMaintainGear,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterMaintainGear,
    interruptible: true
  ),
  OptionDef(
    name: "FighterAggressive",
    canStart: canStartFighterAggressive,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterAggressive,
    interruptible: true
  ),
  OptionDef(
    name: "FighterFallbackSearch",
    canStart: optionsAlwaysCanStart,
    shouldTerminate: optionsAlwaysTerminate,
    act: optFighterFallbackSearch,
    interruptible: true
  )
]

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  return runOptions(controller, env, agent, agentId, state, FighterOptions)
