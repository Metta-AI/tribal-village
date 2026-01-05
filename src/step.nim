# This file is included by src/environment.nim
proc step*(env: Environment, actions: ptr array[MapAgents, uint8]) =
  ## Step the environment
  # Decay short-lived action tints
  if env.actionTintPositions.len > 0:
    var kept: seq[IVec2] = @[]
    for pos in env.actionTintPositions:
      let x = pos.x
      let y = pos.y
      if x < 0 or x >= MapWidth or y < 0 or y >= MapHeight:
        continue
      let c = env.actionTintCountdown[x][y]
      if c > 0:
        let next = c - 1
        env.actionTintCountdown[x][y] = next
        if next == 0:
          env.actionTintFlags[x][y] = false
          env.updateObservations(TintLayer, pos, 0)
        kept.add(pos)
      else:
        env.actionTintFlags[x][y] = false
        env.updateObservations(TintLayer, pos, 0)
    env.actionTintPositions = kept

  # Decay shields
  for i in 0 ..< MapAgents:
    if env.shieldCountdown[i] > 0:
      env.shieldCountdown[i] = env.shieldCountdown[i] - 1

  # Remove any agents that already hit zero HP so they can't act this step
  env.enforceZeroHpDeaths()

  inc env.currentStep
  # Single RNG for entire step - more efficient than multiple initRand calls
  var stepRng = initRand(env.currentStep)

  for id, actionValue in actions[]:
    let agent = env.agents[id]
    if agent.frozen > 0:
      continue

    let decoded = decodeAction(actionValue)
    let verb = decoded.verb.int
    let argument = decoded.argument.int

    if verb < 0 or verb >= ActionVerbCount:
      inc env.stats[id].actionInvalid
      continue
    if argument < 0 or argument >= ActionArgumentCount:
      inc env.stats[id].actionInvalid
      continue

    case verb:
    of 0: env.noopAction(id, agent)
    of 1: env.moveAction(id, agent, argument)
    of 2: env.attackAction(id, agent, argument)
    of 3: env.useAction(id, agent, argument)  # Use terrain/buildings
    of 4: env.swapAction(id, agent, argument)
    of 5: env.putAction(id, agent, argument)  # Give to teammate
    of 6: env.plantAction(id, agent, argument)  # Plant lantern
    of 7: env.plantResourceAction(id, agent, argument)  # Plant wheat/tree on fertile tile
    of 8: env.buildFromChoices(id, agent, argument, BuildChoices)
    else: inc env.stats[id].actionInvalid

  # Combined single-pass object updates and tumor collection
  var newTumorsToSpawn: seq[Thing] = @[]
  var tumorsToProcess: seq[Thing] = @[]

  var cowHerds: Table[int, tuple[count: int, sumX: int, sumY: int]] = initTable[int, tuple[count: int, sumX: int, sumY: int]]()
  var cowDrift: Table[int, IVec2] = initTable[int, IVec2]()

  for thing in env.things:
    if thing.kind == Cow:
      let herd = thing.herdId
      let acc = cowHerds.getOrDefault(herd, (count: 0, sumX: 0, sumY: 0))
      cowHerds[herd] = (count: acc.count + 1, sumX: acc.sumX + thing.pos.x.int, sumY: acc.sumY + thing.pos.y.int)

  for herdId in cowHerds.keys:
    if randFloat(stepRng) < 0.35:
      let dirIdx = randIntInclusive(stepRng, 0, 3)
      let drift = case dirIdx
        of 0: ivec2(-1, 0)
        of 1: ivec2(1, 0)
        of 2: ivec2(0, -1)
        else: ivec2(0, 1)
      cowDrift[herdId] = drift
    else:
      cowDrift[herdId] = ivec2(0, 0)

  for thing in env.things:
    if thing.kind == Altar:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      # Combine altar heart reward calculation here
      if env.currentStep >= env.config.maxSteps:  # Only at episode end
        let altarHearts = thing.hearts.float32
        for agent in env.agents:
          if agent.homeAltar == thing.pos:
            agent.reward += altarHearts / MapAgentsPerHouseFloat
    elif thing.kind == Magma:
      env.tickCooldown(thing)
    elif thing.kind in {Armory, ClayOven, WeavingLoom,
                        Barracks, ArcheryRange, Stable, SiegeWorkshop, Blacksmith, Market, Bank,
                        Dock, Monastery, University, Castle, TownCenter, House}:
      # All production buildings have simple cooldown
      env.tickCooldown(thing)
    elif thing.kind == Mill:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      else:
        for dx in -2 .. 2:
          for dy in -2 .. 2:
            if dx == 0 and dy == 0:
              continue
            if max(abs(dx), abs(dy)) > 2:
              continue
            let pos = thing.pos + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if not env.isEmpty(pos) or env.hasDoor(pos) or
               isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
              continue
            let terrain = env.terrain[pos.x][pos.y]
            if terrain in {Empty, Grass, Sand, Snow, Dune, Stalagmite, Road}:
              env.terrain[pos.x][pos.y] = Fertile
              env.resetTileColor(pos)
        thing.cooldown = 10
    elif thing.kind == Spawner:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      else:
        # Spawner is ready to spawn a Tumor
        # Fast grid-based nearby Tumor count (5-tile radius)
        var nearbyTumorCount = 0
        for dx in -5..5:
          for dy in -5..5:
            let checkPos = thing.pos + ivec2(dx, dy)
            if isValidPos(checkPos):
              let other = env.getThing(checkPos)
              if not isNil(other) and other.kind == Tumor and not other.hasClaimedTerritory:
                inc nearbyTumorCount

        # Spawn a new Tumor with reasonable limits to prevent unbounded growth
        let maxTumorsPerSpawner = 3  # Keep only a few active tumors near the spawner
        if nearbyTumorCount < maxTumorsPerSpawner:
          # Find first empty position (no allocation)
          let spawnPos = env.findFirstEmptyPositionAround(thing.pos, 2)
          if spawnPos.x >= 0:

            let newTumor = createTumor(spawnPos, thing.pos, stepRng)
            # Don't add immediately - collect for later
            newTumorsToSpawn.add(newTumor)

            # Reset spawner cooldown based on spawn rate
            # Convert spawn rate (0.0-1.0) to cooldown steps (higher rate = lower cooldown)
            let cooldown = if env.config.tumorSpawnRate > 0.0:
              max(1, int(20.0 / env.config.tumorSpawnRate))  # Base 20 steps, scaled by rate
            else:
              1000  # Very long cooldown if spawn disabled
            thing.cooldown = cooldown
    elif thing.kind == Cow:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      let herdAcc = cowHerds.getOrDefault(thing.herdId, (count: 1, sumX: thing.pos.x.int, sumY: thing.pos.y.int))
      let center = ivec2((herdAcc.sumX div herdAcc.count).int32, (herdAcc.sumY div herdAcc.count).int32)
      let drift = cowDrift.getOrDefault(thing.herdId, ivec2(0, 0))
      let herdTarget = if drift.x != 0 or drift.y != 0:
        center + drift * 2
      else:
        center
      let dist = max(abs(herdTarget.x - thing.pos.x), abs(herdTarget.y - thing.pos.y))

      proc stepToward(fromPos, toPos: IVec2): IVec2 =
        let dx = toPos.x - fromPos.x
        let dy = toPos.y - fromPos.y
        if dx == 0 and dy == 0:
          return ivec2(0, 0)
        if abs(dx) >= abs(dy):
          return ivec2((if dx > 0: 1 else: -1), 0)
        return ivec2(0, (if dy > 0: 1 else: -1))

      var desired = ivec2(0, 0)
      if dist > 1:
        desired = stepToward(thing.pos, herdTarget)
      elif (drift.x != 0 or drift.y != 0) and randFloat(stepRng) < 0.6:
        desired = stepToward(thing.pos, herdTarget)
      elif randFloat(stepRng) < 0.08:
        let dirIdx = randIntInclusive(stepRng, 0, 3)
        desired = case dirIdx
          of 0: ivec2(-1, 0)
          of 1: ivec2(1, 0)
          of 2: ivec2(0, -1)
          else: ivec2(0, 1)

      if desired != ivec2(0, 0):
        let nextPos = thing.pos + desired
        if isValidPos(nextPos) and not env.hasDoor(nextPos) and not isBlockedTerrain(env.terrain[nextPos.x][nextPos.y]) and env.isEmpty(nextPos):
          env.grid[thing.pos.x][thing.pos.y] = nil
          thing.pos = nextPos
          env.grid[nextPos.x][nextPos.y] = thing
          if desired.x < 0:
            thing.orientation = Orientation.W
          elif desired.x > 0:
            thing.orientation = Orientation.E
    elif thing.kind == Agent:
      if thing.frozen > 0:
        thing.frozen -= 1
    elif thing.kind == Tumor:
      # Only collect mobile clippies for processing (planted ones are static)
      if not thing.hasClaimedTerritory:
        tumorsToProcess.add(thing)

  # ============== TUMOR PROCESSING ==============
  var newTumorBranches: seq[Thing] = @[]

  for tumor in tumorsToProcess:
    tumor.turnsAlive += 1
    if tumor.turnsAlive < TumorBranchMinAge:
      continue

    if randFloat(stepRng) >= TumorBranchChance:
      continue

    let branchPos = findTumorBranchTarget(tumor, env, stepRng)
    if branchPos.x < 0:
      continue

    let newTumor = createTumor(branchPos, tumor.homeSpawner, stepRng)

    # Face both clippies toward the new branch direction for clarity
    let dx = branchPos.x - tumor.pos.x
    let dy = branchPos.y - tumor.pos.y
    var branchOrientation: Orientation
    if abs(dx) >= abs(dy):
      branchOrientation = (if dx >= 0: Orientation.E else: Orientation.W)
    else:
      branchOrientation = (if dy >= 0: Orientation.S else: Orientation.N)

    newTumor.orientation = branchOrientation
    tumor.orientation = branchOrientation

    # Queue the new tumor for insertion and mark parent as inert
    newTumorBranches.add(newTumor)
    tumor.hasClaimedTerritory = true
    tumor.turnsAlive = 0

  # Add newly spawned tumors from spawners and branching this step
  for newTumor in newTumorsToSpawn:
    env.add(newTumor)
  for newTumor in newTumorBranches:
    env.add(newTumor)

  # Resolve agent contact: agents adjacent to tumors risk lethal creep
  var tumorsToRemove: seq[Thing] = @[]

  let thingCount = env.things.len
  for i in 0 ..< thingCount:
    let tumor = env.things[i]
    if tumor.kind != Tumor:
      continue
    let adjacentPositions = [
      tumor.pos + ivec2(0, -1),
      tumor.pos + ivec2(1, 0),
      tumor.pos + ivec2(0, 1),
      tumor.pos + ivec2(-1, 0)
    ]

    for adjPos in adjacentPositions:
      if not isValidPos(adjPos):
        continue

      let occupant = env.getThing(adjPos)
      if isNil(occupant) or occupant.kind != Agent:
        continue

      # Shield check: block death if shield active and tumor is in shield band
      var blocked = false
      if env.shieldCountdown[occupant.agentId] > 0:
        let ori = occupant.orientation
        let d = getOrientationDelta(ori)
        let perp = if d.x != 0: ivec2(0, 1) else: ivec2(1, 0)
        let forward = occupant.pos + ivec2(d.x, d.y)
        for offset in -1 .. 1:
          let shieldPos = forward + ivec2(perp.x * offset, perp.y * offset)
          if shieldPos == tumor.pos:
            blocked = true
            break
      if blocked:
        continue

      if randFloat(stepRng) < TumorAdjacencyDeathChance:
        let killed = env.applyAgentDamage(occupant, 1)
        if killed and tumor notin tumorsToRemove:
          tumorsToRemove.add(tumor)
          env.grid[tumor.pos.x][tumor.pos.y] = nil
          env.updateObservations(AgentLayer, tumor.pos, 0)
          env.updateObservations(AgentOrientationLayer, tumor.pos, 0)
        if killed:
          break

  # Remove tumors cleared by lethal contact this step
  if tumorsToRemove.len > 0:
    for i in countdown(env.things.len - 1, 0):
      if env.things[i] in tumorsToRemove:
        env.things.del(i)

  # Catch any agents that were reduced to zero HP during the step
  env.enforceZeroHpDeaths()

  # Precompute team population and pop caps (Town Centers + Houses)
  var teamPopCounts: array[MapRoomObjectsHouses, int]
  var teamPopCaps: array[MapRoomObjectsHouses, int]
  for agent in env.agents:
    if agent.isNil:
      continue
    if env.terminated[agent.agentId] != 0.0:
      continue
    let teamId = getTeamId(agent.agentId)
    if teamId >= 0 and teamId < MapRoomObjectsHouses:
      inc teamPopCounts[teamId]
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId < 0 or thing.teamId >= MapRoomObjectsHouses:
      continue
    case thing.kind
    of TownCenter:
      teamPopCaps[thing.teamId] += TownCenterPopCap
    of House:
      teamPopCaps[thing.teamId] += HousePopCap
    else:
      discard

  # Respawn dead agents at their altars
  for agentId in 0 ..< MapAgents:
    let agent = env.agents[agentId]

    # Check if agent is dead and has a home altar
    if env.terminated[agentId] == 1.0 and agent.homeAltar.x >= 0:
      let teamId = getTeamId(agent.agentId)
      if teamId < 0 or teamId >= MapRoomObjectsHouses:
        continue
      if teamPopCounts[teamId] >= teamPopCaps[teamId]:
        continue
      # Find the altar
      var altarThing: Thing = nil
      for thing in env.things:
        if thing.kind == ThingKind.Altar and thing.pos == agent.homeAltar:
          altarThing = thing
          break

      # Respawn if altar exists and has hearts above the auto-spawn threshold
      if not isNil(altarThing) and altarThing.hearts > MapObjectAltarAutoSpawnThreshold:
        # Deduct a heart from the altar
        altarThing.hearts = altarThing.hearts - MapObjectAltarRespawnCost
        env.updateObservations(altarHeartsLayer, altarThing.pos, altarThing.hearts)

        # Find first empty position around altar (no allocation)
        let respawnPos = env.findFirstEmptyPositionAround(altarThing.pos, 2)
        if respawnPos.x >= 0:
          # Respawn the agent
          agent.pos = respawnPos
          agent.inventory = emptyInventory()
          agent.frozen = 0
          applyUnitClass(agent, UnitVillager)
          env.terminated[agentId] = 0.0

          # Update grid
          env.grid[agent.pos.x][agent.pos.y] = agent
          inc teamPopCounts[teamId]

          # Update observations
          # REMOVED: expensive per-agent full grid rebuild
          env.updateObservations(AgentLayer, agent.pos, getTeamId(agent.agentId) + 1)
          env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
          for key in ObservedItemKeys:
            env.updateAgentInventoryObs(agent, key)

  # Apply per-step survival penalty to all living agents
  if env.config.survivalPenalty != 0.0:
    for agent in env.agents:
      if agent.frozen == 0:  # Only alive agents
        agent.reward += env.config.survivalPenalty

  # Update heatmap using batch tint modification system
  # This is much more efficient than updating during each entity move
  env.updateTintModifications()  # Collect all entity contributions
  env.applyTintModifications()   # Apply them to the main color array in one pass


  # Check if episode should end
  if env.currentStep >= env.config.maxSteps:
    # Team altar rewards already applied in main loop above
    # Mark all living agents as truncated (episode ended due to time limit)
    for i in 0..<MapAgents:
      if env.terminated[i] == 0.0:
        env.truncated[i] = 1.0
    env.shouldReset = true

  # Check if all agents are terminated/truncated
  var allDone = true
  for i in 0..<MapAgents:
    if env.terminated[i] == 0.0 and env.truncated[i] == 0.0:
      allDone = false
      break
  if allDone:
    # Team altar rewards already applied in main loop if needed
    env.shouldReset = true

proc reset*(env: Environment) =
  env.currentStep = 0
  env.shouldReset = false
  env.terminated.clear()
  env.truncated.clear()
  env.things.setLen(0)
  env.agents.setLen(0)
  env.stats.setLen(0)
  env.grid.clear()
  env.observations.clear()
  env.observationsInitialized = false
  # Clear the massive tintMods array to prevent accumulation
  env.tintMods.clear()
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  # Clear global colors that could accumulate
  agentVillageColors.setLen(0)
  teamColors.setLen(0)
  altarColors.clear()
  # Clear UI selection to prevent stale references
  selection = nil
  env.init()  # init() handles terrain, activeTiles, and tile colors
