const
  DividerDoorSpacing = 5
  DividerDoorOffset = 0
  DividerHalfLengthMin = 6
  DividerHalfLengthMax = 18
  DividerInvSqrt2 = 0.70710677'f32

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos
  template actOrMove(targetPos: IVec2, verb: uint8) =
    if isAdjacent(agent.pos, targetPos):
      return controller.actAt(env, agent, agentId, state, targetPos, verb)
    return controller.moveTo(env, agent, agentId, state, targetPos)

  # React to nearby enemy agents by fortifying outward.
  var enemy: Thing = nil
  var bestEnemyDist = int.high
  let enemyRadius = ObservationRadius.int32 * 2
  for other in env.agents:
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
      enemy = other
  if not isNil(enemy):
    if agent.unitClass == UnitVillager:
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
                env.canPlaceBuilding(outpostPos):
              let outDist = int(chebyshevDist(agent.pos, outpostPos))
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

      var targetFound = false
      var targetKind = Wall
      var targetPos = ivec2(-1, -1)
      if bestDoor.x >= 0:
        targetFound = true
        targetKind = Door
        targetPos = bestDoor
      elif bestOutpost.x >= 0:
        targetFound = true
        targetKind = Outpost
        targetPos = bestOutpost
      elif bestWall.x >= 0:
        targetFound = true
        targetKind = Wall
        targetPos = bestWall

      if targetFound:
        case targetKind
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
            controller, env, agent, agentId, state, targetPos, BuildIndexDoor
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
              controller, env, agent, agentId, state, targetPos, idx
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
            controller, env, agent, agentId, state, targetPos, BuildIndexWall
          )
          if didWall: return wallAct
    let avoidDir = (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, enemy.pos,
        controller.rng, avoidDir).uint8))

  # Keep buildings lit, then push lanterns farther out from the base.
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
    target = bestPos
  else:
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
      actOrMove(target, 6'u8)

    # No lantern in inventory: craft or gather resources to make one.
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
        actOrMove(loom.pos, 3'u8)
      return controller.moveNextSearch(env, agent, agentId, state)

    let food = env.stockpileCount(teamId, ResourceFood)
    let wood = env.stockpileCount(teamId, ResourceWood)
    if wood <= food:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
      return controller.moveNextSearch(env, agent, agentId, state)

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      actOrMove(wheat.pos, 3'u8)
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
      actOrMove(barracks.pos, 3'u8)

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
    actOrMove(tumor.pos, 2'u8)
  let spawner = env.findNearestThingSpiral(state, Spawner, controller.rng)
  if not isNil(spawner):
    actOrMove(spawner.pos, 2'u8)

  # Hunt while patrolling if nothing else to do.
  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)
