# This file is included by src/environment.nim
when defined(stepTiming):
  import std/[os, monotimes]

  let stepTimingTargetStr = getEnv("TV_STEP_TIMING", "")
  let stepTimingWindowStr = getEnv("TV_STEP_TIMING_WINDOW", "0")
  let stepTimingTarget = block:
    if stepTimingTargetStr.len == 0:
      -1
    else:
      try:
        parseInt(stepTimingTargetStr)
      except ValueError:
        -1
  let stepTimingWindow = block:
    if stepTimingWindowStr.len == 0:
      0
    else:
      try:
        parseInt(stepTimingWindowStr)
      except ValueError:
        0

  proc stepTimingActive(env: Environment): bool =
    stepTimingTarget >= 0 and env.currentStep >= stepTimingTarget and
      env.currentStep <= stepTimingTarget + stepTimingWindow

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

let spawnerScanOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -5 .. 5:
    for dy in -5 .. 5:
      offsets.add(ivec2(dx, dy))
  offsets

proc step*(env: Environment, actions: ptr array[MapAgents, uint8]) =
  ## Step the environment
  when defined(stepTiming):
    let timing = stepTimingActive(env)
    var tStart: MonoTime
    var tNow: MonoTime
    var tTotalStart: MonoTime
    var tActionTintMs: float64
    var tShieldsMs: float64
    var tPreDeathsMs: float64
    var tActionsMs: float64
    var tThingsMs: float64
    var tTumorsMs: float64
    var tAdjacencyMs: float64
    var tPopRespawnMs: float64
    var tSurvivalMs: float64
    var tTintMs: float64
    var tEndMs: float64

    if timing:
      tStart = getMonoTime()
      tTotalStart = tStart

  # Decay short-lived action tints
  if env.actionTintPositions.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.actionTintPositions.len:
      let pos = env.actionTintPositions[readIdx]
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
        env.actionTintPositions[writeIdx] = pos
        inc writeIdx
      else:
        env.actionTintFlags[x][y] = false
        env.updateObservations(TintLayer, pos, 0)
    env.actionTintPositions.setLen(writeIdx)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tActionTintMs = msBetween(tStart, tNow)
      tStart = tNow

  # Decay shields
  for i in 0 ..< MapAgents:
    if env.shieldCountdown[i] > 0:
      env.shieldCountdown[i] = env.shieldCountdown[i] - 1

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tShieldsMs = msBetween(tStart, tNow)
      tStart = tNow

  # Remove any agents that already hit zero HP so they can't act this step
  env.enforceZeroHpDeaths()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tPreDeathsMs = msBetween(tStart, tNow)
      tStart = tNow

  inc env.currentStep
  # Single RNG for entire step - more efficient than multiple initRand calls
  var stepRng = initRand(env.currentStep)

  for id, actionValue in actions[]:
    let agent = env.agents[id]
    if not isAgentAlive(env, agent):
      continue

    let verb = actionValue.int div ActionArgumentCount
    let argument = actionValue.int mod ActionArgumentCount

    if verb < 0 or verb >= ActionVerbCount:
      inc env.stats[id].actionInvalid
      continue
    if argument < 0 or argument >= ActionArgumentCount:
      inc env.stats[id].actionInvalid
      continue

    case verb:
    of 0: inc env.stats[id].actionNoop
    of 1: env.moveAction(id, agent, argument)
    of 2: env.attackAction(id, agent, argument)
    of 3: env.useAction(id, agent, argument)  # Use terrain/buildings
    of 4: env.swapAction(id, agent, argument)
    of 5: env.putAction(id, agent, argument)  # Give to teammate
    of 6: env.plantAction(id, agent, argument)  # Plant lantern
    of 7: env.plantResourceAction(id, agent, argument)  # Plant wheat/tree on fertile tile
    of 8: env.buildFromChoices(id, agent, argument, BuildChoices)
    else: inc env.stats[id].actionInvalid

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tActionsMs = msBetween(tStart, tNow)
      tStart = tNow

  # Combined single-pass object updates and tumor collection
  const adjacentOffsets = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]
  var newTumorsToSpawn: seq[Thing] = @[]
  var tumorsToProcess: seq[Thing] = @[]

  if env.cowHerdCounts.len > 0:
    for i in 0 ..< env.cowHerdCounts.len:
      env.cowHerdCounts[i] = 0
      env.cowHerdSumX[i] = 0
      env.cowHerdSumY[i] = 0

  # Precompute team pop caps while scanning things
  var teamPopCaps: array[MapRoomObjectsHouses, int]

  for thing in env.things:
    if thing.teamId >= 0 and thing.teamId < MapRoomObjectsHouses and isBuildingKind(thing.kind):
      let add = buildingPopCap(thing.kind)
      if add > 0:
        teamPopCaps[thing.teamId] += add

    if thing.kind == Altar:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      # Combine altar heart reward calculation here
      if env.currentStep >= env.config.maxSteps:  # Only at episode end
        let altarHearts = thing.hearts.float32
        for agent in env.agents:
          if agent.homeAltar == thing.pos:
            agent.reward += altarHearts / MapAgentsPerVillageFloat
    elif thing.kind == Magma:
      env.tickCooldown(thing)
    elif thing.kind == Mill:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      else:
        let radius = max(0, buildingFertileRadius(thing.kind))
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if dx == 0 and dy == 0:
              continue
            if max(abs(dx), abs(dy)) > radius:
              continue
            let pos = thing.pos + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if not env.isEmpty(pos) or env.hasDoor(pos) or
               isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
              continue
            let terrain = env.terrain[pos.x][pos.y]
            if terrain in {Empty, Grass, Sand, Snow, Dune, Road}:
              env.terrain[pos.x][pos.y] = Fertile
              env.resetTileColor(pos)
        thing.cooldown = 10
    elif buildingUseKind(thing.kind) in {UseArmory, UseClayOven, UseWeavingLoom, UseBlacksmith, UseMarket,
                                        UseTrain, UseTrainAndCraft, UseCraft}:
      # All production buildings have simple cooldown
      env.tickCooldown(thing)
    elif thing.kind == Spawner:
      if thing.cooldown > 0:
        thing.cooldown -= 1
      else:
        # Spawner is ready to spawn a Tumor
        # Fast grid-based nearby Tumor count (5-tile radius)
        var nearbyTumorCount = 0
        for offset in spawnerScanOffsets:
          let checkPos = thing.pos + offset
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
      let herd = thing.herdId
      if herd >= env.cowHerdCounts.len:
        let newLen = herd + 1
        env.cowHerdCounts.setLen(newLen)
        env.cowHerdSumX.setLen(newLen)
        env.cowHerdSumY.setLen(newLen)
        env.cowHerdDrift.setLen(newLen)
      env.cowHerdCounts[herd] += 1
      env.cowHerdSumX[herd] += thing.pos.x.int
      env.cowHerdSumY[herd] += thing.pos.y.int
    elif thing.kind == Agent:
      if thing.frozen > 0:
        thing.frozen -= 1
    elif thing.kind == Tumor:
      # Only collect mobile clippies for processing (planted ones are static)
      if not thing.hasClaimedTerritory:
        tumorsToProcess.add(thing)

  for herdId in 0 ..< env.cowHerdCounts.len:
    if env.cowHerdCounts[herdId] <= 0:
      env.cowHerdDrift[herdId] = ivec2(0, 0)
    elif randFloat(stepRng) < 0.35:
      let dirIdx = randIntInclusive(stepRng, 0, 3)
      let drift = case dirIdx
        of 0: ivec2(-1, 0)
        of 1: ivec2(1, 0)
        of 2: ivec2(0, -1)
        else: ivec2(0, 1)
      env.cowHerdDrift[herdId] = drift
    else:
      env.cowHerdDrift[herdId] = ivec2(0, 0)

  for thing in env.thingsByKind[Cow]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    let herd = thing.herdId
    let herdAccCount = max(1, env.cowHerdCounts[herd])
    let center = ivec2((env.cowHerdSumX[herd] div herdAccCount).int32,
                       (env.cowHerdSumY[herd] div herdAccCount).int32)
    let drift = env.cowHerdDrift[herd]
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
      if isValidPos(nextPos) and not env.hasDoor(nextPos) and
         not isBlockedTerrain(env.terrain[nextPos.x][nextPos.y]) and env.isEmpty(nextPos):
        env.grid[thing.pos.x][thing.pos.y] = nil
        thing.pos = nextPos
        env.grid[nextPos.x][nextPos.y] = thing
        if desired.x < 0:
          thing.orientation = Orientation.W
        elif desired.x > 0:
          thing.orientation = Orientation.E

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tThingsMs = msBetween(tStart, tNow)
      tStart = tNow

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
    if not tumor.hasClaimedTerritory:
      env.updateTumorInfluence(tumor.pos, 1)
    tumor.hasClaimedTerritory = true
    tumor.turnsAlive = 0

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tTumorsMs = msBetween(tStart, tNow)
      tStart = tNow

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
    for offset in adjacentOffsets:
      let adjPos = tumor.pos + offset
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
    for tumor in tumorsToRemove:
      removeThing(env, tumor)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tAdjacencyMs = msBetween(tStart, tNow)
      tStart = tNow

  # Catch any agents that were reduced to zero HP during the step
  env.enforceZeroHpDeaths()

  # Precompute team population counts (Town Centers + Houses already counted above)
  var teamPopCounts: array[MapRoomObjectsHouses, int]
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let teamId = getTeamId(agent.agentId)
    if teamId >= 0 and teamId < MapRoomObjectsHouses:
      inc teamPopCounts[teamId]

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
      # Find the altar via direct grid lookup (avoids O(things) scan)
      let altarThing = env.getThing(agent.homeAltar)

      # Respawn if altar exists and has hearts above the auto-spawn threshold
      if not isNil(altarThing) and altarThing.kind == ThingKind.Altar and
          altarThing.hearts > MapObjectAltarAutoSpawnThreshold:
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

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tPopRespawnMs = msBetween(tStart, tNow)
      tStart = tNow

  # Apply per-step survival penalty to all living agents
  if env.config.survivalPenalty != 0.0:
    for agent in env.agents:
      if isAgentAlive(env, agent):  # Only alive agents
        agent.reward += env.config.survivalPenalty

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tSurvivalMs = msBetween(tStart, tNow)
      tStart = tNow

  # Update heatmap using batch tint modification system
  # This is much more efficient than updating during each entity move
  env.updateTintModifications()  # Collect all entity contributions
  env.applyTintModifications()   # Apply them to the main color array in one pass

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tTintMs = msBetween(tStart, tNow)
      tStart = tNow

  # Check if episode should end
  if env.currentStep >= env.config.maxSteps:
    # Team altar rewards already applied in main loop above
    # Mark all living agents as truncated (episode ended due to time limit)
    for i in 0..<MapAgents:
      if env.terminated[i] == 0.0:
        env.truncated[i] = 1.0
    env.shouldReset = true

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tEndMs = msBetween(tStart, tNow)

      var countTumor = 0
      var countCorpse = 0
      var countSkeleton = 0
      var countCow = 0
      var countStump = 0
      for thing in env.things:
        case thing.kind:
        of Tumor: inc countTumor
        of Corpse: inc countCorpse
        of Skeleton: inc countSkeleton
        of Cow: inc countCow
        of Stump: inc countStump
        else: discard

      let totalMs = msBetween(tTotalStart, tNow)
      echo "step=", env.currentStep,
        " total_ms=", totalMs,
        " actionTint_ms=", tActionTintMs,
        " shields_ms=", tShieldsMs,
        " preDeaths_ms=", tPreDeathsMs,
        " actions_ms=", tActionsMs,
        " things_ms=", tThingsMs,
        " tumor_ms=", tTumorsMs,
        " adjacency_ms=", tAdjacencyMs,
        " pop_respawn_ms=", tPopRespawnMs,
        " survival_ms=", tSurvivalMs,
        " tint_ms=", tTintMs,
        " end_ms=", tEndMs,
        " things=", env.things.len,
        " agents=", env.agents.len,
        " tints=", env.actionTintPositions.len,
        " tumors=", countTumor,
        " corpses=", countCorpse,
        " skeletons=", countSkeleton,
        " cows=", countCow,
        " stumps=", countStump

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
  env.thingsByKind = default(array[ThingKind, seq[Thing]])
  env.agents.setLen(0)
  env.stats.setLen(0)
  env.grid.clear()
  env.observations.clear()
  env.observationsInitialized = false
  # Clear the massive tintMods array to prevent accumulation
  env.tintMods.clear()
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorTintMods = default(array[MapWidth, array[MapHeight, TintModification]])
  env.tumorActiveTiles.positions.setLen(0)
  env.tumorActiveTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.cowHerdCounts.setLen(0)
  env.cowHerdSumX.setLen(0)
  env.cowHerdSumY.setLen(0)
  env.cowHerdDrift.setLen(0)
  # Clear global colors that could accumulate
  agentVillageColors.setLen(0)
  teamColors.setLen(0)
  altarColors.clear()
  # Clear UI selection to prevent stale references
  selection = nil
  env.init()  # init() handles terrain, activeTiles, and tile colors
