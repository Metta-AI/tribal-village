import coordination

const
  DividerDoorSpacing = 5
  DividerDoorOffset = 0
  DividerHalfLengthMin = 6
  DividerHalfLengthMax = 18
  DividerInvSqrt2 = 0.70710677'f32
  FighterTrainKinds = [Castle, MangonelWorkshop, SiegeWorkshop, Stable, ArcheryRange, Barracks, Monastery]
  FighterSiegeTrainKinds = [MangonelWorkshop, SiegeWorkshop]
  # Target swapping constants
  TargetSwapInterval = 10  # Re-evaluate target every N ticks
  LowHpThreshold = 0.33    # Enemies below this HP ratio get priority
  AllyThreatRadius = 2     # Distance at which enemy is considered threatening an ally
  # Escort behavior constants
  EscortRadius = 3         # Stay within this distance of the protected unit

proc stanceAllowsChase*(agent: Thing): bool =
  ## Returns true if the agent's stance allows chasing enemies.
  ## Aggressive: chase freely
  ## Defensive: limited chase (within observation radius of home)
  ## StandGround/NoAttack: no chasing
  case agent.stance
  of StanceAggressive: true
  of StanceDefensive: true  # Defensive allows chasing, but returns to position
  of StanceStandGround, StanceNoAttack: false

proc stanceAllowsMovementToAttack*(agent: Thing): bool =
  ## Returns true if the agent's stance allows moving to attack.
  ## Used for determining if agent should move toward enemy to engage.
  case agent.stance
  of StanceAggressive, StanceDefensive: true
  of StanceStandGround, StanceNoAttack: false

proc fighterIsEnclosed(env: Environment, agent: Thing): bool =
  for _, d in Directions8:
    let np = agent.pos + d
    if canEnterForMove(env, agent, agent.pos, np):
      return false
  true

proc isThreateningAlly(env: Environment, enemy: Thing, teamId: int): bool =
  ## Check if an enemy is close enough to any ally to be considered a threat.
  ## Returns true if the enemy is within AllyThreatRadius of any friendly unit.
  for other in env.agents:
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) != teamId:
      continue
    if int(chebyshevDist(enemy.pos, other.pos)) <= AllyThreatRadius:
      return true
  false

proc scoreEnemy(env: Environment, agent: Thing, enemy: Thing, teamId: int): float =
  ## Score an enemy for target selection. Higher score = better target.
  ## Considers: distance, HP ratio, and threat to allies.
  var score = 0.0
  let dist = int(chebyshevDist(agent.pos, enemy.pos))

  # Base score from distance (closer is better, max ~20 points for adjacent)
  score += float(20 - min(dist, 20))

  # Bonus for low HP enemies (easier to finish off) - up to 15 points
  let hpRatio = if enemy.maxHp > 0: float(enemy.hp) / float(enemy.maxHp) else: 1.0
  if hpRatio <= LowHpThreshold:
    score += 15.0  # High priority for very low HP targets
  elif hpRatio <= 0.5:
    score += 10.0  # Medium priority for half-HP targets
  elif hpRatio <= 0.75:
    score += 5.0   # Small bonus for wounded targets

  # Bonus for enemies threatening allies - up to 20 points
  if isThreateningAlly(env, enemy, teamId):
    score += 20.0

  score

proc fighterFindNearbyEnemy(controller: Controller, env: Environment, agent: Thing,
                            state: var AgentState): Thing =
  ## Find the best enemy target using smart target selection with periodic re-evaluation.
  ## Prioritizes: enemies threatening allies > low HP enemies > closest enemies.
  ## On lower difficulties (advancedTargetingEnabled=false), simply picks the closest enemy.
  let enemyRadius = ObservationRadius.int32 * 2
  let teamId = getTeamId(agent)
  let diffConfig = controller.getDifficulty(teamId)
  let useAdvancedTargeting = diffConfig.advancedTargetingEnabled

  # Check if we should use cached target or re-evaluate
  # Re-evaluate every TargetSwapInterval ticks or if cache is stale
  let shouldReevaluate = (env.currentStep - state.fighterEnemyStep) >= TargetSwapInterval

  if not shouldReevaluate and state.fighterEnemyStep >= 0 and
      state.fighterEnemyAgentId >= 0 and state.fighterEnemyAgentId < MapAgents:
    let cached = env.agents[state.fighterEnemyAgentId]
    if cached.agentId != agent.agentId and
        isAgentAlive(env, cached) and
        not sameTeam(agent, cached) and
        int(chebyshevDist(agent.pos, cached.pos)) <= enemyRadius.int:
      return cached

  # Re-evaluate: find the best target
  var bestScore = float.low
  var bestDist = int.high
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

    if useAdvancedTargeting:
      # Smart targeting: use scoring based on HP, threat level, etc.
      let score = scoreEnemy(env, agent, other, teamId)
      if score > bestScore:
        bestScore = score
        bestEnemyId = idx
    else:
      # Simple targeting: just pick the closest enemy
      if dist < bestDist:
        bestDist = dist
        bestEnemyId = idx

  state.fighterEnemyStep = env.currentStep
  state.fighterEnemyAgentId = bestEnemyId
  if bestEnemyId >= 0:
    return env.agents[bestEnemyId]

proc fighterSeesEnemyStructure(env: Environment, agent: Thing): bool =
  let teamId = getTeamId(agent)
  for thing in env.things:
    if thing.isNil or thing.teamId == teamId:
      continue
    if not isBuildingKind(thing.kind):
      continue
    if thing.kind notin AttackableStructures:
      continue
    if chebyshevDist(agent.pos, thing.pos) <= ObservationRadius.int32:
      return true
  false

proc canStartFighterMonk(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitMonk

proc shouldTerminateFighterMonk(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  # Terminate when no longer a monk
  agent.unitClass != UnitMonk

proc optFighterMonk(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  if agent.inventoryRelic > 0:
    let monastery = env.findNearestFriendlyThingSpiral(state, teamId, Monastery)
    if not isNil(monastery):
      var dropPos = ivec2(-1, -1)
      for d in Directions8:
        let cand = monastery.pos + d
        if not isValidPos(cand):
          continue
        if env.isEmpty(cand) and not env.hasDoor(cand) and
            env.terrain[cand.x][cand.y] != Water and not isTileFrozen(cand, env):
          dropPos = cand
          break
      if dropPos.x >= 0:
        return actOrMove(controller, env, agent, agentId, state, dropPos, 3'u8)
      return controller.moveTo(env, agent, agentId, state, monastery.pos)

  let relic = env.findNearestThingSpiral(state, Relic)
  if not isNil(relic):
    return actOrMove(controller, env, agent, agentId, state, relic.pos, 3'u8)

  var bestEnemy: Thing = nil
  var bestDist = int.high
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) == teamId:
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist < bestDist:
      bestDist = dist
      bestEnemy = other
  if not isNil(bestEnemy):
    return actOrMove(controller, env, agent, agentId, state, bestEnemy.pos, 2'u8)

  controller.moveNextSearch(env, agent, agentId, state)

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

const
  HealerSeekRadius = 30  # Max distance to search for friendly monks
  MonkHealRadius = 2     # Distance to stay near monk for healing (matches MonkAuraRadius)

proc findNearestFriendlyMonk(env: Environment, agent: Thing): Thing =
  ## Find the nearest friendly monk to seek healing from.
  let teamId = getTeamId(agent)
  var bestMonk: Thing = nil
  var bestDist = int.high
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) != teamId:
      continue
    if other.unitClass != UnitMonk:
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist > HealerSeekRadius:
      continue
    if dist < bestDist:
      bestDist = dist
      bestMonk = other
  bestMonk

proc canStartFighterSeekHealer(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): bool =
  ## Seek healer when low HP and no bread available.
  ## This is more targeted than generic retreat - actively seeks monk healing.
  if agent.hp * 3 > agent.maxHp:  # Only when HP <= 33%
    return false
  if agent.inventoryBread > 0:  # Can self-heal with bread instead
    return false
  not isNil(findNearestFriendlyMonk(env, agent))

proc shouldTerminateFighterSeekHealer(controller: Controller, env: Environment, agent: Thing,
                                      agentId: int, state: var AgentState): bool =
  ## Stop seeking healer when HP recovered or no monk available
  if agent.hp * 3 > agent.maxHp:  # HP recovered above threshold
    return true
  if agent.inventoryBread > 0:  # Got bread, can self-heal
    return true
  isNil(findNearestFriendlyMonk(env, agent))  # No monk to seek

proc optFighterSeekHealer(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): uint8 =
  ## Move toward the nearest friendly monk to benefit from their healing aura.
  let monk = findNearestFriendlyMonk(env, agent)
  if isNil(monk):
    return 0'u8
  let dist = int(chebyshevDist(agent.pos, monk.pos))
  # Already within monk's healing aura - stay put and wait for healing
  if dist <= MonkHealRadius:
    return 0'u8
  # Move toward the monk
  controller.moveTo(env, agent, agentId, state, monk.pos)

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
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  var safePos = basePos
  for kind in [Outpost, Barracks, TownCenter, Monastery]:
    let safe = env.findNearestFriendlyThingSpiral(state, teamId, kind)
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
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
  state.basePosition = basePos
  # Request defense from builders via coordination system
  requestDefenseFromBuilder(env, agent, enemy.pos)

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
    let posTerrain = env.terrain[pos.x][pos.y]
    if posTerrain == TerrainRoad or isRampTerrain(posTerrain):
      continue
    let distToAgent = int(chebyshevDist(agent.pos, pos))
    let raw = (offset + DividerDoorOffset) mod DividerDoorSpacing
    let normalized = if raw < 0: raw + DividerDoorSpacing else: raw
    let isDoorSlot = normalized == 0
    if isDoorSlot:
      if env.hasDoor(pos):
        let outpostPos = pos + normal
        let outpostTerrain = env.terrain[outpostPos.x][outpostPos.y]
        if isValidPos(outpostPos) and outpostTerrain != TerrainRoad and
            not isRampTerrain(outpostTerrain) and env.canPlace(outpostPos):
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
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
      let (didWall, wallAct) = goToAdjacentAndBuild(
        controller, env, agent, agentId, state, targetPos, BuildIndexWall
      )
      if didWall: return wallAct
    return controller.moveTo(env, agent, agentId, state, enemy.pos)
  0'u8

proc canStartFighterLanterns(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

proc shouldTerminateFighterLanterns(controller: Controller, env: Environment, agent: Thing,
                                    agentId: int, state: var AgentState): bool =
  ## Terminate when agent has no lanterns and isn't a villager (can't craft more)
  agent.inventoryLantern == 0 and agent.unitClass != UnitVillager

proc optFighterLanterns(controller: Controller, env: Environment, agent: Thing,
                        agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let basePos = agent.getBasePos()
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
      let candidate = getNextSpiralPoint(state)
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
      return actOrMove(controller, env, agent, agentId, state, target, 6'u8)

    if controller.getBuildingCount(env, teamId, WeavingLoom) == 0 and agent.unitClass == UnitVillager:
      if chebyshevDist(agent.pos, basePos) > 2'i32:
        let avoidDir = (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
        let dir = getMoveTowards(env, agent, agent.pos, basePos, controller.rng, avoidDir)
        if dir >= 0:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dir.uint8))
        # Fall through to try building if can't move
      let (didBuild, buildAct) = controller.tryBuildIfMissing(env, agent, agentId, state, teamId, WeavingLoom)
      if didBuild: return buildAct

    let hasLanternInput = agent.inventoryWheat > 0 or agent.inventoryWood > 0
    let loom = env.findNearestFriendlyThingSpiral(state, teamId, WeavingLoom)
    if hasLanternInput:
      if not isNil(loom):
        return actOrMove(controller, env, agent, agentId, state, loom.pos, 3'u8)
      return controller.moveNextSearch(env, agent, agentId, state)

    let food = env.stockpileCount(teamId, ResourceFood)
    let wood = env.stockpileCount(teamId, ResourceWood)
    if wood <= food:
      let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
      if didWood: return actWood
      return controller.moveNextSearch(env, agent, agentId, state)

    for kind in [Wheat, Stubble]:
      let wheat = env.findNearestThingSpiral(state, kind)
      if isNil(wheat):
        continue
      return actOrMove(controller, env, agent, agentId, state, wheat.pos, 3'u8)
    let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
    if didWood: return actWood
    return controller.moveNextSearch(env, agent, agentId, state)

  0'u8

proc canStartFighterDropoffFood(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and isFoodItem(key):
      return true
  false

proc shouldTerminateFighterDropoffFood(controller: Controller, env: Environment, agent: Thing,
                                       agentId: int, state: var AgentState): bool =
  # Terminate when no longer carrying food
  for key, count in agent.inventory.pairs:
    if count > 0 and isFoodItem(key):
      return false
  true

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
  let teamId = getTeamId(agent)
  let seesEnemyStructure = fighterSeesEnemyStructure(env, agent)
  for kind in FighterTrainKinds:
    if kind in FighterSiegeTrainKinds and not seesEnemyStructure:
      continue
    if controller.getBuildingCount(env, teamId, kind) == 0:
      continue
    if not env.canSpendStockpile(teamId, buildingTrainCosts(kind)):
      continue
    return true
  false

proc shouldTerminateFighterTrain(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  ## Terminate when no longer a villager (was trained) or can't afford any training
  if agent.unitClass != UnitVillager:
    return true
  let teamId = getTeamId(agent)
  let seesEnemyStructure = fighterSeesEnemyStructure(env, agent)
  for kind in FighterTrainKinds:
    if kind in FighterSiegeTrainKinds and not seesEnemyStructure:
      continue
    if controller.getBuildingCount(env, teamId, kind) == 0:
      continue
    if env.canSpendStockpile(teamId, buildingTrainCosts(kind)):
      return false  # Can still train, don't terminate
  true  # No training options available

proc optFighterTrain(controller: Controller, env: Environment, agent: Thing,
                     agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
  let seesEnemyStructure = fighterSeesEnemyStructure(env, agent)
  for kind in FighterTrainKinds:
    if kind in FighterSiegeTrainKinds and not seesEnemyStructure:
      continue
    if controller.getBuildingCount(env, teamId, kind) == 0:
      continue
    if not env.canSpendStockpile(teamId, buildingTrainCosts(kind)):
      continue
    let building = env.findNearestFriendlyThingSpiral(state, teamId, kind)
    if isNil(building) or building.cooldown != 0:
      continue
    return actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)
  0'u8

proc canStartFighterBecomeSiege(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  ## True siege conversion: combat units (ManAtArms, Knight) can convert to siege
  ## when they see enemy structures and a SiegeWorkshop is available.
  if agent.unitClass notin {UnitManAtArms, UnitKnight}:
    return false
  if not fighterSeesEnemyStructure(env, agent):
    return false
  let teamId = getTeamId(agent)
  if controller.getBuildingCount(env, teamId, SiegeWorkshop) == 0:
    return false
  if not env.canSpendStockpile(teamId, buildingTrainCosts(SiegeWorkshop)):
    return false
  true

proc shouldTerminateFighterBecomeSiege(controller: Controller, env: Environment, agent: Thing,
                                       agentId: int, state: var AgentState): bool =
  ## Terminate when unit class changes (became siege) or conditions no longer met
  if agent.unitClass notin {UnitManAtArms, UnitKnight}:
    return true
  if not fighterSeesEnemyStructure(env, agent):
    return true
  let teamId = getTeamId(agent)
  if controller.getBuildingCount(env, teamId, SiegeWorkshop) == 0:
    return true
  if not env.canSpendStockpile(teamId, buildingTrainCosts(SiegeWorkshop)):
    return true
  false

proc optFighterBecomeSiege(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  ## Move to SiegeWorkshop and interact to convert to battering ram
  let teamId = getTeamId(agent)
  let building = env.findNearestFriendlyThingSpiral(state, teamId, SiegeWorkshop)
  if isNil(building) or building.cooldown != 0:
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, building.pos, 3'u8)

proc canStartFighterMaintainGear(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  if agent.inventoryArmor < ArmorPoints:
    return true
  agent.unitClass == UnitManAtArms and agent.inventorySpear == 0

proc shouldTerminateFighterMaintainGear(controller: Controller, env: Environment, agent: Thing,
                                        agentId: int, state: var AgentState): bool =
  # Terminate when fully geared (armor at max, and spear if ManAtArms)
  if agent.inventoryArmor < ArmorPoints:
    return false
  if agent.unitClass == UnitManAtArms and agent.inventorySpear == 0:
    return false
  true

proc optFighterMaintainGear(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent)
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

const
  KiteTriggerDistance = 3  # Distance at which kiting triggers (within archer range)
  AntiSiegeDetectionRadius = 12  # Distance to detect enemy siege units
  SiegeNearStructureRadius = 5  # Siege units this close to friendly structures get priority

proc findNearestMeleeEnemy(env: Environment, agent: Thing): Thing =
  ## Find the nearest enemy agent that is a melee unit (not archer, mangonel, or monk)
  let teamId = getTeamId(agent)
  var bestEnemy: Thing = nil
  var bestDist = int.high
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) == teamId:
      continue
    # Melee units are: Villager, ManAtArms, Scout, Knight, BatteringRam, Goblin
    # Non-melee: Archer, Mangonel, Monk, Boat
    if other.unitClass in {UnitArcher, UnitMangonel, UnitMonk, UnitBoat}:
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist < bestDist:
      bestDist = dist
      bestEnemy = other
  bestEnemy

proc isSiegeThreateningStructure(env: Environment, siege: Thing, teamId: int): bool =
  ## Check if enemy siege unit is close to any friendly structures
  for thing in env.things:
    if thing.isNil or thing.teamId != teamId:
      continue
    if not isBuildingKind(thing.kind):
      continue
    if thing.kind notin AttackableStructures:
      continue
    if int(chebyshevDist(siege.pos, thing.pos)) <= SiegeNearStructureRadius:
      return true
  false

proc findNearestSiegeEnemy(env: Environment, agent: Thing, prioritizeThreatening: bool = true): Thing =
  ## Find the nearest enemy siege unit (BatteringRam or Mangonel)
  ## If prioritizeThreatening is true, prefer siege units near friendly structures
  let teamId = getTeamId(agent)
  var bestEnemy: Thing = nil
  var bestDist = int.high
  var bestThreatening = false

  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if getTeamId(other) == teamId:
      continue
    # Only target siege units
    if other.unitClass notin {UnitBatteringRam, UnitMangonel}:
      continue
    let dist = int(chebyshevDist(agent.pos, other.pos))
    if dist > AntiSiegeDetectionRadius:
      continue

    let threatening = prioritizeThreatening and isSiegeThreateningStructure(env, other, teamId)

    # Prefer threatening siege, then closest
    if threatening and not bestThreatening:
      bestThreatening = true
      bestDist = dist
      bestEnemy = other
    elif threatening == bestThreatening and dist < bestDist:
      bestDist = dist
      bestEnemy = other
  bestEnemy

proc canStartFighterAntiSiege(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  ## Anti-siege triggers when there's an enemy siege unit nearby
  ## Requires stance that allows chasing
  if not stanceAllowsChase(agent):
    return false
  not isNil(findNearestSiegeEnemy(env, agent))

proc shouldTerminateFighterAntiSiege(controller: Controller, env: Environment, agent: Thing,
                                     agentId: int, state: var AgentState): bool =
  ## Terminate when no more siege units nearby
  isNil(findNearestSiegeEnemy(env, agent))

proc optFighterAntiSiege(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  ## Move toward and attack enemy siege units
  let siege = findNearestSiegeEnemy(env, agent)
  if isNil(siege):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, siege.pos, 2'u8)

proc canStartFighterKite(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool =
  ## Kiting triggers for archers when a melee enemy is within trigger distance
  ## StandGround stance disables kiting (no movement allowed)
  if agent.unitClass != UnitArcher:
    return false
  if not stanceAllowsMovementToAttack(agent):
    return false
  let meleeEnemy = findNearestMeleeEnemy(env, agent)
  if isNil(meleeEnemy):
    return false
  let dist = int(chebyshevDist(agent.pos, meleeEnemy.pos))
  dist <= KiteTriggerDistance

proc shouldTerminateFighterKite(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  ## Terminate when no melee enemy within trigger distance
  if agent.unitClass != UnitArcher:
    return true
  let meleeEnemy = findNearestMeleeEnemy(env, agent)
  if isNil(meleeEnemy):
    return true
  let dist = int(chebyshevDist(agent.pos, meleeEnemy.pos))
  dist > KiteTriggerDistance

proc optFighterKite(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): uint8 =
  ## Move away from the nearest melee enemy while staying within attack range
  let meleeEnemy = findNearestMeleeEnemy(env, agent)
  if isNil(meleeEnemy):
    return 0'u8

  let dist = int(chebyshevDist(agent.pos, meleeEnemy.pos))
  # If already at safe distance, no need to kite
  if dist > KiteTriggerDistance:
    return 0'u8

  # Calculate direction away from enemy
  let dx = agent.pos.x - meleeEnemy.pos.x
  let dy = agent.pos.y - meleeEnemy.pos.y
  let awayDir = ivec2(signi(dx), signi(dy))

  # Try to move in the direction away from enemy
  # Check multiple directions, preferring directly away, then diagonals
  var candidates: seq[IVec2] = @[]
  # Primary direction: directly away
  if awayDir.x != 0 or awayDir.y != 0:
    candidates.add(awayDir)
  # Secondary: perpendicular directions (allows strafing)
  if awayDir.x != 0 and awayDir.y != 0:
    # Diagonal away - try the two perpendicular diagonals
    candidates.add(ivec2(awayDir.x, 0))
    candidates.add(ivec2(0, awayDir.y))
  elif awayDir.x != 0:
    # Moving horizontally - can strafe vertically
    candidates.add(ivec2(awayDir.x, 1))
    candidates.add(ivec2(awayDir.x, -1))
  elif awayDir.y != 0:
    # Moving vertically - can strafe horizontally
    candidates.add(ivec2(1, awayDir.y))
    candidates.add(ivec2(-1, awayDir.y))

  # Try each candidate direction
  for dir in candidates:
    let targetPos = agent.pos + dir
    if not isValidPos(targetPos):
      continue
    if not canEnterForMove(env, agent, agent.pos, targetPos):
      continue
    # Check that we maintain attack range (stay within ArcherBaseRange of any enemy)
    # For now, just move away - the attack opportunity check will handle attacking
    let dirIdx = vecToOrientation(dir)
    return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dirIdx.uint8))

  # If can't move directly away, try any direction that increases distance
  for dirIdx in 0 .. 7:
    let dir = Directions8[dirIdx]
    let targetPos = agent.pos + dir
    if not isValidPos(targetPos):
      continue
    if not canEnterForMove(env, agent, agent.pos, targetPos):
      continue
    let newDist = int(chebyshevDist(targetPos, meleeEnemy.pos))
    if newDist > dist:
      return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dirIdx.uint8))

  # Can't kite, return 0 to let other options handle it
  0'u8

proc canStartFighterHuntPredators(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  ## Hunting predators requires chasing them - check stance
  if not stanceAllowsChase(agent):
    return false
  agent.hp * 2 >= agent.maxHp and not isNil(findNearestPredator(env, agent.pos))

proc shouldTerminateFighterHuntPredators(controller: Controller, env: Environment, agent: Thing,
                                         agentId: int, state: var AgentState): bool =
  # Terminate when HP drops below threshold or no predator nearby
  agent.hp * 2 < agent.maxHp or isNil(findNearestPredator(env, agent.pos))

proc optFighterHuntPredators(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): uint8 =
  let target = findNearestPredator(env, agent.pos)
  if isNil(target):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)

proc canStartFighterClearGoblins(controller: Controller, env: Environment, agent: Thing,
                                 agentId: int, state: var AgentState): bool =
  ## Clearing goblin structures requires chasing - check stance
  if not stanceAllowsChase(agent):
    return false
  agent.hp * 2 >= agent.maxHp and not isNil(findNearestGoblinStructure(env, agent.pos))

proc shouldTerminateFighterClearGoblins(controller: Controller, env: Environment, agent: Thing,
                                        agentId: int, state: var AgentState): bool =
  # Terminate when HP drops below threshold or no goblin structure nearby
  agent.hp * 2 < agent.maxHp or isNil(findNearestGoblinStructure(env, agent.pos))

proc optFighterClearGoblins(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  let target = findNearestGoblinStructure(env, agent.pos)
  if isNil(target):
    return 0'u8
  actOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)

# Escort behavior: respond to protection requests from coordination system
proc canStartFighterEscort(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  ## Check if there's a nearby protection request to respond to
  if not stanceAllowsChase(agent):
    return false
  # Only combat units can escort
  if agent.unitClass notin {UnitManAtArms, UnitKnight, UnitScout, UnitArcher}:
    return false
  let (should, _) = fighterShouldEscort(env, agent)
  should

proc shouldTerminateFighterEscort(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  ## Terminate when no more protection requests or target reached
  let (should, _) = fighterShouldEscort(env, agent)
  not should

proc optFighterEscort(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  ## Move toward the unit requesting protection and engage any enemies along the way
  let (should, targetPos) = fighterShouldEscort(env, agent)
  if not should:
    return 0'u8

  # First check for attack opportunity - engage enemies
  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  # Check for nearby enemies and engage them
  let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
  if not isNil(enemy):
    return actOrMove(controller, env, agent, agentId, state, enemy.pos, 2'u8)

  # Move toward the protected unit
  let dist = int(chebyshevDist(agent.pos, targetPos))
  if dist <= EscortRadius:
    # Already close enough - stay nearby but allow other behaviors
    return 0'u8
  controller.moveTo(env, agent, agentId, state, targetPos)

proc canStartFighterAggressive(controller: Controller, env: Environment, agent: Thing,
                               agentId: int, state: var AgentState): bool =
  ## Aggressive hunting requires chasing - check stance
  if not stanceAllowsChase(agent):
    return false
  if agent.hp * 2 >= agent.maxHp:
    return true
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if not sameTeam(agent, other):
      continue
    if chebyshevDist(agent.pos, other.pos) <= 4'i32:
      return true
  false

proc shouldTerminateFighterAggressive(controller: Controller, env: Environment, agent: Thing,
                                      agentId: int, state: var AgentState): bool =
  # Terminate when HP drops low and no allies nearby for support
  if agent.hp * 2 >= agent.maxHp:
    return false
  for other in env.agents:
    if other.agentId == agent.agentId:
      continue
    if not isAgentAlive(env, other):
      continue
    if not sameTeam(agent, other):
      continue
    if chebyshevDist(agent.pos, other.pos) <= 4'i32:
      return false
  true

proc optFighterAggressive(controller: Controller, env: Environment, agent: Thing,
                          agentId: int, state: var AgentState): uint8 =
  for kind in [Tumor, Spawner]:
    let target = env.findNearestThingSpiral(state, kind)
    if not isNil(target):
      return actOrMove(controller, env, agent, agentId, state, target.pos, 2'u8)
  let (didHunt, actHunt) = controller.ensureHuntFood(env, agent, agentId, state)
  if didHunt: return actHunt
  0'u8

# Attack-Move: Move to destination, attacking any enemies encountered along the way
# Like AoE2's attack-move: path to destination, engage enemies in range, resume after combat

const
  AttackMoveDetectionRadius = 8  # Distance to detect enemies while attack-moving

proc canStartFighterAttackMove*(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState): bool =
  ## Attack-move is active when the agent has a valid attack-move destination set.
  ## Requires stance that allows movement to attack.
  if not stanceAllowsMovementToAttack(agent):
    return false
  state.attackMoveTarget.x >= 0

proc shouldTerminateFighterAttackMove*(controller: Controller, env: Environment, agent: Thing,
                                       agentId: int, state: var AgentState): bool =
  ## Terminate when destination is reached or attack-move is cancelled.
  if state.attackMoveTarget.x < 0:
    return true
  # Reached destination (within 1 tile)
  chebyshevDist(agent.pos, state.attackMoveTarget) <= 1'i32

proc optFighterAttackMove*(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  ## Attack-move behavior: move toward destination, but engage enemies along the way.
  ## After defeating an enemy, resume path to destination.
  if state.attackMoveTarget.x < 0:
    return 0'u8

  # Check if we've reached the destination
  if chebyshevDist(agent.pos, state.attackMoveTarget) <= 1'i32:
    # Clear the attack-move target - we've arrived
    state.attackMoveTarget = ivec2(-1, -1)
    return 0'u8

  # Look for enemies within detection radius
  let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
  if not isNil(enemy):
    let enemyDist = int(chebyshevDist(agent.pos, enemy.pos))
    if enemyDist <= AttackMoveDetectionRadius:
      # Enemy found - engage!
      return actOrMove(controller, env, agent, agentId, state, enemy.pos, 2'u8)

  # No enemy nearby - continue moving toward destination
  controller.moveTo(env, agent, agentId, state, state.attackMoveTarget)

proc setAttackMoveTarget*(controller: Controller, agentId: int, target: IVec2) =
  ## Set an attack-move target for a specific agent.
  ## The agent will move toward the target while engaging enemies along the way.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].attackMoveTarget = target

proc clearAttackMoveTarget*(controller: Controller, agentId: int) =
  ## Clear the attack-move target for a specific agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].attackMoveTarget = ivec2(-1, -1)

proc getAttackMoveTarget*(controller: Controller, agentId: int): IVec2 =
  ## Get the current attack-move target for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].attackMoveTarget
  ivec2(-1, -1)

# Battering Ram AI: Simple forward movement with attack-on-block behavior
# 1. Move forward in current orientation
# 2. If blocked, attack blocking target
# 3. If target destroyed, resume moving forward

proc canStartBatteringRamAdvance(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  agent.unitClass == UnitBatteringRam

proc shouldTerminateBatteringRamAdvance(controller: Controller, env: Environment, agent: Thing,
                                         agentId: int, state: var AgentState): bool =
  # Never terminates - battering ram always uses this behavior
  agent.unitClass != UnitBatteringRam

proc optBatteringRamAdvance(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): uint8 =
  ## Simple battering ram AI: move forward, attack blockers
  let delta = OrientationDeltas[agent.orientation.int]
  let forwardPos = agent.pos + delta

  # Check if there's something blocking forward movement
  let blocking = env.getThing(forwardPos)
  if not isNil(blocking):
    # Attack the blocking thing (verb 2 = attack)
    return actOrMove(controller, env, agent, agentId, state, forwardPos, 2'u8)

  # Check for blocking agent
  let blockingAgent = env.grid[forwardPos.x][forwardPos.y]
  if not isNil(blockingAgent) and blockingAgent.agentId != agent.agentId:
    return actOrMove(controller, env, agent, agentId, state, forwardPos, 2'u8)

  # Check terrain passability
  if not canEnterForMove(env, agent, agent.pos, forwardPos):
    # Something blocks us (wall, terrain) - try to attack forward
    return actOrMove(controller, env, agent, agentId, state, forwardPos, 2'u8)

  # Path is clear - move forward (verb 1 = move)
  let dirIdx = agent.orientation.int
  return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dirIdx.uint8))

proc optFighterFallbackSearch(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): uint8 =
  controller.moveNextSearch(env, agent, agentId, state)

# Patrol behavior - walk between waypoints and attack enemies encountered
const PatrolArrivalThreshold = 2  # Distance at which we consider waypoint "reached"

proc canStartFighterPatrol(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool =
  ## Patrol activates when patrol mode is enabled for this agent
  state.patrolActive and state.patrolPoint1.x >= 0 and state.patrolPoint2.x >= 0

proc shouldTerminateFighterPatrol(controller: Controller, env: Environment, agent: Thing,
                                  agentId: int, state: var AgentState): bool =
  ## Patrol terminates when patrol mode is disabled
  not state.patrolActive

proc optFighterPatrol(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState): uint8 =
  ## Patrol between two waypoints, attacking any enemies encountered.
  ## Uses AoE2-style patrol: walk to waypoint, attack nearby enemies, continue patrol.

  # First check for attack opportunity - attack takes priority during patrol
  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  # Check for nearby enemies and chase them if stance allows
  if stanceAllowsChase(agent):
    let enemy = fighterFindNearbyEnemy(controller, env, agent, state)
    if not isNil(enemy):
      # Move toward enemy to engage
      return controller.moveTo(env, agent, agentId, state, enemy.pos)

  # Determine current patrol target
  let target = if state.patrolToSecondPoint: state.patrolPoint2 else: state.patrolPoint1

  # Check if we've reached the current waypoint
  let distToTarget = int(chebyshevDist(agent.pos, target))
  if distToTarget <= PatrolArrivalThreshold:
    # Switch direction
    state.patrolToSecondPoint = not state.patrolToSecondPoint
    # Get the new target after switching
    let newTarget = if state.patrolToSecondPoint: state.patrolPoint2 else: state.patrolPoint1
    return controller.moveTo(env, agent, agentId, state, newTarget)

  # Move toward current waypoint
  controller.moveTo(env, agent, agentId, state, target)

let FighterOptions* = [
  OptionDef(
    name: "BatteringRamAdvance",
    canStart: canStartBatteringRamAdvance,
    shouldTerminate: shouldTerminateBatteringRamAdvance,
    act: optBatteringRamAdvance,
    interruptible: false  # Battering ram AI is not interruptible - it just advances and attacks
  ),
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
  EmergencyHealOption,
  OptionDef(
    name: "FighterSeekHealer",
    canStart: canStartFighterSeekHealer,
    shouldTerminate: shouldTerminateFighterSeekHealer,
    act: optFighterSeekHealer,
    interruptible: true
  ),
  OptionDef(
    name: "FighterMonk",
    canStart: canStartFighterMonk,
    shouldTerminate: shouldTerminateFighterMonk,
    act: optFighterMonk,
    interruptible: true
  ),
  OptionDef(
    name: "FighterPatrol",
    canStart: canStartFighterPatrol,
    shouldTerminate: shouldTerminateFighterPatrol,
    act: optFighterPatrol,
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
    shouldTerminate: shouldTerminateFighterLanterns,
    act: optFighterLanterns,
    interruptible: true
  ),
  OptionDef(
    name: "FighterDropoffFood",
    canStart: canStartFighterDropoffFood,
    shouldTerminate: shouldTerminateFighterDropoffFood,
    act: optFighterDropoffFood,
    interruptible: true
  ),
  OptionDef(
    name: "FighterTrain",
    canStart: canStartFighterTrain,
    shouldTerminate: shouldTerminateFighterTrain,
    act: optFighterTrain,
    interruptible: true
  ),
  OptionDef(
    name: "FighterBecomeSiege",
    canStart: canStartFighterBecomeSiege,
    shouldTerminate: shouldTerminateFighterBecomeSiege,
    act: optFighterBecomeSiege,
    interruptible: true
  ),
  OptionDef(
    name: "FighterMaintainGear",
    canStart: canStartFighterMaintainGear,
    shouldTerminate: shouldTerminateFighterMaintainGear,
    act: optFighterMaintainGear,
    interruptible: true
  ),
  OptionDef(
    name: "FighterKite",
    canStart: canStartFighterKite,
    shouldTerminate: shouldTerminateFighterKite,
    act: optFighterKite,
    interruptible: true
  ),
  OptionDef(
    name: "FighterAntiSiege",
    canStart: canStartFighterAntiSiege,
    shouldTerminate: shouldTerminateFighterAntiSiege,
    act: optFighterAntiSiege,
    interruptible: true
  ),
  OptionDef(
    name: "FighterEscort",
    canStart: canStartFighterEscort,
    shouldTerminate: shouldTerminateFighterEscort,
    act: optFighterEscort,
    interruptible: true
  ),
  OptionDef(
    name: "FighterHuntPredators",
    canStart: canStartFighterHuntPredators,
    shouldTerminate: shouldTerminateFighterHuntPredators,
    act: optFighterHuntPredators,
    interruptible: true
  ),
  OptionDef(
    name: "FighterClearGoblins",
    canStart: canStartFighterClearGoblins,
    shouldTerminate: shouldTerminateFighterClearGoblins,
    act: optFighterClearGoblins,
    interruptible: true
  ),
  SmeltGoldOption,
  CraftBreadOption,
  StoreValuablesOption,
  OptionDef(
    name: "FighterAggressive",
    canStart: canStartFighterAggressive,
    shouldTerminate: shouldTerminateFighterAggressive,
    act: optFighterAggressive,
    interruptible: true
  ),
  OptionDef(
    name: "FighterAttackMove",
    canStart: canStartFighterAttackMove,
    shouldTerminate: shouldTerminateFighterAttackMove,
    act: optFighterAttackMove,
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
