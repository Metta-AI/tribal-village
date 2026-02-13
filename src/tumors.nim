# Tumors - Tumor growth, branching, and damage processing
# This file is included by step.nim

# ============================================================================
# Shield Blocking
# ============================================================================

proc isBlockedByShield(env: Environment, agent: Thing, tumorPos: IVec2): bool =
  ## Check if a tumor position is blocked by the agent's active shield
  if env.shieldCountdown[agent.agentId] <= 0:
    return false
  let d = orientationToVec(agent.orientation)
  let perp = if d.x != 0: ivec2(0, 1) else: ivec2(1, 0)
  let forward = agent.pos + d
  for offset in -1 .. 1:
    let shieldPos = forward + ivec2(perp.x * offset, perp.y * offset)
    if shieldPos == tumorPos:
      return true
  return false

# ============================================================================
# Tumor Processing
# ============================================================================

proc stepProcessTumors(env: Environment, tumorsToProcess: seq[Thing],
                       newTumorsToSpawn: seq[Thing],
                       stepRng: var Rand) =
  ## Process tumor branching and add all newly spawned tumors to the environment.
  ## Handles both spawner-created tumors (newTumorsToSpawn) and branch tumors.
  ## Staggered: only 1/TumorProcessStagger tumors checked for branching each step.
  # Use arena buffer for temporary collection (reuses pre-allocated capacity)
  var newTumorBranches = addr env.arena.things3
  newTumorBranches[].setLen(0)

  # Stagger processing: only check 1/N tumors per step for branching
  let staggerBucket = env.currentStep mod TumorProcessStagger
  var tumorIdx = 0

  # Global tumor cap: stop branching when tumor count exceeds threshold
  let totalTumors = tumorsToProcess.len + newTumorsToSpawn.len
  let branchingAllowed = totalTumors < MaxGlobalTumors

  for tumor in tumorsToProcess:
    if env.getThing(tumor.pos) != tumor:
      continue
    tumor.turnsAlive += 1

    # Stagger: only check this tumor for branching every N steps
    let inBucket = (tumorIdx mod TumorProcessStagger) == staggerBucket
    tumorIdx += 1
    if not inBucket:
      continue

    if not branchingAllowed:
      continue

    if tumor.turnsAlive < TumorBranchMinAge:
      continue

    if randFloat(stepRng) >= TumorBranchChance:
      continue

    var branchPos = ivec2(-1, -1)
    var branchCount = 0
    for offset in TumorBranchOffsets:
      let candidate = tumor.pos + offset
      if not env.isValidEmptyPosition(candidate):
        continue

      var adjacentTumor = false
      for adj in CardinalOffsets:
        let checkPos = candidate + adj
        if not isValidPos(checkPos):
          continue
        let occupant = env.getThing(checkPos)
        if not isNil(occupant) and occupant.kind == Tumor:
          adjacentTumor = true
          break
      if not adjacentTumor:
        inc branchCount
        if randIntExclusive(stepRng, 0, branchCount) == 0:
          branchPos = candidate
    if branchPos.x < 0:
      continue

    let newTumor = createTumor(env, branchPos, tumor.homeSpawner, stepRng)

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
    newTumorBranches[].add(newTumor)
    when defined(tumorAudit):
      recordTumorBranched()
    tumor.hasClaimedTerritory = true
    tumor.turnsAlive = 0

  # Add newly spawned tumors from spawners and branching this step
  for newTumor in newTumorsToSpawn:
    env.add(newTumor)
  for newTumor in newTumorBranches[]:
    env.add(newTumor)

# ============================================================================
# Tumor Damage
# ============================================================================

proc stepApplyTumorDamage(env: Environment, stepRng: var Rand) =
  ## Resolve contact: agents and predators adjacent to tumors risk lethal creep.
  ## Optimized: iterates agents/predators O(a+p) instead of tumors O(t) since
  ## tumor count grows unboundedly while agent/predator count is bounded.
  # Use arena buffers for temporary collections (reuses pre-allocated capacity)
  var tumorsToRemove = addr env.arena.things1
  var predatorsToRemove = addr env.arena.things2
  tumorsToRemove[].setLen(0)
  predatorsToRemove[].setLen(0)

  # Process agents - check if any adjacent tumor deals damage
  for agent in env.thingsByKind[Agent]:
    if not isAgentAlive(env, agent):
      continue
    for offset in CardinalOffsets:
      let adjPos = agent.pos + offset
      if not isValidPos(adjPos):
        continue
      let tumor = env.getThing(adjPos)
      if isNil(tumor) or tumor.kind != Tumor:
        continue
      if tumor in tumorsToRemove[]:
        continue  # Tumor already marked for removal
      if env.isBlockedByShield(agent, tumor.pos):
        continue
      if randFloat(stepRng) < TumorAdjacencyDeathChance:
        let killed = env.applyAgentDamage(agent, 1)
        when defined(tumorAudit):
          recordTumorDamage(killed)
        if killed:
          tumorsToRemove[].add(tumor)
          env.grid[tumor.pos.x][tumor.pos.y] = nil
          break  # Agent dead, stop checking other tumors

  # Process predators (Bear, Wolf) - check if any adjacent tumor deals damage
  for kind in [Bear, Wolf]:
    for predator in env.thingsByKind[kind]:
      for offset in CardinalOffsets:
        let adjPos = predator.pos + offset
        if not isValidPos(adjPos):
          continue
        let tumor = env.getThing(adjPos)
        if isNil(tumor) or tumor.kind != Tumor:
          continue
        if tumor in tumorsToRemove[]:
          continue  # Tumor already marked for removal
        if randFloat(stepRng) < TumorAdjacencyDeathChance:
          when defined(tumorAudit):
            recordTumorPredatorKill()
          if predator notin predatorsToRemove[]:
            predatorsToRemove[].add(predator)
            env.grid[predator.pos.x][predator.pos.y] = nil
          tumorsToRemove[].add(tumor)
          env.grid[tumor.pos.x][tumor.pos.y] = nil
          break  # Predator dead, stop checking other tumors

  # Remove tumors cleared by lethal contact this step
  if tumorsToRemove[].len > 0:
    when defined(tumorAudit):
      for _ in tumorsToRemove[]:
        recordTumorDestroyed()
    for tumor in tumorsToRemove[]:
      removeThing(env, tumor)

  if predatorsToRemove[].len > 0:
    for predator in predatorsToRemove[]:
      removeThing(env, predator)
