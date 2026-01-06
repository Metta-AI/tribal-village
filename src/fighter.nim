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

proc countTeamOutpostsNear(env: Environment, teamId: int, pos: IVec2, radius: int32): int =
  for thing in env.things:
    if thing.kind != Outpost:
      continue
    if thing.teamId != teamId:
      continue
    if chebyshevDist(thing.pos, pos) <= radius:
      inc result

proc defenseFrontierPos(basePos, enemyPos: IVec2): IVec2 =
  let dx = signi(enemyPos.x - basePos.x)
  let dy = signi(enemyPos.y - basePos.y)
  let dist = max(abs(enemyPos.x - basePos.x), abs(enemyPos.y - basePos.y))
  let step = max(4'i32, min(8'i32, int32(dist div 2)))
  clampToPlayable(basePos + ivec2(dx * step, dy * step))


proc buildWallToward(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState, targetPos: IVec2): uint8 =
  let dirIdx = neighborDirIndex(agent.pos, targetPos)
  let step = agent.pos + orientationToVec(Orientation(dirIdx))
  if agent.orientation == Orientation(dirIdx) and isValidPos(step) and env.isEmpty(step) and
     not env.hasDoor(step) and env.terrain[step.x][step.y] in {TerrainEmpty, TerrainGrass, TerrainSand, TerrainSnow,
                                                              TerrainDune, TerrainStalagmite, TerrainBridge} and
     not isTileFrozen(step, env):
    return saveStateAndReturn(controller, agentId, state, encodeAction(8'u8, BuildIndexWall.uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8))

proc decideFighter(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)
  let basePos = if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos
  state.basePosition = basePos

  # React to nearby enemy agents by fortifying outward.
  let enemy = findNearestEnemyAgent(env, agent, ObservationRadius.int32 * 2)
  if enemy != nil:
    let frontier = defenseFrontierPos(basePos, enemy.pos)
    if agent.unitClass == UnitVillager:
      let outpostCount = countTeamOutpostsNear(env, teamId, frontier, 6)
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
        if idx >= 0 and chebyshevDist(agent.pos, frontier) <= 1'i32:
          let (didBuild, buildAct) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
          if didBuild: return buildAct
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, frontier, controller.rng).uint8))
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
      return buildWallToward(controller, env, agent, agentId, state, frontier)
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, enemy.pos, controller.rng).uint8))

  # Keep buildings lit, then push lanterns farther out from the base.
  let unlit = findNearestUnlitBuilding(env, teamId, agent.pos)
  var target = ivec2(-1, -1)
  if unlit != nil:
    target = findLanternSpotNearBuilding(env, teamId, agent, unlit)
  else:
    let lanternCount = countTeamLanterns(env, teamId)
    let farthest = farthestLanternDist(env, teamId, basePos)
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
    if env.countTeamBuildings(teamId, WeavingLoom) == 0 and agent.unitClass == UnitVillager:
      if chebyshevDist(agent.pos, basePos) > 2'i32:
        return saveStateAndReturn(controller, agentId, state,
          encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, basePos, controller.rng).uint8))
      let (didBuild, buildAct) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, WeavingLoom)
      if didBuild: return buildAct

    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom, controller.rng)
    if loom != nil and (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
      return controller.useOrMove(env, agent, agentId, state, loom.pos)

    let (didWheat, actWheat) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
    if didWheat: return actWheat
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

  # Train into a combat unit when possible.
  if agent.unitClass == UnitVillager:
    let barracks = env.findNearestFriendlyThingSpiral(state, teamId, Barracks, controller.rng)
    if barracks != nil:
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
  if tumor != nil:
    return controller.attackOrMove(env, agent, agentId, state, tumor.pos)
  let spawner = env.findNearestThingSpiral(state, Spawner, controller.rng)
  if spawner != nil:
    return controller.attackOrMove(env, agent, agentId, state, spawner.pos)

  # Hunt while patrolling if nothing else to do.
  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  return controller.moveNextSearch(env, agent, agentId, state)
