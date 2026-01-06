proc findNearestEnemyAgent(env: Environment, agent: Thing, radius: int32): Thing =
  var bestDist = int.high
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if sameTeam(agent, other):
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist > radius.int:
      continue
    if dist < bestDist:
      bestDist = dist
      result = other

const
  DividerDoorSpacing = 5
  DividerDoorOffset = 0
  DividerHalfLengthMin = 6
  DividerHalfLengthMax = 18
  DividerInvSqrt2 = 0.70710677'f32

proc findNearestEnemyAltar(env: Environment, basePos: IVec2, teamId: int): Thing =
  var bestDist = int.high
  for altar in env.thingsByKind[Altar]:
    if altar.teamId == teamId:
      continue
    let dist = abs(altar.pos.x - basePos.x) + abs(altar.pos.y - basePos.y)
    if dist < bestDist:
      bestDist = dist
      result = altar

proc dividerLineDir(basePos, enemyPos: IVec2): IVec2 =
  let dx = float32(enemyPos.x - basePos.x)
  let dy = float32(enemyPos.y - basePos.y)
  var bestDir = ivec2(1, 0)
  var bestScore = abs(dx * float32(bestDir.x) + dy * float32(bestDir.y))
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
      bestDir = entry[0]
  bestDir

proc dividerNormalTowardBase(basePos, midPos, lineDir: IVec2): IVec2 =
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
  if toBase.x * n1.x + toBase.y * n1.y >= 0:
    return n1
  n2

proc isDividerDoorSlot(offset: int): bool =
  let raw = (offset + DividerDoorOffset) mod DividerDoorSpacing
  let normalized = if raw < 0: raw + DividerDoorSpacing else: raw
  normalized == 0

proc findDividerBuildTarget(env: Environment, basePos, enemyPos, agentPos: IVec2):
    tuple[found: bool, kind: ThingKind, pos: IVec2] =
  let lineDir = dividerLineDir(basePos, enemyPos)
  let midPos = ivec2(
    (basePos.x + enemyPos.x) div 2,
    (basePos.y + enemyPos.y) div 2
  )
  let normal = dividerNormalTowardBase(basePos, midPos, lineDir)
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
    let distToAgent = int(chebyshevDist(agentPos, pos))
    if isDividerDoorSlot(offset):
      if env.hasDoor(pos):
        let outpostPos = pos + normal
        if isValidPos(outpostPos) and env.terrain[outpostPos.x][outpostPos.y] != TerrainRoad and
            env.canPlaceBuilding(outpostPos):
          let outDist = int(chebyshevDist(agentPos, outpostPos))
          if outDist < bestOutpostDist:
            bestOutpostDist = outDist
            bestOutpost = outpostPos
      else:
        if env.canPlaceBuilding(pos):
          if distToAgent < bestDoorDist:
            bestDoorDist = distToAgent
            bestDoor = pos
    else:
      if env.canPlaceBuilding(pos):
        if distToAgent < bestWallDist:
          bestWallDist = distToAgent
          bestWall = pos

  if bestDoor.x >= 0:
    return (true, Door, bestDoor)
  if bestOutpost.x >= 0:
    return (true, Outpost, bestOutpost)
  if bestWall.x >= 0:
    return (true, Wall, bestWall)
  (false, Wall, ivec2(-1, -1))

proc preferLanternWood(env: Environment, teamId: int): bool =
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  if wood != food:
    return wood < food
  true

proc chooseLanternTarget(controller: Controller, env: Environment, agent: Thing,
                         teamId: int, state: var AgentState, basePos: IVec2): IVec2 =
  let unlit = findNearestUnlitBuilding(env, teamId, agent.pos)
  if not isNil(unlit):
    return findLanternSpotNearBuilding(env, teamId, agent, unlit)

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
    return candidate

  ivec2(-1, -1)

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

  # React to nearby enemy agents by fortifying outward.
  let enemy = findNearestEnemyAgent(env, agent, ObservationRadius.int32 * 2)
  if not isNil(enemy):
    if agent.unitClass == UnitVillager:
      let enemyBase = findNearestEnemyAltar(env, basePos, teamId)
      let enemyPos = if not isNil(enemyBase): enemyBase.pos else: enemy.pos
      let target = findDividerBuildTarget(env, basePos, enemyPos, agent.pos)
      if target.found:
        case target.kind
        of Door:
          let doorKey = thingItem("Door")
          if not env.canAffordBuild(teamId, doorKey):
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
            controller, env, agent, agentId, state, target.pos, BuildIndexDoor
          )
          if didDoor: return doorAct
        of Outpost:
          let outpostKey = thingItem("Outpost")
          if not env.canAffordBuild(teamId, outpostKey):
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
              controller, env, agent, agentId, state, target.pos, idx
            )
            if didOutpost: return outpostAct
        else:
          let wallKey = thingItem("Wall")
          if not env.canAffordBuild(teamId, wallKey):
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
            controller, env, agent, agentId, state, target.pos, BuildIndexWall
          )
          if didWall: return wallAct
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, enemy.pos, controller.rng).uint8))

  # Keep buildings lit, then push lanterns farther out from the base.
  let target = chooseLanternTarget(controller, env, agent, teamId, state, basePos)

  if target.x >= 0:
    if agent.inventoryLantern > 0:
      if chebyshevDist(agent.pos, target) == 1'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(6'u8, neighborDirIndex(agent.pos, target).uint8))
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, target, controller.rng).uint8))

    # No lantern in inventory: craft or gather resources to make one.
    if controller.getBuildingCount(env, teamId, WeavingLoom) == 0 and agent.unitClass == UnitVillager:
      if chebyshevDist(agent.pos, basePos) > 2'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, basePos, controller.rng).uint8))
      let (didBuild, buildAct) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, WeavingLoom)
      if didBuild: return buildAct

    let hasLanternInput = agent.inventoryWheat > 0 or agent.inventoryWood > 0
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if hasLanternInput:
      if not isNil(loom):
        return controller.useOrMove(env, agent, agentId, state, loom.pos)
      return controller.moveNextSearch(env, agent, agentId, state)

    if preferLanternWood(env, teamId):
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
      return controller.moveNextSearch(env, agent, agentId, state)

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      return controller.useOrMove(env, agent, agentId, state, wheat.pos)
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

  # Drop off any carried food (meat counts as food) when not in immediate combat.
  let (didFoodDrop, foodDropAct) =
    controller.dropoffCarrying(env, agent, agentId, state, allowFood = true)
  if didFoodDrop: return foodDropAct

  # Train into a combat unit when possible.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if not isNil(barracks):
      return controller.useOrMove(env, agent, agentId, state, barracks.pos)

  # Maintain armor and spears.
  if agent.inventoryArmor < ArmorPoints:
    let (didSmith, actSmith) = controller.moveToNearestSmith(env, agent, agentId, state, teamId)
    if didSmith: return actSmith

  if agent.unitClass == UnitManAtArms and agent.inventorySpear == 0:
    if agent.inventoryWood == 0:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
    let (didSmith, actSmith) = controller.moveToNearestSmith(env, agent, agentId, state, teamId)
    if didSmith: return actSmith

  # Seek tumors/spawners when idle.
  let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
  if not isNil(tumor):
    return controller.attackOrMove(env, agent, agentId, state, tumor.pos)
  let spawner = env.findNearestThingSpiral(state, Spawner, controller.rng)
  if not isNil(spawner):
    return controller.attackOrMove(env, agent, agentId, state, spawner.pos)

  # Hunt while patrolling if nothing else to do.
  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)
