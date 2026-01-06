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

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

  # React to nearby enemy agents by fortifying outward.
  let enemy = findNearestEnemyAgent(env, agent, ObservationRadius.int32 * 2)
  if not isNil(enemy):
    let dx = signi(enemy.pos.x - basePos.x)
    let dy = signi(enemy.pos.y - basePos.y)
    let dist = max(abs(enemy.pos.x - basePos.x), abs(enemy.pos.y - basePos.y))
    let step = max(4'i32, min(8'i32, int32(dist div 2)))
    let frontier = clampToPlayable(basePos + ivec2(dx * step, dy * step))
    if agent.unitClass == UnitVillager:
      var outpostCount = 0
      for thing in env.things:
        if thing.kind != Outpost:
          continue
        if thing.teamId != teamId:
          continue
        if chebyshevDist(thing.pos, frontier) <= 6:
          inc outpostCount
      let outpostKey = thingItem("Outpost")
      if outpostCount < 2:
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
          let (didBuild, buildAct) = goToAdjacentAndBuild(
            controller, env, agent, agentId, state, frontier, idx
          )
          if didBuild: return buildAct
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
        controller, env, agent, agentId, state, frontier, BuildIndexWall
      )
      if didWall: return wallAct
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, enemy.pos, controller.rng).uint8))

  # Drop off any carried food (meat counts as food) when not in immediate combat.
  let (didFoodDrop, foodDropAct) =
    controller.dropoffCarrying(env, agent, agentId, state, allowFood = true)
  if didFoodDrop: return foodDropAct

  # Keep buildings lit, then push lanterns farther out from the base.
  let unlit = findNearestUnlitBuilding(env, teamId, agent.pos)
  var target = ivec2(-1, -1)
  if not isNil(unlit):
    target = findLanternSpotNearBuilding(env, teamId, agent, unlit)
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

    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if not isNil(loom) and (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
      return controller.useOrMove(env, agent, agentId, state, loom.pos)

    let wheat = env.findNearestThingSpiral(state, Wheat, controller.rng)
    if not isNil(wheat):
      return controller.useOrMove(env, agent, agentId, state, wheat.pos)
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

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
