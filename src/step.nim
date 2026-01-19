# This file is included by src/environment.nim
import std/os

proc parseEnvInt(raw: string, fallback: int): int =
  if raw.len == 0:
    return fallback
  try:
    parseInt(raw)
  except ValueError:
    fallback

when defined(stepTiming):
  import std/monotimes

  let stepTimingTarget = parseEnvInt(getEnv("TV_STEP_TIMING", ""), -1)
  let stepTimingWindow = parseEnvInt(getEnv("TV_STEP_TIMING_WINDOW", "0"), 0)

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

let spawnerScanOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -5 .. 5:
    for dy in -5 .. 5:
      offsets.add(ivec2(dx, dy))
  offsets

let logRenderEnabled = getEnv("TV_LOG_RENDER", "") notin ["", "0", "false"]
let logRenderWindow = max(100, parseEnvInt(getEnv("TV_LOG_RENDER_WINDOW", "100"), 100))
let logRenderEvery = max(1, parseEnvInt(getEnv("TV_LOG_RENDER_EVERY", "1"), 1))
let logRenderPath = block:
  let raw = getEnv("TV_LOG_RENDER_PATH", "")
  if raw.len > 0: raw else: "tribal_village.log"

var logRenderBuffer: seq[string] = @[]
var logRenderHead = 0
var logRenderCount = 0

include "actions"

const
  TowerAttackTint = TileColor(r: 0.95, g: 0.70, b: 0.25, intensity: 1.10)
  CastleAttackTint = TileColor(r: 0.35, g: 0.25, b: 0.85, intensity: 1.15)
  TowerAttackTintDuration = 2'i8
  CastleAttackTintDuration = 3'i8
  TankAuraTint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.05)
  MonkAuraTint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.05)
  TankAuraTintDuration = 1'i8
  MonkAuraTintDuration = 1'i8
  ManAtArmsAuraRadius = 1
  KnightAuraRadius = 2
  MonkAuraRadius = 2

proc step*(env: Environment, actions: ptr array[MapAgents, uint8]) =
  ## Step the environment
  when defined(stepTiming):
    let timing = stepTimingTarget >= 0 and env.currentStep >= stepTimingTarget and
      env.currentStep <= stepTimingTarget + stepTimingWindow
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
      if not isValidPos(pos):
        continue
      let x = pos.x
      let y = pos.y
      let c = env.actionTintCountdown[x][y]
      if c > 0:
        let next = c - 1
        env.actionTintCountdown[x][y] = next
        if next == 0:
          env.actionTintFlags[x][y] = false
          env.actionTintCode[x][y] = ActionTintNone
          env.updateObservations(TintLayer, pos, 0)
        env.actionTintPositions[writeIdx] = pos
        inc writeIdx
      else:
        env.actionTintFlags[x][y] = false
        env.actionTintCode[x][y] = ActionTintNone
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

  applyActions(env, actions)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tActionsMs = msBetween(tStart, tNow)
      tStart = tNow

  # Combined single-pass object updates and tumor collection
  var newTumorsToSpawn: seq[Thing] = @[]
  var tumorsToProcess: seq[Thing] = @[]
  var towerRemovals: seq[Thing] = @[]

  proc tryTowerAttack(tower: Thing, range: int) =
    if tower.teamId < 0:
      return
    var bestTarget: Thing = nil
    var bestDist = int.high
    for agent in env.agents:
      if not isAgentAlive(env, agent):
        continue
      if tower.teamId == getTeamId(agent):
        continue
      let dist = max(abs(agent.pos.x - tower.pos.x), abs(agent.pos.y - tower.pos.y))
      if dist <= range and dist < bestDist:
        bestDist = dist
        bestTarget = agent
    for kind in [Tumor, Spawner]:
      for thing in env.thingsByKind[kind]:
        let dist = max(abs(thing.pos.x - tower.pos.x), abs(thing.pos.y - tower.pos.y))
        if dist <= range and dist < bestDist:
          bestDist = dist
          bestTarget = thing
    if isNil(bestTarget):
      return
    let tint = if tower.kind == Castle: CastleAttackTint else: TowerAttackTint
    let tintCode = if tower.kind == Castle: ActionTintAttackCastle else: ActionTintAttackTower
    let tintDuration = if tower.kind == Castle: CastleAttackTintDuration else: TowerAttackTintDuration
    env.applyActionTint(bestTarget.pos, tint, tintDuration, tintCode)
    case bestTarget.kind
    of Agent:
      discard env.applyAgentDamage(bestTarget, max(1, tower.attackDamage))
    of Tumor, Spawner:
      if bestTarget notin towerRemovals:
        towerRemovals.add(bestTarget)
    else:
      discard

  if env.cowHerdCounts.len > 0:
    for i in 0 ..< env.cowHerdCounts.len:
      env.cowHerdCounts[i] = 0
      env.cowHerdSumX[i] = 0
      env.cowHerdSumY[i] = 0

  if env.wolfPackCounts.len > 0:
    for i in 0 ..< env.wolfPackCounts.len:
      env.wolfPackCounts[i] = 0
      env.wolfPackSumX[i] = 0
      env.wolfPackSumY[i] = 0

  # Precompute team pop caps while scanning things
  var teamPopCaps: array[MapRoomObjectsHouses, int]
  let thingsCount = env.things.len
  for i in 0 ..< thingsCount:
    let thing = env.things[i]
    if towerRemovals.len > 0 and thing in towerRemovals:
      continue
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
      if thing.cooldown > 0:
        dec thing.cooldown
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
            if terrain in BuildableTerrain:
              env.terrain[pos.x][pos.y] = Fertile
              env.resetTileColor(pos)
              env.updateObservations(ThingAgentLayer, pos, 0)
        thing.cooldown = 10
    elif thing.kind == GuardTower:
      tryTowerAttack(thing, GuardTowerRange)
    elif thing.kind == Castle:
      tryTowerAttack(thing, CastleRange)
      if thing.cooldown > 0:
        dec thing.cooldown
    elif thing.kind == Temple:
      if thing.cooldown > 0:
        dec thing.cooldown
    elif buildingUseKind(thing.kind) in {UseClayOven, UseWeavingLoom, UseBlacksmith, UseMarket,
                                         UseTrain, UseTrainAndCraft, UseCraft}:
      # All production buildings have simple cooldown
      if thing.cooldown > 0:
        dec thing.cooldown
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
        let oldLen = env.cowHerdCounts.len
        let newLen = herd + 1
        env.cowHerdCounts.setLen(newLen)
        env.cowHerdSumX.setLen(newLen)
        env.cowHerdSumY.setLen(newLen)
        env.cowHerdDrift.setLen(newLen)
        env.cowHerdTargets.setLen(newLen)
        for i in oldLen ..< newLen:
          env.cowHerdTargets[i] = ivec2(-1, -1)
      env.cowHerdCounts[herd] += 1
      env.cowHerdSumX[herd] += thing.pos.x.int
      env.cowHerdSumY[herd] += thing.pos.y.int
    elif thing.kind == Wolf:
      let pack = thing.packId
      if pack >= env.wolfPackCounts.len:
        let oldLen = env.wolfPackCounts.len
        let newLen = pack + 1
        env.wolfPackCounts.setLen(newLen)
        env.wolfPackSumX.setLen(newLen)
        env.wolfPackSumY.setLen(newLen)
        env.wolfPackDrift.setLen(newLen)
        env.wolfPackTargets.setLen(newLen)
        for i in oldLen ..< newLen:
          env.wolfPackTargets[i] = ivec2(-1, -1)
      env.wolfPackCounts[pack] += 1
      env.wolfPackSumX[pack] += thing.pos.x.int
      env.wolfPackSumY[pack] += thing.pos.y.int
    elif thing.kind == Agent:
      if thing.frozen > 0:
        thing.frozen -= 1
    elif thing.kind == Tumor:
      # Only collect mobile clippies for processing (planted ones are static)
      if not thing.hasClaimedTerritory:
        tumorsToProcess.add(thing)

  for teamId in 0 ..< teamPopCaps.len:
    if teamPopCaps[teamId] > MaxHousePopCap:
      teamPopCaps[teamId] = MaxHousePopCap

  if towerRemovals.len > 0:
    for target in towerRemovals:
      removeThing(env, target)

  proc stepToward(fromPos, toPos: IVec2): IVec2 =
    let dx = toPos.x - fromPos.x
    let dy = toPos.y - fromPos.y
    if dx == 0 and dy == 0:
      return ivec2(0, 0)
    if abs(dx) >= abs(dy):
      return ivec2((if dx > 0: 1 else: -1), 0)
    return ivec2(0, (if dy > 0: 1 else: -1))

  proc tryStep(thing: Thing, desired: IVec2) =
    if desired == ivec2(0, 0):
      return
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

  proc findNearestPredatorTarget(center: IVec2, radius: int): IVec2 =
    var bestTumorDist = int.high
    var bestTumor = ivec2(-1, -1)
    var bestAgentDist = int.high
    var bestAgent = ivec2(-1, -1)
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        let pos = center + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        let dist = max(abs(dx), abs(dy))
        if dist > radius:
          continue
        let thing = env.getThing(pos)
        if isNil(thing):
          continue
        if thing.kind == Tumor and not thing.hasClaimedTerritory:
          if dist < bestTumorDist:
            bestTumorDist = dist
            bestTumor = pos
        elif thing.kind == Agent and isAgentAlive(env, thing):
          if dist < bestAgentDist:
            bestAgentDist = dist
            bestAgent = pos
    if bestTumor.x >= 0: bestTumor else: bestAgent

  let cornerMin = (MapBorder + 2).int32
  let cornerMaxX = (MapWidth - MapBorder - 3).int32
  let cornerMaxY = (MapHeight - MapBorder - 3).int32
  let cornerTargets = [
    ivec2(cornerMin, cornerMin),
    ivec2(cornerMaxX, cornerMin),
    ivec2(cornerMin, cornerMaxY),
    ivec2(cornerMaxX, cornerMaxY)
  ]

  for herdId in 0 ..< env.cowHerdCounts.len:
    if env.cowHerdCounts[herdId] <= 0:
      env.cowHerdDrift[herdId] = ivec2(0, 0)
      continue
    let herdAccCount = max(1, env.cowHerdCounts[herdId])
    let center = ivec2((env.cowHerdSumX[herdId] div herdAccCount).int32,
                       (env.cowHerdSumY[herdId] div herdAccCount).int32)
    let target = env.cowHerdTargets[herdId]
    let targetInvalid = target.x < 0 or target.y < 0
    let distToTarget = if targetInvalid:
      0
    else:
      max(abs(center.x - target.x), abs(center.y - target.y))
    let nearBorder = center.x <= cornerMin or center.y <= cornerMin or
                     center.x >= cornerMaxX or center.y >= cornerMaxY
    if targetInvalid or (nearBorder and distToTarget <= 3):
      var bestDist = -1
      var candidates: seq[IVec2] = @[]
      for corner in cornerTargets:
        if corner == target:
          continue
        let dist = max(abs(center.x - corner.x), abs(center.y - corner.y))
        if dist > bestDist:
          candidates.setLen(0)
          candidates.add(corner)
          bestDist = dist
        elif dist == bestDist:
          candidates.add(corner)
      if candidates.len == 0:
        env.cowHerdTargets[herdId] = cornerTargets[randIntInclusive(stepRng, 0, 3)]
      else:
        env.cowHerdTargets[herdId] = candidates[randIntInclusive(stepRng, 0, candidates.len - 1)]
    env.cowHerdDrift[herdId] = stepToward(center, env.cowHerdTargets[herdId])

  for packId in 0 ..< env.wolfPackCounts.len:
    if env.wolfPackCounts[packId] <= 0:
      env.wolfPackDrift[packId] = ivec2(0, 0)
      continue
    let packAccCount = max(1, env.wolfPackCounts[packId])
    let center = ivec2((env.wolfPackSumX[packId] div packAccCount).int32,
                       (env.wolfPackSumY[packId] div packAccCount).int32)
    let huntTarget = findNearestPredatorTarget(center, WolfPackAggroRadius)
    if huntTarget.x >= 0:
      env.wolfPackTargets[packId] = huntTarget
    else:
      let target = env.wolfPackTargets[packId]
      let targetInvalid = target.x < 0 or target.y < 0
      let distToTarget = if targetInvalid:
        0
      else:
        max(abs(center.x - target.x), abs(center.y - target.y))
      let nearBorder = center.x <= cornerMin or center.y <= cornerMin or
                       center.x >= cornerMaxX or center.y >= cornerMaxY
      if targetInvalid or (nearBorder and distToTarget <= 3):
        var bestDist = -1
        var candidates: seq[IVec2] = @[]
        for corner in cornerTargets:
          if corner == target:
            continue
          let dist = max(abs(center.x - corner.x), abs(center.y - corner.y))
          if dist > bestDist:
            candidates.setLen(0)
            candidates.add(corner)
            bestDist = dist
          elif dist == bestDist:
            candidates.add(corner)
        if candidates.len == 0:
          env.wolfPackTargets[packId] = cornerTargets[randIntInclusive(stepRng, 0, 3)]
        else:
          env.wolfPackTargets[packId] = candidates[randIntInclusive(stepRng, 0, candidates.len - 1)]
    env.wolfPackDrift[packId] = stepToward(center, env.wolfPackTargets[packId])

  for thing in env.thingsByKind[Cow]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    let herd = thing.herdId
    let herdAccCount = max(1, env.cowHerdCounts[herd])
    let center = ivec2((env.cowHerdSumX[herd] div herdAccCount).int32,
                       (env.cowHerdSumY[herd] div herdAccCount).int32)
    let drift = env.cowHerdDrift[herd]
    let herdTarget = if drift.x != 0 or drift.y != 0:
      center + drift * 3
    else:
      center
    let dist = max(abs(herdTarget.x - thing.pos.x), abs(herdTarget.y - thing.pos.y))

    var desired = ivec2(0, 0)
    if dist > 1:
      desired = stepToward(thing.pos, herdTarget)
    elif (drift.x != 0 or drift.y != 0) and randFloat(stepRng) < 0.6:
      desired = stepToward(thing.pos, herdTarget)
    elif randFloat(stepRng) < 0.08:
      desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]

    tryStep(thing, desired)

  for thing in env.thingsByKind[Wolf]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    let pack = thing.packId
    let packAccCount = max(1, env.wolfPackCounts[pack])
    let center = ivec2((env.wolfPackSumX[pack] div packAccCount).int32,
                       (env.wolfPackSumY[pack] div packAccCount).int32)
    let packTarget = env.wolfPackTargets[pack]
    let drift = env.wolfPackDrift[pack]
    let distFromCenter = max(abs(center.x - thing.pos.x), abs(center.y - thing.pos.y))
    var desired = ivec2(0, 0)
    if distFromCenter > WolfPackCohesionRadius:
      desired = stepToward(thing.pos, center)
    elif packTarget.x >= 0:
      let distToTarget = max(abs(packTarget.x - thing.pos.x), abs(packTarget.y - thing.pos.y))
      if distToTarget > 1:
        desired = stepToward(thing.pos, packTarget)
    elif (drift.x != 0 or drift.y != 0) and randFloat(stepRng) < 0.55:
      desired = stepToward(thing.pos, center + drift * 3)
    elif randFloat(stepRng) < 0.1:
      desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]

    tryStep(thing, desired)

  for thing in env.thingsByKind[Bear]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    let target = findNearestPredatorTarget(thing.pos, BearAggroRadius)
    var desired = ivec2(0, 0)
    if target.x >= 0:
      let dist = max(abs(target.x - thing.pos.x), abs(target.y - thing.pos.y))
      if dist > 1:
        desired = stepToward(thing.pos, target)
    elif randFloat(stepRng) < 0.12:
      desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]

    tryStep(thing, desired)

  for kind in [Wolf, Bear]:
    for predator in env.thingsByKind[kind]:
      block predatorAttack:
        var agentTarget: Thing = nil
        for offset in CardinalOffsets:
          let pos = predator.pos + offset
          if not isValidPos(pos):
            continue
          let target = env.getThing(pos)
          if isNil(target):
            continue
          if target.kind == Tumor and not target.hasClaimedTerritory:
            removeThing(env, target)
            break predatorAttack
          if target.kind == Agent and isAgentAlive(env, target) and agentTarget.isNil:
            agentTarget = target
        if not agentTarget.isNil:
          discard env.applyAgentDamage(agentTarget, max(1, predator.attackDamage))

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tThingsMs = msBetween(tStart, tNow)
      tStart = tNow

  # ============== TUMOR PROCESSING ==============
  var newTumorBranches: seq[Thing] = @[]

  for tumor in tumorsToProcess:
    if env.getThing(tumor.pos) != tumor:
      continue
    tumor.turnsAlive += 1
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

  # Resolve contact: agents and predators adjacent to tumors risk lethal creep
  var tumorsToRemove: seq[Thing] = @[]
  var predatorsToRemove: seq[Thing] = @[]

  let thingCount = env.things.len
  for i in 0 ..< thingCount:
    let tumor = env.things[i]
    if tumor.kind != Tumor:
      continue
    for offset in CardinalOffsets:
      let adjPos = tumor.pos + offset
      if not isValidPos(adjPos):
        continue

      let occupant = env.getThing(adjPos)
      if isNil(occupant) or occupant.kind notin {Agent, Bear, Wolf}:
        continue

      if occupant.kind == Agent:
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
          if killed:
            break
      else:
        if randFloat(stepRng) < TumorAdjacencyDeathChance:
          if occupant notin predatorsToRemove:
            predatorsToRemove.add(occupant)
            env.grid[occupant.pos.x][occupant.pos.y] = nil
          if tumor notin tumorsToRemove:
            tumorsToRemove.add(tumor)
            env.grid[tumor.pos.x][tumor.pos.y] = nil

  # Remove tumors cleared by lethal contact this step
  if tumorsToRemove.len > 0:
    for tumor in tumorsToRemove:
      removeThing(env, tumor)

  if predatorsToRemove.len > 0:
    for predator in predatorsToRemove:
      removeThing(env, predator)

  # Tank aura tints
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if isThingFrozen(agent, env):
      continue
    let radius = case agent.unitClass
      of UnitManAtArms: ManAtArmsAuraRadius
      of UnitKnight: KnightAuraRadius
      else: -1
    if radius < 0:
      continue
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        let pos = agent.pos + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        let existingCountdown = env.actionTintCountdown[pos.x][pos.y]
        let existingCode = env.actionTintCode[pos.x][pos.y]
        if existingCountdown > 0 and existingCode notin {ActionTintNone, ActionTintShield}:
          if existingCode != ActionTintMixed:
            env.actionTintCode[pos.x][pos.y] = ActionTintMixed
            env.updateObservations(TintLayer, pos, ActionTintMixed.int)
          continue
        env.applyActionTint(pos, TankAuraTint, TankAuraTintDuration, ActionTintShield)

  # Monk aura tints + healing
  var healFlags: array[MapAgents, bool]
  for monk in env.agents:
    if not isAgentAlive(env, monk):
      continue
    if monk.unitClass != UnitMonk:
      continue
    if isThingFrozen(monk, env):
      continue
    let teamId = getTeamId(monk)
    var needsHeal = false
    for ally in env.agents:
      if not isAgentAlive(env, ally):
        continue
      if getTeamId(ally) != teamId:
        continue
      let dx = abs(ally.pos.x - monk.pos.x)
      let dy = abs(ally.pos.y - monk.pos.y)
      if max(dx, dy) > MonkAuraRadius:
        continue
      if ally.hp < ally.maxHp and not isThingFrozen(ally, env):
        needsHeal = true
        break
    if not needsHeal:
      continue

    for dx in -MonkAuraRadius .. MonkAuraRadius:
      for dy in -MonkAuraRadius .. MonkAuraRadius:
        let pos = monk.pos + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        let existingCountdown = env.actionTintCountdown[pos.x][pos.y]
        let existingCode = env.actionTintCode[pos.x][pos.y]
        if existingCountdown > 0 and existingCode notin {ActionTintNone, ActionTintShield, ActionTintHealMonk}:
          if existingCode != ActionTintMixed:
            env.actionTintCode[pos.x][pos.y] = ActionTintMixed
            env.updateObservations(TintLayer, pos, ActionTintMixed.int)
          continue
        env.applyActionTint(pos, MonkAuraTint, MonkAuraTintDuration, ActionTintHealMonk)

    for ally in env.agents:
      if not isAgentAlive(env, ally):
        continue
      if getTeamId(ally) != teamId:
        continue
      let dx = abs(ally.pos.x - monk.pos.x)
      let dy = abs(ally.pos.y - monk.pos.y)
      if max(dx, dy) > MonkAuraRadius:
        continue
      if not isThingFrozen(ally, env):
        healFlags[ally.agentId] = true

  for agentId in 0 ..< env.agents.len:
    if not healFlags[agentId]:
      continue
    let target = env.agents[agentId]
    if isAgentAlive(env, target) and target.hp < target.maxHp and not isThingFrozen(target, env):
      target.hp = min(target.maxHp, target.hp + 1)

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
    let teamId = getTeamId(agent)
    if teamId >= 0 and teamId < MapRoomObjectsHouses:
      inc teamPopCounts[teamId]

  # Respawn dead agents at their altars
  for agentId in 0 ..< MapAgents:
    let agent = env.agents[agentId]

    # Check if agent is dead and has a home altar
    if env.terminated[agentId] == 1.0 and agent.homeAltar.x >= 0:
      let teamId = getTeamId(agent)
      if teamId < 0 or teamId >= MapRoomObjectsHouses:
        continue
      if teamPopCounts[teamId] >= teamPopCaps[teamId]:
        continue
      # Find the altar via direct grid lookup (avoids O(things) scan)
      let altarThing = env.getThing(agent.homeAltar)

      # Respawn if altar exists and has at least one heart to spend
      if not isNil(altarThing) and altarThing.kind == ThingKind.Altar and
          altarThing.hearts >= MapObjectAltarRespawnCost:
        # Deduct a heart from the altar (can reach 0, but not negative)
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
          env.updateObservations(AgentLayer, agent.pos, getTeamId(agent) + 1)
          env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
          for key in ObservedItemKeys:
            env.updateAgentInventoryObs(agent, key)

  # Temple hybrid spawn: two adjacent agents + heart -> spawn a new villager.
  for temple in env.thingsByKind[Temple]:
    if temple.cooldown > 0:
      continue
    var parentA: Thing = nil
    var parentB: Thing = nil
    var teamId = -1
    for d in AdjacentOffsets8:
      let pos = temple.pos + d
      if not isValidPos(pos):
        continue
      let candidate = env.grid[pos.x][pos.y]
      if isNil(candidate) or candidate.kind != Agent:
        continue
      if not isAgentAlive(env, candidate):
        continue
      if candidate.unitClass == UnitGoblin:
        continue
      let candTeam = getTeamId(candidate)
      if candTeam < 0 or candTeam >= MapRoomObjectsHouses:
        continue
      if parentA.isNil:
        parentA = candidate
        teamId = candTeam
      elif candTeam == teamId and candidate.agentId != parentA.agentId:
        parentB = candidate
        break
    if parentA.isNil or parentB.isNil:
      continue
    if teamPopCounts[teamId] >= teamPopCaps[teamId]:
      continue
    # Find a dormant agent slot for this team.
    let teamStart = teamId * MapAgentsPerVillage
    let teamEnd = teamStart + MapAgentsPerVillage
    var childId = -1
    for id in teamStart ..< teamEnd:
      if env.terminated[id] == 1.0:
        childId = id
        break
    if childId < 0:
      continue
    let spawnPos = env.findFirstEmptyPositionAround(temple.pos, 2)
    if spawnPos.x < 0:
      continue
    let altarThing = env.getThing(parentA.homeAltar)
    if isNil(altarThing) or altarThing.kind != ThingKind.Altar:
      continue
    if altarThing.hearts < MapObjectAltarRespawnCost:
      continue
    # Consume heart and spawn the child.
    altarThing.hearts = altarThing.hearts - MapObjectAltarRespawnCost
    env.updateObservations(altarHeartsLayer, altarThing.pos, altarThing.hearts)
    let child = env.agents[childId]
    child.pos = spawnPos
    child.inventory = emptyInventory()
    child.frozen = 0
    applyUnitClass(child, UnitVillager)
    env.terminated[childId] = 0.0
    env.grid[child.pos.x][child.pos.y] = child
    inc teamPopCounts[teamId]
    env.updateObservations(AgentLayer, child.pos, getTeamId(child) + 1)
    env.updateObservations(AgentOrientationLayer, child.pos, child.orientation.int)
    for key in ObservedItemKeys:
      env.updateAgentInventoryObs(child, key)
    env.templeHybridRequests.add TempleHybridRequest(
      parentA: parentA.agentId,
      parentB: parentB.agentId,
      childId: childId,
      teamId: teamId,
      pos: temple.pos
    )
    temple.cooldown = 25

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
    if not env.territoryScored:
      env.territoryScore = env.scoreTerritory()
      env.territoryScored = true
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
    if not env.territoryScored:
      env.territoryScore = env.scoreTerritory()
      env.territoryScored = true
    env.shouldReset = true

  maybeLogReplayStep(env, actions)
  if env.shouldReset:
    maybeFinalizeReplay(env)

  if logRenderEnabled and (env.currentStep mod logRenderEvery == 0):
    var entry = "STEP " & $env.currentStep & "\n"
    var teamSeen: array[MapRoomObjectsHouses, bool]
    for agent in env.agents:
      if agent.isNil:
        continue
      let teamId = getTeamId(agent)
      if teamId >= 0 and teamId < teamSeen.len:
        teamSeen[teamId] = true
    entry.add("Stockpiles:\n")
    for teamId, seen in teamSeen:
      if not seen:
        continue
      entry.add(
        "  t" & $teamId &
        " food=" & $env.stockpileCount(teamId, ResourceFood) &
        " wood=" & $env.stockpileCount(teamId, ResourceWood) &
        " stone=" & $env.stockpileCount(teamId, ResourceStone) &
        " gold=" & $env.stockpileCount(teamId, ResourceGold) & "\n"
      )
    entry.add("Agents:\n")
    for id, agent in env.agents:
      if agent.isNil:
        continue
      let actionValue = actions[][id]
      let verb = actionValue.int div ActionArgumentCount
      let arg = actionValue.int mod ActionArgumentCount
      var invParts: seq[string] = @[]
      for key in ObservedItemKeys:
        let count = getInv(agent, key)
        if count > 0:
          invParts.add($key & "=" & $count)
      let invSummary = if invParts.len > 0: invParts.join(",") else: "-"
      entry.add(
        "  a" & $id &
        " t" & $getTeamId(agent) &
        " " & (case agent.agentId mod MapAgentsPerVillage:
          of 0, 1: "gatherer"
          of 2, 3: "builder"
          of 4, 5: "fighter"
          else: "gatherer") &
        " pos=(" & $agent.pos.x & "," & $agent.pos.y & ")" &
        " ori=" & $agent.orientation &
        " act=" & (case verb:
          of 0: "noop"
          of 1: "move"
          of 2: "attack"
          of 3: "use"
          of 4: "swap"
          of 5: "put"
          of 6: "plant_lantern"
          of 7: "plant_resource"
          of 8: "build"
          of 9: "orient"
          else: "unknown") & ":" &
        (if verb in [1, 2, 3, 9]:
          (case arg:
            of 0: "N"
            of 1: "S"
            of 2: "W"
            of 3: "E"
            of 4: "NW"
            of 5: "NE"
            of 6: "SW"
            of 7: "SE"
            else: $arg)
        else:
          $arg) &
        " hp=" & $agent.hp & "/" & $agent.maxHp &
        " inv=" & invSummary & "\n"
      )
    entry.add("Map:\n")
    entry.add(env.render())
    if logRenderBuffer.len < logRenderWindow:
      logRenderBuffer.add(entry)
      logRenderCount = logRenderBuffer.len
    else:
      logRenderBuffer[logRenderHead] = entry
      logRenderHead = (logRenderHead + 1) mod logRenderWindow
      logRenderCount = logRenderWindow

    if logRenderCount > 0:
      var output = newStringOfCap(logRenderCount * 512)
      output.add("=== tribal-village log window (" & $logRenderCount & " steps) ===\n")
      for i in 0 ..< logRenderCount:
        let idx = (logRenderHead + i) mod logRenderCount
        output.add(logRenderBuffer[idx])
        output.add("\n")
      writeFile(logRenderPath, output)

proc reset*(env: Environment) =
  maybeFinalizeReplay(env)
  env.currentStep = 0
  env.shouldReset = false
  env.terminated.clear()
  env.truncated.clear()
  env.things.setLen(0)
  env.thingsByKind = default(array[ThingKind, seq[Thing]])
  env.agents.setLen(0)
  env.stats.setLen(0)
  env.templeInteractions.setLen(0)
  env.templeHybridRequests.setLen(0)
  env.grid.clear()
  env.observations.clear()
  env.observationsInitialized = false
  # Clear the massive tintMods array to prevent accumulation
  env.tintMods.clear()
  env.tintStrength = default(array[MapWidth, array[MapHeight, int32]])
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorTintMods = default(array[MapWidth, array[MapHeight, TintModification]])
  env.tumorStrength = default(array[MapWidth, array[MapHeight, int32]])
  env.tumorActiveTiles.positions.setLen(0)
  env.tumorActiveTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.cowHerdCounts.setLen(0)
  env.cowHerdSumX.setLen(0)
  env.cowHerdSumY.setLen(0)
  env.cowHerdDrift.setLen(0)
  env.cowHerdTargets.setLen(0)
  env.wolfPackCounts.setLen(0)
  env.wolfPackSumX.setLen(0)
  env.wolfPackSumY.setLen(0)
  env.wolfPackDrift.setLen(0)
  env.wolfPackTargets.setLen(0)
  # Clear colors (now stored in Environment)
  env.agentColors.setLen(0)
  env.teamColors.setLen(0)
  env.altarColors.clear()
  env.territoryScore = default(TerritoryScore)
  env.territoryScored = false
  # Clear UI selection to prevent stale references
  selection = nil
  env.init()  # init() handles terrain, activeTiles, and tile colors
