# This file is included by src/environment.nim
# std/os is already imported by console_viz.nim (included before this file)
# std/strutils is already imported by environment.nim

when defined(rewardBatch):
  import std/monotimes
  var rewardBatchOps: int = 0
  var rewardBatchCumMs: float64 = 0.0
  var rewardBatchSteps: int = 0
  const RewardBatchReportInterval = 500

  proc rewardBatchMsBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

  proc reportRewardBatch() =
    if rewardBatchSteps > 0:
      let avgOps = rewardBatchOps.float64 / rewardBatchSteps.float64
      let avgMs = rewardBatchCumMs / rewardBatchSteps.float64
      echo "[rewardBatch] steps=", rewardBatchSteps,
        " avgOps/step=", avgOps,
        " avgMs/step=", avgMs
      rewardBatchOps = 0
      rewardBatchCumMs = 0.0
      rewardBatchSteps = 0

# parseEnvInt is now provided by envconfig module (imported by environment.nim)
# Use parseEnvIntRaw for cases where we already have the raw string value

when defined(stepTiming):
  import std/monotimes

  let stepTimingTarget = parseEnvInt("TV_STEP_TIMING", -1)
  let stepTimingWindow = parseEnvInt("TV_STEP_TIMING_WINDOW", 0)
  let stepTimingInterval = parseEnvInt("TV_TIMING_INTERVAL", 100)

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

  const TimingSystemCount = 11
  const TimingSystemNames: array[TimingSystemCount, string] = [
    "actionTint", "shields", "preDeaths", "actions", "things",
    "tumors", "tumorDamage", "auras", "popRespawn", "survival", "tintObs"
  ]

  var timingCumSum: array[TimingSystemCount, float64]
  var timingCumMax: array[TimingSystemCount, float64]
  var timingCumTotal: float64 = 0.0
  var timingStepCount: int = 0

  proc resetTimingCounters() =
    for i in 0 ..< TimingSystemCount:
      timingCumSum[i] = 0.0
      timingCumMax[i] = 0.0
    timingCumTotal = 0.0
    timingStepCount = 0

  proc recordTimingSample(idx: int, ms: float64) =
    timingCumSum[idx] += ms
    if ms > timingCumMax[idx]:
      timingCumMax[idx] = ms

  proc printTimingReport(currentStep: int) =
    if timingStepCount == 0:
      return
    let n = timingStepCount.float64
    echo ""
    echo "=== Step Timing Report (steps ", currentStep - timingStepCount + 1, "-", currentStep, ", n=", timingStepCount, ") ==="
    echo align("System", 14), " | ", align("Avg ms", 10), " | ", align("Max ms", 10), " | ", align("% Total", 8)
    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 8)
    for i in 0 ..< TimingSystemCount:
      let avg = timingCumSum[i] / n
      let maxMs = timingCumMax[i]
      let pct = if timingCumTotal > 0.0: timingCumSum[i] / timingCumTotal * 100.0 else: 0.0
      echo align(TimingSystemNames[i], 14), " | ",
           align(formatFloat(avg, ffDecimal, 4), 10), " | ",
           align(formatFloat(maxMs, ffDecimal, 4), 10), " | ",
           align(formatFloat(pct, ffDecimal, 1), 8)
    let totalAvg = timingCumTotal / n
    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 8)
    echo align("TOTAL", 14), " | ", align(formatFloat(totalAvg, ffDecimal, 4), 10), " | ", align("", 10), " | ", align("100.0", 8)
    echo ""
    resetTimingCounters()

when defined(perfRegression):
  include "perf_regression"

  proc msBetweenPerfTiming(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

when defined(flameGraph):
  include "flame_graph"

let logRenderEnabled = parseEnvBool("TV_LOG_RENDER", false)
let logRenderWindow = max(100, parseEnvInt("TV_LOG_RENDER_WINDOW", 100))
let logRenderEvery = max(1, parseEnvInt("TV_LOG_RENDER_EVERY", 1))
let logRenderPath = block:
  let raw = getEnv("TV_LOG_RENDER_PATH", "")
  if raw.len > 0: raw else: "tribal_village.log"

var logRenderBuffer: seq[string] = @[]
var logRenderHead = 0
var logRenderCount = 0

include "actions"

# Common distance calculation used throughout step logic
template chebyshevDist*(a, b: IVec2): int32 =
  ## Chebyshev distance (max of abs differences) - used for tower/building ranges
  max(abs(a.x - b.x), abs(a.y - b.y))

const
  # Tower/Castle/TownCenter attack visuals (colors are display-only, not in constants.nim)
  TowerAttackTint = TileColor(r: 0.95, g: 0.70, b: 0.25, intensity: 1.10)
  CastleAttackTint = TileColor(r: 0.35, g: 0.25, b: 0.85, intensity: 1.15)
  TownCenterAttackTint = TileColor(r: 0.85, g: 0.50, b: 0.20, intensity: 1.12)

  # Aura tints (colors are display-only, not in constants.nim)
  TankAuraTint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.05)
  MonkAuraTint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.05)

  # Compile-time dispatch tables: replace runtime case/branching with array lookups
  # indexed by AgentUnitClass enum ordinal. This eliminates branch mispredictions in
  # hot paths by converting conditional logic to direct memory loads.

  ## Aura radius per unit class (-1 = no aura)
  UnitAuraRadius: array[AgentUnitClass, int] = [
    UnitVillager: -1, UnitManAtArms: ManAtArmsAuraRadius, UnitArcher: -1,
    UnitScout: -1, UnitKnight: KnightAuraRadius, UnitMonk: -1,
    UnitBatteringRam: -1, UnitMangonel: -1, UnitTrebuchet: -1,
    UnitGoblin: -1, UnitBoat: -1, UnitTradeCog: -1,
    UnitSamurai: -1, UnitLongbowman: -1, UnitCataphract: -1,
    UnitWoadRaider: -1, UnitTeutonicKnight: -1, UnitHuskarl: -1,
    UnitMameluke: -1, UnitJanissary: -1, UnitKing: -1,
    UnitLongSwordsman: -1, UnitChampion: -1,
    UnitLightCavalry: -1, UnitHussar: -1,
    UnitCrossbowman: -1, UnitArbalester: -1,
    UnitGalley: -1, UnitFireShip: -1, UnitScorpion: -1,
  ]

  ## Base ranged attack range per unit class (0 = melee)
  UnitRangedRange: array[AgentUnitClass, int] = [
    UnitVillager: 0, UnitManAtArms: 0, UnitArcher: ArcherBaseRange,
    UnitScout: 0, UnitKnight: 0, UnitMonk: 0,
    UnitBatteringRam: 0, UnitMangonel: 0, UnitTrebuchet: TrebuchetBaseRange,
    UnitGoblin: 0, UnitBoat: 0, UnitTradeCog: 0,
    UnitSamurai: 0, UnitLongbowman: 0, UnitCataphract: 0,
    UnitWoadRaider: 0, UnitTeutonicKnight: 0, UnitHuskarl: 0,
    UnitMameluke: 0, UnitJanissary: 0, UnitKing: 0,
    UnitLongSwordsman: 0, UnitChampion: 0,
    UnitLightCavalry: 0, UnitHussar: 0,
    UnitCrossbowman: ArcherBaseRange, UnitArbalester: ArcherBaseRange,
    UnitGalley: GalleyBaseRange, UnitFireShip: 0, UnitScorpion: ScorpionBaseRange,
  ]

  ## Units eligible for Ballistics tech damage bonus
  BallisticsUnits: set[AgentUnitClass] = {
    UnitArcher, UnitLongbowman, UnitJanissary, UnitCrossbowman, UnitArbalester,
    UnitGalley, UnitScorpion
  }

  ## Units eligible for Siege Engineers tech range bonus
  SiegeUnits: set[AgentUnitClass] = {
    UnitBatteringRam, UnitMangonel, UnitTrebuchet
  }

  ## Cavalry units that get double-move in step
  CavalryMoveUnits: set[AgentUnitClass] = {
    UnitScout, UnitKnight
  }

  ## Units with charge attack (2-tile forward attack)
  ChargeAttackUnits: set[AgentUnitClass] = {
    UnitScout, UnitBatteringRam
  }

proc spawnProjectile(env: Environment, source, target: IVec2, kind: ProjectileKind) {.inline.} =
  ## Spawn a visual-only projectile from source to target.
  ## Lifetime scales with distance for natural flight speed.
  ## Uses pre-allocated pool to minimize heap allocations.
  let dist = max(abs(target.x - source.x), abs(target.y - source.y))
  if dist <= 0:
    return
  # Siege projectiles travel slower (more frames), arrows faster
  let lifetime = case kind
    of ProjMangonel: min(dist + ProjMangonelAddedFrames, ProjMangonelMaxLifetime).int8
    of ProjTrebuchet: min(dist + ProjTrebuchetAddedFrames, ProjTrebuchetMaxLifetime).int8
    else: min(dist + ProjArrowBaseLifetime, ProjArrowMaxLifetime).int8
  env.projectiles.add(Projectile(
    source: source, target: target, kind: kind,
    countdown: lifetime, lifetime: lifetime))
  env.projectilePool.stats.acquired += 1
  env.projectilePool.stats.poolSize = env.projectiles.len

proc stepDecayProjectiles(env: Environment) =
  ## Decay and remove expired projectiles.
  ## Uses in-place compaction - setLen preserves capacity for pool reuse.
  if env.projectiles.len > 0:
    var writeIdx = 0
    let startLen = env.projectiles.len
    for readIdx in 0 ..< env.projectiles.len:
      env.projectiles[readIdx].countdown -= 1
      if env.projectiles[readIdx].countdown > 0:
        env.projectiles[writeIdx] = env.projectiles[readIdx]
        inc writeIdx
    env.projectiles.setLen(writeIdx)
    # Track released projectiles for pool stats
    let released = startLen - writeIdx
    env.projectilePool.stats.released += released
    env.projectilePool.stats.poolSize = writeIdx

proc stepDecayDamageNumbers(env: Environment) =
  ## Decay and remove expired damage numbers.
  ## Uses in-place compaction - setLen preserves capacity for pool reuse.
  if env.damageNumbers.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.damageNumbers.len:
      env.damageNumbers[readIdx].countdown -= 1
      if env.damageNumbers[readIdx].countdown > 0:
        env.damageNumbers[writeIdx] = env.damageNumbers[readIdx]
        inc writeIdx
    env.damageNumbers.setLen(writeIdx)

proc stepRagdolls(env: Environment) =
  ## Update ragdoll physics and remove expired ragdolls.
  ## Applies velocity, gravity, friction, and rotation each frame.
  if env.ragdolls.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.ragdolls.len:
      var ragdoll = env.ragdolls[readIdx]
      ragdoll.countdown -= 1
      if ragdoll.countdown > 0:
        # Apply physics: velocity, gravity, friction, rotation
        ragdoll.pos.x += ragdoll.velocity.x
        ragdoll.pos.y += ragdoll.velocity.y
        ragdoll.velocity.y += RagdollGravity  # Gravity pulls "down" (positive Y)
        ragdoll.velocity.x *= RagdollFriction
        ragdoll.velocity.y *= RagdollFriction
        ragdoll.angle += ragdoll.angularVel
        ragdoll.angularVel *= RagdollFriction  # Angular friction
        env.ragdolls[writeIdx] = ragdoll
        inc writeIdx
    env.ragdolls.setLen(writeIdx)

proc stepDecayDebris(env: Environment) =
  ## Update debris particle positions and remove expired ones.
  ## Particles move outward with velocity and fade over time.
  if env.debris.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.debris.len:
      env.debris[readIdx].countdown -= 1
      if env.debris[readIdx].countdown > 0:
        # Update position based on velocity
        env.debris[readIdx].pos.x += env.debris[readIdx].velocity.x
        env.debris[readIdx].pos.y += env.debris[readIdx].velocity.y
        # Apply slight gravity/drag to velocity
        env.debris[readIdx].velocity.y += 0.005  # Gravity pulls down
        env.debris[readIdx].velocity.x *= 0.95   # Horizontal drag
        env.debris[writeIdx] = env.debris[readIdx]
        inc writeIdx
    env.debris.setLen(writeIdx)

proc stepDecaySpawnEffects(env: Environment) =
  ## Decay and remove expired spawn effects.
  ## Uses in-place compaction - setLen preserves capacity for pool reuse.
  if env.spawnEffects.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.spawnEffects.len:
      env.spawnEffects[readIdx].countdown -= 1
      if env.spawnEffects[readIdx].countdown > 0:
        env.spawnEffects[writeIdx] = env.spawnEffects[readIdx]
        inc writeIdx
    env.spawnEffects.setLen(writeIdx)

proc stepDecayDyingUnits(env: Environment) =
  ## Decay and remove expired dying unit animations.
  ## Uses in-place compaction - setLen preserves capacity for pool reuse.
  if env.dyingUnits.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.dyingUnits.len:
      env.dyingUnits[readIdx].countdown -= 1
      if env.dyingUnits[readIdx].countdown > 0:
        env.dyingUnits[writeIdx] = env.dyingUnits[readIdx]
        inc writeIdx
    env.dyingUnits.setLen(writeIdx)

proc stepDecayGatherSparkles(env: Environment) =
  ## Update gather sparkle particle positions and remove expired ones.
  ## Particles burst outward and fade over time.
  if env.gatherSparkles.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.gatherSparkles.len:
      env.gatherSparkles[readIdx].countdown -= 1
      if env.gatherSparkles[readIdx].countdown > 0:
        # Update position based on velocity
        env.gatherSparkles[readIdx].pos.x += env.gatherSparkles[readIdx].velocity.x
        env.gatherSparkles[readIdx].pos.y += env.gatherSparkles[readIdx].velocity.y
        # Apply slight deceleration (sparkles slow down as they expand)
        env.gatherSparkles[readIdx].velocity.x *= 0.92
        env.gatherSparkles[readIdx].velocity.y *= 0.92
        env.gatherSparkles[writeIdx] = env.gatherSparkles[readIdx]
        inc writeIdx
    env.gatherSparkles.setLen(writeIdx)

proc stepDecayConstructionDust(env: Environment) =
  ## Update construction dust particle positions and remove expired ones.
  ## Particles rise upward and fade over time.
  if env.constructionDust.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.constructionDust.len:
      env.constructionDust[readIdx].countdown -= 1
      if env.constructionDust[readIdx].countdown > 0:
        # Update position based on velocity (rising upward)
        env.constructionDust[readIdx].pos.x += env.constructionDust[readIdx].velocity.x
        env.constructionDust[readIdx].pos.y += env.constructionDust[readIdx].velocity.y
        # Dust slows down as it rises and spreads slightly
        env.constructionDust[readIdx].velocity.y *= 0.96
        env.constructionDust[readIdx].velocity.x *= 0.98
        env.constructionDust[writeIdx] = env.constructionDust[readIdx]
        inc writeIdx
    env.constructionDust.setLen(writeIdx)

proc stepDecayUnitTrails(env: Environment) =
  ## Update unit trail particle positions and remove expired ones.
  ## Trails drift slightly and fade over time.
  if env.unitTrails.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.unitTrails.len:
      env.unitTrails[readIdx].countdown -= 1
      if env.unitTrails[readIdx].countdown > 0:
        # Update position based on velocity (slight drift)
        env.unitTrails[readIdx].pos.x += env.unitTrails[readIdx].velocity.x
        env.unitTrails[readIdx].pos.y += env.unitTrails[readIdx].velocity.y
        # Trails settle quickly (reduce drift)
        env.unitTrails[readIdx].velocity.x *= 0.9
        env.unitTrails[readIdx].velocity.y *= 0.9
        env.unitTrails[writeIdx] = env.unitTrails[readIdx]
        inc writeIdx
    env.unitTrails.setLen(writeIdx)

proc stepDecayWaterRipples(env: Environment) =
  ## Decay and remove expired water ripples.
  ## Ripples expand and fade over time.
  if env.waterRipples.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.waterRipples.len:
      env.waterRipples[readIdx].countdown -= 1
      if env.waterRipples[readIdx].countdown > 0:
        env.waterRipples[writeIdx] = env.waterRipples[readIdx]
        inc writeIdx
    env.waterRipples.setLen(writeIdx)

proc stepDecayActionTints(env: Environment) =
  ## Decay short-lived action tints, removing expired ones
  if env.actionTintPositions.len > 0:
    var writeIdx = 0
    for readIdx in 0 ..< env.actionTintPositions.len:
      let pos = env.actionTintPositions[readIdx]
      if not isValidPos(pos):
        continue
      let x = pos.x
      let y = pos.y
      let countdown = env.actionTintCountdown[x][y]
      if countdown > 0:
        let next = countdown - 1
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

proc stepDecayShields(env: Environment) =
  ## Decay shield countdown timers for all agents
  for i in 0 ..< MapAgents:
    if env.shieldCountdown[i] > 0:
      env.shieldCountdown[i] = env.shieldCountdown[i] - 1

proc stepTryTowerAttack(env: Environment, tower: Thing, range: int,
                        towerRemovals: var seq[Thing]) =
  ## Have a tower attack the nearest valid target in range.
  ## University techs affect tower behavior:
  ## - Murder Holes: Allow attacking adjacent units (min range 0 instead of 1)
  ## - Arrowslits: +1 attack damage for towers
  ## - Heated Shot: +2 damage vs boats
  if tower.teamId < 0:
    return

  # Murder Holes: allow attacking adjacent units (distance 1)
  # Without Murder Holes, towers have a "dead zone" at distance 1 (can't attack adjacent)
  let hasMurderHoles = env.hasUniversityTech(tower.teamId, TechMurderHoles)
  let minRange = if hasMurderHoles: 1 else: 2

  # Use spatial index for enemy agent lookup instead of scanning all agents
  var bestTarget = findNearestEnemyInRangeSpatial(env, tower.pos, tower.teamId, minRange, range)
  var bestDist = if bestTarget.isNil: int.high
                 else: chebyshevDist(bestTarget.pos, tower.pos).int
  # Use spatial query for Tumor/Spawner targets instead of O(n) scan
  for kind in [Tumor, Spawner]:
    let nearest = findNearestThingSpatial(env, tower.pos, kind, range)
    if not nearest.isNil:
      let dist = chebyshevDist(nearest.pos, tower.pos).int
      if dist >= minRange and dist < bestDist:
        bestDist = dist
        bestTarget = nearest
  if isNil(bestTarget):
    return
  let tint = if tower.kind == Castle: CastleAttackTint else: TowerAttackTint
  let tintCode = if tower.kind == Castle: ActionTintAttackCastle else: ActionTintAttackTower
  let tintDuration = if tower.kind == Castle: CastleAttackTintDuration else: TowerAttackTintDuration
  env.applyActionTint(bestTarget.pos, tint, tintDuration, tintCode)
  let projKind = if tower.kind == Castle: ProjCastleArrow else: ProjTowerArrow
  env.spawnProjectile(tower.pos, bestTarget.pos, projKind)

  # Calculate tower damage with University tech bonuses
  var damage = tower.attackDamage

  # Arrowslits: +1 tower attack damage (only for GuardTower, not Castle)
  if tower.kind == GuardTower and env.hasUniversityTech(tower.teamId, TechArrowslits):
    damage += 1

  # Castle unique tech bonuses for tower/castle attack
  # Crenellations (Team 1 Imperial): +2 castle attack
  if tower.kind == Castle and env.hasCastleTech(tower.teamId, CastleTechCrenellations):
    damage += 2
  # Crenellations2 (Team 4 Imperial): +2 castle attack
  if tower.kind == Castle and env.hasCastleTech(tower.teamId, CastleTechCrenellations2):
    damage += 2
  # Artillery (Team 7 Imperial): +2 tower and castle attack
  if tower.kind in {GuardTower, Castle} and env.hasCastleTech(tower.teamId, CastleTechArtillery):
    damage += 2

  # Apply damage to base target (nearest enemy)
  template applyTowerHit(target: Thing) =
    case target.kind
    of Agent:
      var targetDamage = damage
      # Heated Shot: +2 damage vs boats
      if target.isWaterUnit and env.hasUniversityTech(tower.teamId, TechHeatedShot):
        targetDamage += 2
      # Greek Fire (Team 2 Castle): +2 tower attack vs siege
      if target.unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet} and
          env.hasCastleTech(tower.teamId, CastleTechGreekFire):
        targetDamage += 2
      when defined(combatAudit):
        let towerDmg = max(1, targetDamage)
        let tgtTeam = getTeamId(target)
        recordDamage(env.currentStep, tower.teamId, tgtTeam, -1, target.agentId,
                     towerDmg, $tower.kind, $target.unitClass, "tower")
        let died = env.applyAgentDamage(target, max(1, targetDamage))
        if died:
          recordKill(env.currentStep, tower.teamId, getTeamId(target.agentId),
                     -1, target.agentId, $tower.kind, $target.unitClass)
      else:
        discard env.applyAgentDamage(target, max(1, targetDamage))
    of Tumor, Spawner:
      if target notin towerRemovals:
        towerRemovals.add(target)
    else:
      discard

  applyTowerHit(bestTarget)

  # Garrisoned units add extra arrows to building attacks (round-robin across all targets)
  let garrisonCount = tower.garrisonedUnits.len
  if garrisonCount > 0:
    let bonusArrows = garrisonCount * GarrisonArrowBonus
    # Reuse env temp buffer to avoid per-call heap allocation
    env.tempTowerTargets.setLen(0)
    collectEnemiesInRangeSpatial(env, tower.pos, tower.teamId, range, env.tempTowerTargets)
    # Filter by minRange in-place (swap-and-pop) to avoid second allocation
    if minRange > 1:
      var i = 0
      while i < env.tempTowerTargets.len:
        if chebyshevDist(env.tempTowerTargets[i].pos, tower.pos) < minRange:
          env.tempTowerTargets[i] = env.tempTowerTargets[^1]
          env.tempTowerTargets.setLen(env.tempTowerTargets.len - 1)
        else:
          inc i
    # Use spatial query for Tumor/Spawner targets instead of O(n) scan
    for kind in [Tumor, Spawner]:
      collectThingsInRangeSpatial(env, tower.pos, kind, range, env.tempTowerTargets)
    # Filter Tumor/Spawner by minRange after collection (spatial query doesn't support minRange)
    if minRange > 1 and env.tempTowerTargets.len > 0:
      var i = 0
      while i < env.tempTowerTargets.len:
        if env.tempTowerTargets[i].kind in {Tumor, Spawner} and
           chebyshevDist(env.tempTowerTargets[i].pos, tower.pos) < minRange:
          env.tempTowerTargets[i] = env.tempTowerTargets[^1]
          env.tempTowerTargets.setLen(env.tempTowerTargets.len - 1)
        else:
          inc i
    if env.tempTowerTargets.len > 0:
      for i in 0 ..< bonusArrows:
        let bonusTarget = env.tempTowerTargets[i mod env.tempTowerTargets.len]
        # Skip targets killed by earlier arrows in this volley
        if bonusTarget.kind == Agent and not isAgentAlive(env, bonusTarget):
          continue
        env.applyActionTint(bonusTarget.pos, tint, tintDuration, tintCode)
        env.spawnProjectile(tower.pos, bonusTarget.pos, projKind)
        applyTowerHit(bonusTarget)

proc stepTryTownCenterAttack(env: Environment, tc: Thing,
                              towerRemovals: var seq[Thing]) =
  ## Have a Town Center attack enemies in range. Garrisoned units add extra arrows.
  ## Each garrisoned unit fires one additional arrow at a unique target.
  if tc.teamId < 0:
    return

  # Gather all valid targets in range using spatial index
  # Reuse env temp buffer to avoid per-call heap allocation
  env.tempTCTargets.setLen(0)
  collectEnemiesInRangeSpatial(env, tc.pos, tc.teamId, TownCenterRange, env.tempTCTargets)
  # Use spatial query for Tumor/Spawner targets instead of O(n) scan
  for kind in [Tumor, Spawner]:
    collectThingsInRangeSpatial(env, tc.pos, kind, TownCenterRange, env.tempTCTargets)

  if env.tempTCTargets.len == 0:
    return

  # Calculate number of arrows: base damage + 1 per garrisoned unit
  let garrisonCount = tc.garrisonedUnits.len
  let arrowCount = 1 + garrisonCount * GarrisonArrowBonus

  # Fire arrows at targets (round-robin if more arrows than targets)
  for i in 0 ..< arrowCount:
    let targetIdx = i mod env.tempTCTargets.len
    let target = env.tempTCTargets[targetIdx]
    # Skip targets killed by earlier arrows in this volley
    if target.kind == Agent and not isAgentAlive(env, target):
      continue
    env.applyActionTint(target.pos, TownCenterAttackTint, TownCenterAttackTintDuration,
                        ActionTintAttackTower)
    env.spawnProjectile(tc.pos, target.pos, ProjTowerArrow)
    case target.kind
    of Agent:
      when defined(combatAudit):
        let tcDmg = max(1, tc.attackDamage)
        let tcTgtTeam = getTeamId(target)
        recordDamage(env.currentStep, tc.teamId, tcTgtTeam, -1, target.agentId,
                     tcDmg, "TownCenter", $target.unitClass, "tower")
        let tcDied = env.applyAgentDamage(target, max(1, tc.attackDamage))
        if tcDied:
          recordKill(env.currentStep, tc.teamId, getTeamId(target.agentId),
                     -1, target.agentId, "TownCenter", $target.unitClass)
      else:
        discard env.applyAgentDamage(target, max(1, tc.attackDamage))
    of Tumor, Spawner:
      if target notin towerRemovals:
        towerRemovals.add(target)
    else:
      discard

proc garrisonCapacity*(kind: ThingKind): int =
  ## Returns the garrison capacity for a building type, or 0 if it cannot garrison.
  case kind
  of TownCenter: TownCenterGarrisonCapacity
  of Castle: CastleGarrisonCapacity
  of GuardTower: GuardTowerGarrisonCapacity
  of House: HouseGarrisonCapacity
  else: 0

proc garrisonUnitInBuilding*(env: Environment, unit: Thing, building: Thing): bool =
  ## Garrison a unit inside a building. Returns true if successful.
  let capacity = garrisonCapacity(building.kind)
  if capacity == 0:
    return false
  if building.garrisonedUnits.len >= capacity:
    return false
  if not isAgentAlive(env, unit):
    return false
  if getTeamId(unit) != building.teamId:
    return false

  # Remove unit from the grid
  env.grid[unit.pos.x][unit.pos.y] = nil
  env.updateObservations(AgentLayer, unit.pos, 0)
  env.updateObservations(AgentOrientationLayer, unit.pos, 0)

  # Add to garrison
  building.garrisonedUnits.add(unit)
  unit.pos = ivec2(-1, -1)  # Mark as off-grid
  unit.isGarrisoned = true
  true

proc ungarrisonAllUnits*(env: Environment, building: Thing): seq[Thing] =
  ## Ungarrison all units from a building, placing them around it. Returns ungarrisoned units.
  result = newSeqOfCap[Thing](building.garrisonedUnits.len)
  if building.garrisonedUnits.len == 0:
    return

  # Find empty tiles around the building (5x5 grid minus center = 24 max)
  # Reuse env temp buffer to avoid per-call heap allocation
  env.tempEmptyTiles.setLen(0)
  for dy in -2 .. 2:
    for dx in -2 .. 2:
      if dx == 0 and dy == 0:
        continue
      let pos = building.pos + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if not env.isEmpty(pos):
        continue
      if env.terrain[pos.x][pos.y] == Water:
        continue
      env.tempEmptyTiles.add(pos)

  var tileIdx = 0
  for unit in building.garrisonedUnits:
    if tileIdx >= env.tempEmptyTiles.len:
      break  # No more space, remaining units stay garrisoned
    let pos = env.tempEmptyTiles[tileIdx]
    unit.pos = pos
    unit.isGarrisoned = false
    env.grid[pos.x][pos.y] = unit
    env.updateObservations(AgentLayer, pos, getTeamId(unit) + 1)
    env.updateObservations(AgentOrientationLayer, pos, unit.orientation.int)
    result.add(unit)
    inc tileIdx

  # Remove ungarrisoned units from the list
  building.garrisonedUnits = building.garrisonedUnits[result.len .. ^1]

proc stepApplySurvivalPenalty(env: Environment) =
  ## Apply per-step survival penalty to all living agents
  if env.config.survivalPenalty != 0.0:
    let penalty = env.config.survivalPenalty
    when defined(rewardBatch):
      # Batch: apply penalty to contiguous rewards array for SIMD-friendly access
      for i in 0 ..< MapAgents:
        if env.terminated[i] == 0.0 and env.truncated[i] == 0.0:
          env.rewards[i] += penalty
    else:
      for agent in env.agents:
        if isAgentAlive(env, agent):
          env.rewards[agent.agentId] += penalty

proc stepApplyTankAuras(env: Environment) =
  ## Apply tank (ManAtArms/Knight) aura tints to nearby tiles
  ## Optimized: iterates only tankUnits collection instead of all agents
  for tank in env.tankUnits:
    if not isAgentAlive(env, tank):
      continue
    if isThingFrozen(tank, env):
      continue
    let radius = UnitAuraRadius[tank.unitClass]
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        let pos = tank.pos + ivec2(dx.int32, dy.int32)
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

proc stepApplyMonkAuras(env: Environment) =
  ## Apply monk aura tints and heal nearby allies
  ## Optimized: iterates only monkUnits collection instead of all agents
  for monk in env.monkUnits:
    if not isAgentAlive(env, monk):
      continue
    if isThingFrozen(monk, env):
      continue
    let teamId = getTeamId(monk)
    # Use spatial index to find nearby allies - reuse pre-allocated buffer
    env.tempMonkAuraAllies.setLen(0)
    collectAlliesInRangeSpatial(env, monk.pos, teamId, MonkAuraRadius, env.tempMonkAuraAllies)
    # Single-pass: collect allies that need healing (avoids redundant iteration)
    env.tempMonkHealTargets.setLen(0)
    for ally in env.tempMonkAuraAllies:
      if ally.hp < ally.maxHp and not isThingFrozen(ally, env):
        env.tempMonkHealTargets.add(ally)
    if env.tempMonkHealTargets.len == 0:
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

    # Apply healing to pre-filtered targets (no redundant condition checks)
    for ally in env.tempMonkHealTargets:
      ally.hp = min(ally.maxHp, ally.hp + 1)

proc stepRechargeMonkFaith(env: Environment) =
  ## Regenerate faith for monks over time (AoE2-style faith recharge)
  ## Optimized: iterates only monkUnits collection instead of all agents
  for monk in env.monkUnits:
    if not isAgentAlive(env, monk):
      continue
    if isThingFrozen(monk, env):
      continue
    if monk.faith < MonkMaxFaith:
      monk.faith = min(MonkMaxFaith, monk.faith + MonkFaithRechargeRate)

proc isOutOfBounds(pos: IVec2): bool {.inline.} =
  ## Check if position is outside the playable map area (within border margin)
  pos.x < MapBorder.int32 or pos.x >= (MapWidth - MapBorder).int32 or
  pos.y < MapBorder.int32 or pos.y >= (MapHeight - MapBorder).int32

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

proc applyFertileRadius(env: Environment, center: IVec2, radius: int) =
  ## Apply fertile terrain in a Chebyshev radius around center, skipping blocked tiles
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue
      if max(abs(dx), abs(dy)) > radius:
        continue
      let pos = center + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if not env.isEmpty(pos) or env.hasDoor(pos) or
         isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
        continue
      let terrain = env.terrain[pos.x][pos.y]
      if terrain notin BuildableTerrain:
        continue
      env.terrain[pos.x][pos.y] = Fertile
      env.resetTileColor(pos)
      env.updateObservations(ThingAgentLayer, pos, 0)

# ============================================================================
# Victory Conditions (AoE2-style)
# ============================================================================

proc teamHasUnitsOrBuildings(env: Environment, teamId: int): bool =
  ## Check if a team has any living agents or owned buildings.
  for agent in env.agents:
    if agent.isNil:
      continue
    if getTeamId(agent) == teamId and isAgentAlive(env, agent):
      return true
  for kind in TeamOwnedKinds:
    if kind == Agent:
      continue
    for thing in env.thingsByKind[kind]:
      if not thing.isNil and thing.teamId == teamId:
        return true
  false

proc checkConquestVictory(env: Environment): int =
  ## Returns the winning team ID if only one team remains, else -1.
  var survivingTeam = -1
  var survivingCount = 0
  for teamId in 0 ..< MapRoomObjectsTeams:
    if env.teamHasUnitsOrBuildings(teamId):
      survivingTeam = teamId
      inc survivingCount
      if survivingCount > 1:
        return -1  # Multiple teams alive, no winner
  if survivingCount == 1:
    return survivingTeam
  -1

proc checkWonderVictory(env: Environment): int =
  ## Returns the winning team ID if a Wonder has survived its countdown, else -1.
  for teamId in 0 ..< MapRoomObjectsTeams:
    let builtStep = env.victoryStates[teamId].wonderBuiltStep
    if builtStep >= 0:
      # Check if the Wonder still exists
      var wonderAlive = false
      for wonder in env.thingsByKind[Wonder]:
        if not wonder.isNil and wonder.teamId == teamId:
          wonderAlive = true
          break
      if wonderAlive:
        if env.currentStep - builtStep >= WonderVictoryCountdown:
          return teamId
      else:
        # Wonder was destroyed, reset countdown
        env.victoryStates[teamId].wonderBuiltStep = -1
  -1

proc checkRelicVictory(env: Environment): int =
  ## Returns the winning team ID if one team holds all relics long enough, else -1.
  ## A relic is "held" when garrisoned in a Monastery.
  if TotalRelicsOnMap <= 0:
    return -1
  # Count garrisoned relics per team
  var teamRelics: array[MapRoomObjectsTeams, int]
  for monastery in env.thingsByKind[Monastery]:
    if monastery.isNil:
      continue
    let teamId = monastery.teamId
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      teamRelics[teamId] += monastery.garrisonedRelics
  # Check if any team holds all relics
  for teamId in 0 ..< MapRoomObjectsTeams:
    if teamRelics[teamId] >= TotalRelicsOnMap:
      let holdStart = env.victoryStates[teamId].relicHoldStartStep
      if holdStart < 0:
        env.victoryStates[teamId].relicHoldStartStep = env.currentStep
      elif env.currentStep - holdStart >= RelicVictoryCountdown:
        return teamId
    else:
      # Reset hold timer if not holding all relics
      env.victoryStates[teamId].relicHoldStartStep = -1
  -1

proc checkRegicideVictory(env: Environment): int =
  ## Returns winning team ID if only one team's king survives, else -1.
  ## Teams without a king assigned are ignored (not playing regicide).
  var survivingTeam = -1
  var survivingCount = 0
  var participatingTeams = 0
  for teamId in 0 ..< MapRoomObjectsTeams:
    let kingId = env.victoryStates[teamId].kingAgentId
    if kingId < 0:
      continue  # Team has no king, not participating
    inc participatingTeams
    if isAgentAlive(env, env.agents[kingId]):
      survivingTeam = teamId
      inc survivingCount
      if survivingCount > 1:
        return -1  # Multiple kings alive
  if participatingTeams < 2:
    return -1  # Need at least 2 teams with kings
  if survivingCount == 1:
    return survivingTeam
  -1

proc checkKingOfTheHillVictory(env: Environment): int =
  ## Returns the winning team ID if a team has controlled the hill for long enough, else -1.
  ## Control means having the most living units within HillControlRadius of a ControlPoint.
  ## If tied (multiple teams have the same max count), the hill is contested and no one controls.
  for cp in env.thingsByKind[ControlPoint]:
    if cp.isNil:
      continue
    # Count living agents per team within the control radius using spatial query
    var teamUnits: array[MapRoomObjectsTeams, int]
    # Reuse tower targets buffer for control point agents (not used simultaneously)
    env.tempTowerTargets.setLen(0)
    collectThingsInRangeSpatial(env, cp.pos, Agent, HillControlRadius, env.tempTowerTargets)
    for agent in env.tempTowerTargets:
      if not isAgentAlive(env, agent):
        continue
      let teamId = getTeamId(agent)
      if teamId >= 0 and teamId < MapRoomObjectsTeams:
        inc teamUnits[teamId]
    # Find the team with the most units (must be unique max and > 0)
    var bestTeam = -1
    var bestCount = 0
    var tied = false
    for teamId in 0 ..< MapRoomObjectsTeams:
      if teamUnits[teamId] > bestCount:
        bestTeam = teamId
        bestCount = teamUnits[teamId]
        tied = false
      elif teamUnits[teamId] == bestCount and bestCount > 0:
        tied = true
    if tied or bestTeam < 0:
      # Contested or empty - reset all timers
      for teamId in 0 ..< MapRoomObjectsTeams:
        env.victoryStates[teamId].hillControlStartStep = -1
    else:
      # bestTeam controls the hill
      if env.victoryStates[bestTeam].hillControlStartStep < 0:
        env.victoryStates[bestTeam].hillControlStartStep = env.currentStep
      elif env.currentStep - env.victoryStates[bestTeam].hillControlStartStep >= HillVictoryCountdown:
        return bestTeam
      # Reset all other teams
      for teamId in 0 ..< MapRoomObjectsTeams:
        if teamId != bestTeam:
          env.victoryStates[teamId].hillControlStartStep = -1
  -1

proc updateWonderTracking(env: Environment) =
  ## Track when Wonders are first fully constructed (for countdown).
  ## Only starts countdown when wonder reaches full HP (construction complete).
  for teamId in 0 ..< MapRoomObjectsTeams:
    if env.victoryStates[teamId].wonderBuiltStep >= 0:
      continue  # Already tracking
    for wonder in env.thingsByKind[Wonder]:
      if not wonder.isNil and wonder.teamId == teamId and
          wonder.maxHp > 0 and wonder.hp >= wonder.maxHp:
        env.victoryStates[teamId].wonderBuiltStep = env.currentStep
        break

proc checkVictoryConditions(env: Environment) =
  ## Check all active victory conditions and set victoryWinner if met.
  let cond = env.config.victoryCondition

  # Update Wonder tracking regardless of condition
  if cond in {VictoryWonder, VictoryAll}:
    env.updateWonderTracking()

  # Conquest check
  if cond in {VictoryConquest, VictoryAll}:
    let winner = env.checkConquestVictory()
    if winner >= 0:
      env.victoryWinner = winner
      return

  # Wonder check
  if cond in {VictoryWonder, VictoryAll}:
    let winner = env.checkWonderVictory()
    if winner >= 0:
      env.victoryWinner = winner
      return

  # Relic check
  if cond in {VictoryRelic, VictoryAll}:
    let winner = env.checkRelicVictory()
    if winner >= 0:
      env.victoryWinner = winner
      return

  # Regicide check
  if cond in {VictoryRegicide, VictoryAll}:
    let winner = env.checkRegicideVictory()
    if winner >= 0:
      env.victoryWinner = winner
      return

  # King of the Hill check
  if cond in {VictoryKingOfTheHill, VictoryAll}:
    let winner = env.checkKingOfTheHillVictory()
    if winner >= 0:
      env.victoryWinner = winner
      return

proc stepProcessTumors(env: Environment, tumorsToProcess: seq[Thing],
                       newTumorsToSpawn: seq[Thing],
                       stepRng: var Rand) =
  ## Process tumor branching and add all newly spawned tumors to the environment.
  ## Handles both spawner-created tumors (newTumorsToSpawn) and branch tumors.
  # Use arena buffer for temporary collection (reuses pre-allocated capacity)
  var newTumorBranches = addr env.arena.things3
  newTumorBranches[].setLen(0)

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

proc step*(env: Environment, actions: ptr array[MapAgents, uint8]) =
  ## Step the environment
  when defined(stepTiming):
    let perStepTiming = stepTimingTarget >= 0 and env.currentStep >= stepTimingTarget and
      env.currentStep <= stepTimingTarget + stepTimingWindow
    let aggregateTiming = stepTimingInterval > 0
    let timing = perStepTiming or aggregateTiming
    var tStart: MonoTime
    var tNow: MonoTime
    var tTotalStart: MonoTime
    var tActionTintMs: float64
    var tShieldsMs: float64
    var tPreDeathsMs: float64
    var tActionsMs: float64
    var tThingsMs: float64
    var tTumorsMs: float64
    var tTumorDamageMs: float64
    var tAurasMs: float64
    var tPopRespawnMs: float64
    var tSurvivalMs: float64
    var tTintMs: float64
    var tEndMs: float64

    if timing:
      tStart = getMonoTime()
      tTotalStart = tStart

  when defined(perfRegression):
    ensurePerfInit()
    var prfStart = getMonoTime()
    var prfNow: MonoTime
    var prfTotalStart = prfStart
    var prfSubsystems: array[PerfSubsystemCount, float64]

  when defined(flameGraph):
    ensureFlameInit()
    var fgStart = getMonoTime()
    var fgNow: MonoTime
    var fgTotalStart = fgStart
    var fgSubsystems: array[FlameSubsystemCount, int64]

  when defined(combatAudit):
    ensureCombatAuditInit()


  when defined(actionAudit):
    ensureActionAuditInit()

  when defined(actionFreqCounter):
    ensureActionFreqInit()

  when defined(stateDiff):
    capturePreStep(env)

  # Reset arena allocator for this step's temporary allocations
  env.arena.reset()

  # Decay short-lived action tints, projectile visuals, damage numbers, ragdolls, and debris particles
  env.stepDecayActionTints()
  env.stepDecayProjectiles()
  env.stepDecayDamageNumbers()
  env.stepRagdolls()
  env.stepDecayDebris()
  env.stepDecaySpawnEffects()
  env.stepDecayDyingUnits()
  env.stepDecayGatherSparkles()
  env.stepDecayConstructionDust()
  env.stepDecayUnitTrails()
  env.stepDecayWaterRipples()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tActionTintMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[0] = msBetweenPerfTiming(prfStart, prfNow)  # actionTint
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[0] = usBetween(fgStart, fgNow)  # actionTint
    fgStart = fgNow

  # Decay shields
  env.stepDecayShields()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tShieldsMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[1] = msBetweenPerfTiming(prfStart, prfNow)  # shields
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[1] = usBetween(fgStart, fgNow)  # shields
    fgStart = fgNow

  # Remove any agents that already hit zero HP so they can't act this step
  env.enforceZeroHpDeaths()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tPreDeathsMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[2] = msBetweenPerfTiming(prfStart, prfNow)  # preDeaths
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[2] = usBetween(fgStart, fgNow)  # preDeaths
    fgStart = fgNow

  inc env.currentStep

  # AoE2-style market price equilibrium: drift prices toward base rate periodically
  if env.currentStep mod MarketPriceDecayInterval == 0:
    env.decayMarketPrices()

  # Periodically tune spatial index bucket size based on unit density
  when defined(spatialAutoTune):
    env.maybeTuneSpatialIndex(env.currentStep)

  # Single RNG for entire step - XOR gameSeed for variation across different games.
  # Without gameSeed, all games at the same step have identical agent ordering.
  var stepRng = initRand(env.gameSeed xor env.currentStep)

  # Track builders per construction site for multi-builder speed bonus
  # Reuse environment's table to avoid per-step heap allocation
  env.constructionBuilders.clear()

  # Pre-compute team pop caps before action processing (for monk conversion)
  # This avoids O(buildings) iteration inside the action loop
  # Also used later for respawning and production building spawning
  for i in 0 ..< MapRoomObjectsTeams:
    env.stepTeamPopCaps[i] = 0
    env.stepTeamPopCounts[i] = 0
  for thing in env.thingsByKind[TownCenter]:
    if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
      env.stepTeamPopCaps[thing.teamId] += TownCenterPopCap
  for thing in env.thingsByKind[House]:
    if thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
      env.stepTeamPopCaps[thing.teamId] += HousePopCap
  # Clamp to agent pool limit
  for i in 0 ..< MapRoomObjectsTeams:
    if env.stepTeamPopCaps[i] > MapAgentsPerTeam:
      env.stepTeamPopCaps[i] = MapAgentsPerTeam
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let teamId = getTeamId(agent)
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      inc env.stepTeamPopCounts[teamId]

  # Shuffle agent processing order to prevent Team 0 from always acting first.
  # This ensures fair resource access and combat timing across all teams.
  # Array is initialized once at env creation; we just shuffle in place each step.
  stepRng.shuffle(env.agentOrder)

  for id in env.agentOrder:
    let actionValue = actions[id]
    let agent = env.agents[id]
    if not isAgentAlive(env, agent):
      continue

    let verb = actionValue.int div ActionArgumentCount
    let argument = actionValue.int mod ActionArgumentCount

    # Track idle state: agent is idle if taking NOOP (0) or ORIENT (9) action
    # This enables AoE2-style idle villager detection for RL agents
    agent.isIdle = verb == 0 or verb == 9

    when defined(actionAudit):
      recordAction(id, verb)

    when defined(actionFreqCounter):
      recordActionByUnitType(id, verb, agent.unitClass)

    template invalidAndBreak(label: untyped) =
      inc env.stats[id].actionInvalid
      break label

    case verb:
    of 0:
      inc env.stats[id].actionNoop
    of 1:
      block moveAction:
        # Trebuchets cannot move when unpacked or while packing/unpacking
        if agent.unitClass == UnitTrebuchet:
          if not agent.packed or agent.cooldown > 0:
            invalidAndBreak(moveAction)

        # Check terrain movement debt - agents with debt >= 1.0 skip their move
        if agent.movementDebt >= 1.0'f32:
          agent.movementDebt -= 1.0'f32
          agent.orientation = Orientation(argument)  # Still update orientation
          env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
          break moveAction  # Skip movement but don't count as invalid

        let moveOrientation = Orientation(argument)
        let delta = orientationToVec(moveOrientation)
        let step1 = agent.pos + delta

        if not isValidPos(step1) or isOutOfBounds(step1):
          invalidAndBreak(moveAction)
        if not env.canTraverseElevation(agent.pos, step1):
          invalidAndBreak(moveAction)
        if env.isWaterBlockedForAgent(agent, step1):
          invalidAndBreak(moveAction)
        if not env.canAgentPassDoor(agent, step1):
          inc env.stats[id].actionInvalid
          break moveAction

        # Allow walking through planted lanterns by relocating the lantern, preferring push direction (up to 2 tiles ahead)
        proc canEnterFrom(fromPos, pos: IVec2): bool =
          if not isValidPos(pos) or isOutOfBounds(pos):
            return false
          if not env.canTraverseElevation(fromPos, pos):
            return false
          var canMove = env.isEmpty(pos)
          if canMove:
            return true
          let blocker = env.getThing(pos)
          if blocker.kind != Lantern:
            return false

          var relocated = false
          # Helper to ensure lantern spacing (Chebyshev >= 3 from other lanterns)
          # Uses spatial query with pre-allocated buffer to avoid heap allocations
          template spacingOk(nextPos: IVec2): bool =
            var isSpaced = true
            env.tempLanternSpacing.setLen(0)
            collectThingsInRangeSpatial(env, nextPos, Lantern, 2, env.tempLanternSpacing)
            for t in env.tempLanternSpacing:
              if t != blocker:
                isSpaced = false
                break
            isSpaced
          # Preferred push positions in move direction
          let ahead1 = pos + delta
          let ahead2 = pos + ivec2(delta.x * 2'i32, delta.y * 2'i32)
          let blockerOldPos = blocker.pos
          if isValidPos(ahead2) and not isOutOfBounds(ahead2) and
              env.isEmpty(ahead2) and not env.hasDoor(ahead2) and
              not env.isWaterBlockedForAgent(agent, ahead2) and spacingOk(ahead2):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = ahead2
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            updateSpatialIndex(env, blocker, blockerOldPos)
            relocated = true
          elif isValidPos(ahead1) and not isOutOfBounds(ahead1) and
              env.isEmpty(ahead1) and not env.hasDoor(ahead1) and
              not env.isWaterBlockedForAgent(agent, ahead1) and spacingOk(ahead1):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = ahead1
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            updateSpatialIndex(env, blocker, blockerOldPos)
            relocated = true
          # Fallback to any adjacent empty tile around the lantern
          if not relocated:
            for dy in -1 .. 1:
              for dx in -1 .. 1:
                if dx == 0 and dy == 0:
                  continue
                let alt = ivec2(pos.x + dx, pos.y + dy)
                if not isValidPos(alt) or isOutOfBounds(alt):
                  continue
                if env.isEmpty(alt) and not env.hasDoor(alt) and
                    not env.isWaterBlockedForAgent(agent, alt) and spacingOk(alt):
                  env.grid[blocker.pos.x][blocker.pos.y] = nil
                  blocker.pos = alt
                  env.grid[blocker.pos.x][blocker.pos.y] = blocker
                  updateSpatialIndex(env, blocker, blockerOldPos)
                  relocated = true
                  break
              if relocated:
                break
          return relocated

        let isCavalry = agent.unitClass in CavalryMoveUnits
        let step2 = agent.pos + ivec2(delta.x * 2'i32, delta.y * 2'i32)

        var finalPos = step1
        if not canEnterFrom(agent.pos, step1):
          let blocker = env.getThing(step1)
          if not isNil(blocker):
            if blocker.kind == Agent and not isThingFrozen(blocker, env) and
                getTeamId(blocker) == getTeamId(agent):
              let agentOld = agent.pos
              let blockerOld = blocker.pos
              agent.pos = blockerOld
              blocker.pos = agentOld
              env.grid[agentOld.x][agentOld.y] = blocker
              env.grid[blockerOld.x][blockerOld.y] = agent
              updateSpatialIndex(env, agent, agentOld)
              updateSpatialIndex(env, blocker, blockerOld)
              agent.orientation = moveOrientation
              env.updateObservations(AgentLayer, agentOld, getTeamId(blocker) + 1)
              env.updateObservations(AgentLayer, blockerOld, getTeamId(agent) + 1)
              env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
              env.updateObservations(AgentOrientationLayer, blocker.pos, blocker.orientation.int)
              inc env.stats[id].actionMove
              break moveAction
            if blocker.kind in {Tree} and not isThingFrozen(blocker, env):
              if env.harvestTree(agent, blocker):
                inc env.stats[id].actionUse
                break moveAction
          inc env.stats[id].actionInvalid
          break moveAction

        if isCavalry:
          if isValidPos(step2) and
              not env.isWaterBlockedForAgent(agent, step2) and env.canAgentPassDoor(agent, step2):
            if canEnterFrom(step1, step2):
              finalPos = step2
        else:
          # Roads and ramps accelerate movement in the direction of entry.
          let step1Terrain = env.terrain[step1.x][step1.y]
          if step1Terrain == Road or isRampTerrain(step1Terrain):
            if isValidPos(step2) and
                not env.isWaterBlockedForAgent(agent, step2) and env.canAgentPassDoor(agent, step2):
              if canEnterFrom(step1, step2):
                finalPos = step2

        let originalPos = agent.pos  # Save for cliff fall damage check
        env.grid[agent.pos.x][agent.pos.y] = nil
        # Clear old position and set new position
        env.updateObservations(AgentLayer, agent.pos, 0)  # Clear old
        agent.pos = finalPos
        agent.orientation = moveOrientation
        env.grid[agent.pos.x][agent.pos.y] = agent
        updateSpatialIndex(env, agent, originalPos)

        # Spawn dust trail at the position the unit left (not every move to reduce particles)
        if env.currentStep mod UnitTrailSpawnChance == 0:
          env.spawnUnitTrail(originalPos, getTeamId(agent))

        # Spawn water ripple when non-water units enter water terrain
        let terrainAtPos = env.terrain[agent.pos.x][agent.pos.y]
        if terrainAtPos in WaterTerrain and not agent.isWaterUnit:
          env.spawnWaterRipple(agent.pos)

        let dockHere = env.hasDockAt(agent.pos)
        if agent.unitClass == UnitTradeCog:
          # Trade Cogs generate gold when reaching a friendly dock that isn't their home dock
          if dockHere:
            let dockThing = env.getBackgroundThing(agent.pos)
            if not isNil(dockThing) and dockThing.teamId == getTeamId(agent):
              let homeDock = agent.tradeHomeDock
              if homeDock != agent.pos and homeDock != ivec2(0, 0):
                let dist = abs(agent.pos.x - homeDock.x) + abs(agent.pos.y - homeDock.y)
                let goldAmount = max(1, dist div TradeCogDistanceDivisor * TradeCogGoldPerDistance)
                env.addToStockpile(getTeamId(agent), ResourceGold, goldAmount)
                when defined(econAudit):
                  recordTradeShipGold(getTeamId(agent), goldAmount, env.currentStep)
                agent.tradeHomeDock = agent.pos  # Flip home dock for return trip
        elif agent.unitClass == UnitBoat:
          if dockHere or env.terrain[agent.pos.x][agent.pos.y] != Water:
            disembarkAgent(agent)
        elif dockHere:
          embarkAgent(agent)

        # Update observations for new position only
        env.updateObservations(AgentLayer, agent.pos, getTeamId(agent) + 1)
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)

        # Accumulate terrain movement debt (water units are unaffected by terrain penalties)
        if not agent.isWaterUnit:
          let terrainModifier = getTerrainSpeedModifier(env.terrain[agent.pos.x][agent.pos.y])
          if terrainModifier < 1.0'f32:
            var penalty = 1.0'f32 - terrainModifier
            # Villager speed bonus reduces terrain penalty (Wheelbarrow/Hand Cart)
            if agent.unitClass == UnitVillager:
              let speedBonus = env.getVillagerSpeedBonus(getTeamId(agent))
              if speedBonus > 0:
                penalty = penalty * (1.0'f32 - speedBonus.float32 / 100.0'f32)
            agent.movementDebt += penalty

        # Apply cliff fall damage when dropping elevation without a ramp/road
        # Check both steps of movement (original→step1 and step1→finalPos if different)
        if not agent.isWaterUnit:
          var fallDamage = 0
          if env.willCauseCliffFallDamage(originalPos, step1):
            fallDamage += CliffFallDamage
          if finalPos != step1 and env.willCauseCliffFallDamage(step1, finalPos):
            fallDamage += CliffFallDamage
          if fallDamage > 0:
            discard env.applyAgentDamage(agent, fallDamage)

        inc env.stats[id].actionMove
    of 2:
      block attackAction:
        ## Attack an entity in the given direction. Spears extend range to 2 tiles.
        if argument > 7:
          invalidAndBreak(attackAction)

        # Trebuchets can only attack when unpacked and not in packing/unpacking transition
        if agent.unitClass == UnitTrebuchet:
          if agent.packed or agent.cooldown > 0:
            invalidAndBreak(attackAction)

        let attackOrientation = Orientation(argument)
        agent.orientation = attackOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = orientationToVec(attackOrientation)
        let attackerTeam = getTeamId(agent)
        var damageAmount = max(1, agent.attackDamage)

        # Ballistics: +1 damage for ranged units (better accuracy = more effective shots)
        if agent.unitClass in BallisticsUnits and
           attackerTeam >= 0 and env.hasUniversityTech(attackerTeam, TechBallistics):
          damageAmount += 1

        var rangedRange = UnitRangedRange[agent.unitClass]

        # Siege Engineers: +1 range for siege units
        if agent.unitClass in SiegeUnits and
           attackerTeam >= 0 and env.hasUniversityTech(attackerTeam, TechSiegeEngineers):
          if rangedRange > 0:
            rangedRange += 1
        let hasSpear = agent.inventorySpear > 0 and rangedRange == 0
        let maxRange = if hasSpear: 2 else: 1

        proc tryHitAt(pos: IVec2): bool =
          if not isValidPos(pos):
            return false
          let door = env.getBackgroundThing(pos)
          if not isNil(door) and door.kind == Door and door.teamId != attackerTeam:
            discard env.applyStructureDamage(door, damageAmount, agent)
            return true
          let structure = env.getThing(pos)
          if not isNil(structure) and structure.kind in AttackableStructures:
            if structure.teamId != attackerTeam:
              discard env.applyStructureDamage(structure, damageAmount, agent)
              return true
          var target = env.getThing(pos)
          if isNil(target):
            target = env.getBackgroundThing(pos)
          if isNil(target):
            return false
          case target.kind
          of Tumor:
            removeThing(env, target)
            env.rewards[id] += env.config.tumorKillReward
            return true
          of Spawner:
            removeThing(env, target)
            return true
          of Agent:
            if target.agentId == agent.agentId:
              return false
            if getTeamId(target) == attackerTeam:
              return false
            discard env.applyAgentDamage(target, damageAmount, agent)
            return true
          of Altar:
            if target.teamId == attackerTeam:
              return false
            target.hearts = max(0, target.hearts - 1)
            env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
            if target.hearts == 0:
              let oldTeam = target.teamId
              target.teamId = attackerTeam
              if attackerTeam >= 0 and attackerTeam < env.teamColors.len:
                env.altarColors[target.pos] = env.teamColors[attackerTeam]
              if oldTeam >= 0:
                for door in env.thingsByKind[Door]:
                  if door.teamId == oldTeam:
                    door.teamId = attackerTeam
            return true
          of Cow, Bear, Wolf:
            if not env.giveItem(agent, ItemMeat):
              return false
            # Check if killed wolf is pack leader - scatter the pack
            if target.kind == Wolf and target.isPackLeader:
              let pack = target.packId
              # Clear pack leader tracking
              if pack < env.wolfPackLeaders.len:
                env.wolfPackLeaders[pack] = nil
              # Scatter remaining pack members
              for wolf in env.thingsByKind[Wolf]:
                if wolf.packId == pack and wolf != target:
                  wolf.scatteredSteps = ScatteredDuration
            removeThing(env, target)
            if ResourceNodeInitial > 1:
              let corpse = acquireThing(env, Corpse)
              corpse.pos = pos
              corpse.inventory = emptyInventory()
              setInv(corpse, ItemMeat, ResourceNodeInitial - 1)
              env.add(corpse)
            return true
          of Tree:
            return env.harvestTree(agent, target)
          else:
            return false

        if agent.unitClass == UnitMonk:
          let healPos = agent.pos + delta
          let target = env.getThing(healPos)
          if not isNil(target) and target.kind == Agent:
            if getTeamId(target) == attackerTeam:
              discard env.applyAgentHeal(target, 1, agent)
              env.applyActionTint(healPos, TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1), 2, ActionTintHealMonk)
              inc env.stats[id].actionAttack
            else:
              # Faith check for conversion (AoE2-style)
              if agent.faith < MonkConversionFaithCost:
                inc env.stats[id].actionInvalid
                break attackAction
              let newTeam = attackerTeam
              if newTeam < 0 or newTeam >= MapRoomObjectsTeams:
                inc env.stats[id].actionInvalid
                break attackAction
              # Use pre-computed pop caps/counts (avoids O(buildings+agents) per conversion)
              let popCap = env.stepTeamPopCaps[newTeam]
              let popCount = env.stepTeamPopCounts[newTeam]
              if popCap <= 0 or popCount >= popCap:
                inc env.stats[id].actionInvalid
                break attackAction
              var newHome = ivec2(-1, -1)
              if agent.homeAltar.x >= 0:
                let altarThing = env.getThing(agent.homeAltar)
                if not isNil(altarThing) and altarThing.kind == Altar and
                    altarThing.teamId == newTeam:
                  newHome = agent.homeAltar
              if newHome.x < 0:
                # Use spatial query instead of O(n) scan for nearest team altar
                let nearestAltar = findNearestFriendlyThingSpatial(env, target.pos, newTeam, Altar, 1000)
                if not nearestAltar.isNil:
                  newHome = nearestAltar.pos
              target.homeAltar = newHome
              let defaultTeam = getTeamId(target.agentId)
              if newTeam == defaultTeam:
                target.teamIdOverride = -1
              else:
                target.teamIdOverride = newTeam
              if newTeam < env.teamColors.len:
                env.agentColors[target.agentId] = env.teamColors[newTeam]
              env.updateObservations(AgentLayer, target.pos, newTeam + 1)
              env.applyUnitAttackTint(agent.unitClass, healPos)
              # Consume faith on successful conversion
              agent.faith = agent.faith - MonkConversionFaithCost
              when defined(combatAudit):
                let oldTargetTeam = getTeamId(target.agentId)  # original team before override
                recordConversion(env.currentStep, attackerTeam, oldTargetTeam,
                                 agent.agentId, target.agentId, $target.unitClass)
              when defined(eventLog):
                let oldTargetTeamForLog = getTeamId(target.agentId)
                logConversion(attackerTeam, oldTargetTeamForLog, $target.unitClass, env.currentStep)
              inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass == UnitMangonel:
          # "Large spear" attack: forward line 5 tiles with 1-tile side prongs
          # per siege_fortifications_plan.md section 1.2 and combat.md
          var hit = false
          let left = ivec2(-delta.y, delta.x)
          let right = ivec2(delta.y, -delta.x)
          let offsets = [ivec2(0, 0), left, right]  # 1-tile side prongs
          # Visual projectile to midpoint of AoE area
          let midStep = (MangonelAoELength + 1) div 2
          let mangonelTarget = agent.pos + ivec2(delta.x * midStep.int32, delta.y * midStep.int32)
          env.spawnProjectile(agent.pos, mangonelTarget, ProjMangonel)
          for step in 1 .. MangonelAoELength:
            let forward = agent.pos + ivec2(delta.x * step.int32, delta.y * step.int32)
            for offset in offsets:
              let attackPos = forward + offset
              env.applyUnitAttackTint(agent.unitClass, attackPos)
              if tryHitAt(attackPos):
                hit = true
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if rangedRange > 0:
          var attackHit = false
          # Spawn visual projectile to max range (or first hit)
          let rangedProjKind = case agent.unitClass
            of UnitTrebuchet: ProjTrebuchet
            of UnitLongbowman: ProjLongbow
            of UnitJanissary: ProjJanissary
            else: ProjArrow
          for distance in 1 .. rangedRange:
            let attackPos = agent.pos + ivec2(delta.x * distance.int32, delta.y * distance.int32)
            env.applyUnitAttackTint(agent.unitClass, attackPos)
            if tryHitAt(attackPos):
              env.spawnProjectile(agent.pos, attackPos, rangedProjKind)
              attackHit = true
              break
          if not attackHit:
            # Missed: show arrow flying to max range
            let maxPos = agent.pos + ivec2(delta.x * rangedRange.int32, delta.y * rangedRange.int32)
            env.spawnProjectile(agent.pos, maxPos, rangedProjKind)
          if attackHit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        # Armor overlay (defensive flash)
        if agent.inventoryArmor > 0:
          let tint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.1)
          if abs(delta.x) == 1 and abs(delta.y) == 1:
            let diagPos = agent.pos + ivec2(delta.x, delta.y)
            let xPos = agent.pos + ivec2(delta.x, 0)
            let yPos = agent.pos + ivec2(0, delta.y)
            env.applyActionTint(diagPos, tint, 2, ActionTintShield)
            env.applyActionTint(xPos, tint, 2, ActionTintShield)
            env.applyActionTint(yPos, tint, 2, ActionTintShield)
          else:
            let perp = if delta.x != 0: ivec2(0, 1) else: ivec2(1, 0)
            let forward = agent.pos + ivec2(delta.x, delta.y)
            for offset in -1 .. 1:
              let pos = forward + ivec2(perp.x * offset, perp.y * offset)
              env.applyActionTint(pos, tint, 2, ActionTintShield)
          env.shieldCountdown[agent.agentId] = 2

        # Spear: area strike (3 forward + diagonals)
        if hasSpear:
          var hit = false
          let left = ivec2(-delta.y, delta.x)
          let right = ivec2(delta.y, -delta.x)
          let offsets = [ivec2(0, 0), left, right]
          for step in 1 .. 3:
            let forward = agent.pos + ivec2(delta.x * step, delta.y * step)
            for offset in offsets:
              let attackPos = forward + offset
              env.applyUnitAttackTint(agent.unitClass, attackPos)
              if tryHitAt(attackPos):
                hit = true

          if hit:
            agent.inventorySpear = max(0, agent.inventorySpear - 1)
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass in ChargeAttackUnits:
          var hit = false
          for distance in 1 .. 2:
            let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
            env.applyUnitAttackTint(agent.unitClass, attackPos)
            if tryHitAt(attackPos):
              hit = true
              break
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.isWaterUnit:
          if agent.unitClass == UnitTradeCog:
            # Trade Cogs cannot attack
            inc env.stats[id].actionInvalid
          else:
            var hit = false
            let left = ivec2(-delta.y, delta.x)
            let right = ivec2(delta.y, -delta.x)
            let forward = agent.pos + delta
            for pos in [forward, forward + left, forward + right]:
              env.applyUnitAttackTint(agent.unitClass, pos)
              if tryHitAt(pos):
                hit = true
            if hit:
              inc env.stats[id].actionAttack
            else:
              inc env.stats[id].actionInvalid
          break attackAction

        var attackHit = false

        for distance in 1 .. maxRange:
          let attackPos = agent.pos + ivec2(delta.x * distance.int32, delta.y * distance.int32)
          env.applyUnitAttackTint(agent.unitClass, attackPos)
          if tryHitAt(attackPos):
            attackHit = true
            break

        if attackHit:
          if hasSpear:
            agent.inventorySpear = max(0, agent.inventorySpear - 1)
          inc env.stats[id].actionAttack
        else:
          inc env.stats[id].actionInvalid
    of 3:
      block useAction:
        ## Use terrain or building with a single action in a direction.
        ## Trebuchets: argument 8 triggers pack/unpack toggle.

        # Trebuchet pack/unpack: special argument 8 triggers state toggle
        if agent.unitClass == UnitTrebuchet and argument == 8:
          if agent.cooldown > 0:
            # Already in pack/unpack transition, can't start another
            invalidAndBreak(useAction)
          # Start pack/unpack transition
          agent.cooldown = TrebuchetPackDuration
          # Apply visual tint to show packing/unpacking animation
          let tint = TileColor(r: 0.60, g: 0.40, b: 0.95, intensity: 1.15)
          env.applyActionTint(agent.pos, tint, TrebuchetPackDuration.int8, ActionTintAttackTrebuchet)
          inc env.stats[id].actionUse
          break useAction

        # Ungarrison: argument 9 triggers ungarrison of all units from adjacent garrisonable building
        if argument == 9:
          var foundBuilding: Thing = nil
          for dy in -1 .. 1:
            for dx in -1 .. 1:
              let checkPos = agent.pos + ivec2(dx.int32, dy.int32)
              if not isValidPos(checkPos):
                continue
              let b = env.getThing(checkPos)
              if not b.isNil and garrisonCapacity(b.kind) > 0 and b.teamId == getTeamId(agent):
                foundBuilding = b
                break
            if not foundBuilding.isNil:
              break
          if foundBuilding.isNil:
            invalidAndBreak(useAction)
          let ejected = env.ungarrisonAllUnits(foundBuilding)
          if ejected.len > 0:
            inc env.stats[id].actionUse
          else:
            invalidAndBreak(useAction)
          break useAction

        # Town Bell: argument 10 toggles the town bell for the team
        if argument == 10:
          # Find adjacent TownCenter belonging to agent's team
          var foundTC: Thing = nil
          for dy in -1 .. 1:
            for dx in -1 .. 1:
              let checkPos = agent.pos + ivec2(dx.int32, dy.int32)
              if not isValidPos(checkPos):
                continue
              let tc = env.getThing(checkPos)
              if not tc.isNil and tc.kind == TownCenter and tc.teamId == getTeamId(agent):
                foundTC = tc
                break
            if not foundTC.isNil:
              break
          if foundTC.isNil:
            invalidAndBreak(useAction)
          let teamId = getTeamId(agent)
          if teamId >= 0 and teamId < MapRoomObjectsTeams:
            if env.townBellActive[teamId]:
              # Second press: deactivate bell, ungarrison all team buildings
              env.townBellActive[teamId] = false
              for kind in [TownCenter, Castle, GuardTower, House]:
                for building in env.thingsByKind[kind]:
                  if building.teamId == teamId and building.garrisonedUnits.len > 0:
                    discard env.ungarrisonAllUnits(building)
            else:
              # First press: activate bell, villagers will seek garrison via AI options
              env.townBellActive[teamId] = true
          inc env.stats[id].actionUse
          break useAction

        if argument > 7:
          invalidAndBreak(useAction)
        let useOrientation = Orientation(argument)
        agent.orientation = useOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = orientationToVec(useOrientation)
        let targetPos = agent.pos + delta

        if not isValidPos(targetPos):
          inc env.stats[id].actionInvalid
          break useAction

        # Frozen tiles are non-interactable (terrain or things sitting on them)
        if isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break useAction

        var thing = env.getThing(targetPos)
        if isNil(thing):
          thing = env.getBackgroundThing(targetPos)
        template setInvAndObs(key: ItemKey, value: int) =
          setInv(agent, key, value)
          env.updateAgentInventoryObs(agent, key)

        template decInv(key: ItemKey) =
          setInvAndObs(key, getInv(agent, key) - 1)

        template incInv(key: ItemKey) =
          setInvAndObs(key, getInv(agent, key) + 1)

        if isNil(thing):
          # Terrain use only when no Thing occupies the tile.
          var used = false
          case env.terrain[targetPos.x][targetPos.y]:
          of Water:
            if env.giveItem(agent, ItemWater):
              env.rewards[id] += env.config.waterReward
              used = true
          of Empty, Grass, Dune, Sand, Snow, Road,
             RampUpN, RampUpS, RampUpW, RampUpE,
             RampDownN, RampDownS, RampDownW, RampDownE:
            if env.hasDoor(targetPos):
              used = false
            elif agent.inventoryRelic > 0 and agent.unitClass == UnitMonk:
              let canDrop = env.isEmpty(targetPos) and not env.hasDoor(targetPos) and
                not isTileFrozen(targetPos, env) and env.terrain[targetPos.x][targetPos.y] != Water
              if canDrop:
                let relic = Thing(kind: Relic, pos: targetPos)
                relic.inventory = emptyInventory()
                setInv(relic, ItemGold, 0)
                env.add(relic)
                agent.inventoryRelic = agent.inventoryRelic - 1
                env.updateAgentInventoryObs(agent, ItemRelic)
                used = true
            elif agent.inventoryBread > 0:
              decInv(ItemBread)
              let tint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1)
              for dx in -1 .. 1:
                for dy in -1 .. 1:
                  let pos = agent.pos + ivec2(dx, dy)
                  env.applyActionTint(pos, tint, 2, ActionTintHealBread)
                  let occ = env.getThing(pos)
                  if not occ.isNil and occ.kind == Agent:
                    let healAmt = min(BreadHealAmount, occ.maxHp - occ.hp)
                    if healAmt > 0:
                      discard env.applyAgentHeal(occ, healAmt)
              used = true
            else:
              if agent.inventoryWater > 0:
                decInv(ItemWater)
                env.terrain[targetPos.x][targetPos.y] = Fertile
                env.resetTileColor(targetPos)
                env.updateObservations(TintLayer, targetPos, 0)
                used = true
          else:
            used = false

          if used:
            inc env.stats[id].actionUse
          else:
            inc env.stats[id].actionInvalid
          break useAction
        # Building use
        # Prevent interacting with frozen objects/buildings
        if isThingFrozen(thing, env):
          inc env.stats[id].actionInvalid
          break useAction

        var used = false
        template takeFromThing(key: ItemKey, rewardAmount: float32 = 0.0) =
          let stored = getInv(thing, key)
          if stored <= 0:
            removeThing(env, thing)
            used = true
          elif env.giveItem(agent, key):
            let gatherPos = thing.pos  # Capture for sparkle effect
            let remaining = stored - 1
            if rewardAmount != 0:
              env.rewards[id] += rewardAmount
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, key, remaining)
            # Apply biome gathering bonus
            let bonus = env.getBiomeGatherBonus(gatherPos, key)
            if bonus > 0:
              discard env.giveItem(agent, key, bonus)
            # Apply economy tech gathering bonus (AoE2-style)
            let teamId = getTeamId(agent)
            var techBonusPct = 0
            if key == ItemGold:
              techBonusPct = env.getGoldGatherBonus(teamId)
            elif key == ItemStone:
              techBonusPct = env.getStoneGatherBonus(teamId)
            elif key == ItemWood:
              techBonusPct = env.getWoodGatherBonus(teamId)
            if techBonusPct > 0 and (env.currentStep mod (100 div max(1, techBonusPct))) == 0:
              # Probabilistic bonus: techBonusPct% chance per gather to get +1
              discard env.giveItem(agent, key)
            # Spawn sparkle effect at resource location
            env.spawnGatherSparkle(gatherPos)
            used = true
        case thing.kind:
        of Relic:
          if agent.unitClass in {UnitMonk, UnitGoblin}:
            let stored = getInv(thing, ItemGold)
            if stored > 0:
              if env.giveItem(agent, ItemGold):
                setInv(thing, ItemGold, stored - 1)
              else:
                used = false
                break useAction
            if agent.inventoryRelic < MapObjectAgentMaxInventory:
              agent.inventoryRelic = agent.inventoryRelic + 1
              env.updateAgentInventoryObs(agent, ItemRelic)
              removeThing(env, thing)
              used = true
            else:
              used = stored > 0
        of Lantern:
          if agent.inventoryLantern < MapObjectAgentMaxInventory:
            agent.inventoryLantern = agent.inventoryLantern + 1
            env.updateAgentInventoryObs(agent, ItemLantern)
            removeThing(env, thing)
            used = true
        of Wheat:
          let stored = getInv(thing, ItemWheat)
          if stored <= 0:
            removeThing(env, thing)
            used = true
          elif env.grantItem(agent, ItemWheat):
            env.rewards[id] += env.config.wheatReward
            # Apply biome gathering bonus
            let bonus = env.getBiomeGatherBonus(thing.pos, ItemWheat)
            if bonus > 0:
              discard env.grantItem(agent, ItemWheat, bonus)
            let stubblePos = thing.pos  # Capture before pool release
            let teamId = getTeamId(agent)
            removeThing(env, thing)
            let stubble = acquireThing(env, Stubble)
            stubble.pos = stubblePos
            stubble.inventory = emptyInventory()
            let remaining = stored - 1
            if remaining > 0:
              setInv(stubble, ItemWheat, remaining)
            else:
              # Farm exhausted - add to nearest mill's auto-reseed queue
              if env.canAutoReseed(teamId):
                let mill = env.findNearestMill(stubblePos, teamId)
                if mill != nil:
                  env.addFarmToMillQueue(mill, stubblePos)
            env.add(stubble)
            # Spawn sparkle effect at harvest location
            env.spawnGatherSparkle(stubblePos)
            used = true
        of Stubble, Stump:
          let (key, reward) = if thing.kind == Stubble:
            (ItemWheat, env.config.wheatReward)
          else:
            (ItemWood, env.config.woodReward)
          if env.grantItem(agent, key):
            let gatherPos = thing.pos  # Capture for sparkle effect
            env.rewards[id] += reward
            # Apply biome gathering bonus
            let bonus = env.getBiomeGatherBonus(gatherPos, key)
            if bonus > 0:
              discard env.grantItem(agent, key, bonus)
            let remaining = getInv(thing, key) - 1
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, key, remaining)
            # Spawn sparkle effect at resource location
            env.spawnGatherSparkle(gatherPos)
            used = true
        of Stone:
          takeFromThing(ItemStone)
        of Gold:
          takeFromThing(ItemGold)
        of Bush, Cactus:
          takeFromThing(ItemPlant)
        of Stalagmite:
          takeFromThing(ItemStone)
        of Fish:
          takeFromThing(ItemFish)
        of Tree:
          used = env.harvestTree(agent, thing)
        of Corpse:
          var lootKey = ItemNone
          var lootCount = 0
          for key, count in thing.inventory.pairs:
            if count > 0:
              lootKey = key
              lootCount = count
              break
          if lootKey != ItemNone:
            if env.giveItem(agent, lootKey):
              let remaining = lootCount - 1
              if remaining <= 0:
                thing.inventory.del(lootKey)
              else:
                setInv(thing, lootKey, remaining)
              var hasItems = false
              for _, count in thing.inventory.pairs:
                if count > 0:
                  hasItems = true
                  break
              if not hasItems:
                removeThing(env, thing)
                if lootKey != ItemMeat:
                  let skeletonPos = thing.pos  # Capture before potential pool reuse
                  let skeleton = acquireThing(env, Skeleton)
                  skeleton.pos = skeletonPos
                  skeleton.inventory = emptyInventory()
                  env.add(skeleton)
              used = true
        of Magma:  # Magma smelting
          if thing.cooldown == 0 and getInv(agent, ItemGold) > 0 and agent.inventoryBar < MapObjectAgentMaxInventory:
            setInv(agent, ItemGold, getInv(agent, ItemGold) - 1)
            agent.inventoryBar = agent.inventoryBar + 1
            thing.cooldown = 0
            if agent.inventoryBar == 1:
              env.rewards[id] += env.config.barReward
            used = true
        of WeavingLoom:
          if thing.cooldown == 0 and agent.inventoryLantern == 0 and
              (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
            if agent.inventoryWood > 0:
              decInv(ItemWood)
            else:
              decInv(ItemWheat)
            setInvAndObs(ItemLantern, 1)
            thing.cooldown = 0
            env.rewards[id] += env.config.clothReward
            used = true
          elif thing.cooldown == 0:
            if env.tryCraftAtStation(agent, StationLoom, thing):
              used = true
        of ClayOven:
          if thing.cooldown == 0:
            if env.tryCraftAtStation(agent, StationOven, thing):
              used = true
            elif agent.inventoryWheat > 0:
              decInv(ItemWheat)
              incInv(ItemBread)
              thing.cooldown = 0
              # No observation layer for bread; optional for UI later
              env.rewards[id] += env.config.foodReward
              used = true
        of Skeleton:
          let stored = getInv(thing, ItemFish)
          if stored > 0 and env.giveItem(agent, ItemFish):
            let remaining = stored - 1
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, ItemFish, remaining)
            used = true
        of Temple:
          if agent.unitClass == UnitVillager and thing.cooldown == 0:
            env.templeInteractions.add TempleInteraction(
              agentId: agent.agentId,
              teamId: getTeamId(agent),
              pos: thing.pos
            )
            thing.cooldown = TempleInteractionCooldown
            used = true
        of Wall, Door:
          # Construction/repair: villagers can work on walls and doors
          if thing.teamId == getTeamId(agent) and thing.hp < thing.maxHp and
             agent.unitClass == UnitVillager:
            # Register this builder for the multi-builder bonus
            env.constructionBuilders.mgetOrPut(thing.pos, 0) += 1
            used = true
        else:
          if isBuildingKind(thing.kind):
            # Construction: villagers can work on buildings under construction
            if thing.maxHp > 0 and thing.hp < thing.maxHp and
               thing.teamId == getTeamId(agent) and agent.unitClass == UnitVillager:
              # Register this builder for the multi-builder bonus
              env.constructionBuilders.mgetOrPut(thing.pos, 0) += 1
              used = true
            # Normal building use (skip if construction happened)
            if not used:
              let useKind = buildingUseKind(thing.kind)
              case useKind
              of UseAltar:
                if thing.cooldown == 0 and agent.inventoryBar >= 1:
                  decInv(ItemBar)
                  thing.hearts = thing.hearts + 1
                  thing.cooldown = MapObjectAltarCooldown
                  env.updateObservations(altarHeartsLayer, thing.pos, thing.hearts)
                  env.rewards[id] += env.config.heartReward
                  used = true
              of UseClayOven:
                if thing.cooldown == 0:
                  if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
                  elif agent.inventoryWheat > 0:
                    decInv(ItemWheat)
                    incInv(ItemBread)
                    thing.cooldown = 0
                    env.rewards[id] += env.config.foodReward
                    used = true
              of UseWeavingLoom:
                if thing.cooldown == 0 and agent.inventoryLantern == 0 and
                    (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
                  if agent.inventoryWood > 0:
                    decInv(ItemWood)
                  else:
                    decInv(ItemWheat)
                  setInvAndObs(ItemLantern, 1)
                  thing.cooldown = 0
                  env.rewards[id] += env.config.clothReward
                  used = true
                elif thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
                  if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
              of UseBlacksmith:
                if thing.cooldown == 0:
                  if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
                if not used and thing.teamId == getTeamId(agent):
                  if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                    used = true
                # If crafting and storage failed, try researching a Blacksmith upgrade
                if not used and thing.cooldown == 0 and thing.teamId == getTeamId(agent):
                  if env.tryResearchBlacksmithUpgrade(agent, thing):
                    used = true
              of UseMarket:
                # AoE2-style market trading with dynamic prices
                if thing.cooldown == 0:
                  let teamId = getTeamId(agent)
                  if thing.teamId == teamId:
                    var traded = false
                    # Reuse arena buffer for inventory snapshot
                    env.arena.itemCounts.setLen(0)
                    for key, count in agent.inventory.pairs:
                      if count <= 0:
                        continue
                      if not isStockpileResourceKey(key):
                        continue
                      env.arena.itemCounts.add((key: key, count: count))
                    for entry in env.arena.itemCounts:
                      let key = entry.key
                      let count = entry.count
                      let stockpileRes = stockpileResourceForItem(key)
                      if stockpileRes == ResourceWater:
                        continue
                      if stockpileRes == ResourceGold:
                        # Buy food with gold (dynamic pricing)
                        when defined(eventLog):
                          let (goldSpent, foodGained) = env.marketBuyFood(agent, count)
                          if foodGained > 0:
                            env.updateAgentInventoryObs(agent, key)
                            logMarketTrade(teamId, "Bought", "Food", foodGained, goldSpent, env.currentStep)
                            traded = true
                        else:
                          let (_, foodGained) = env.marketBuyFood(agent, count)
                          if foodGained > 0:
                            env.updateAgentInventoryObs(agent, key)
                            traded = true
                      else:
                        # Sell resources for gold (dynamic pricing)
                        when defined(eventLog):
                          let (amountSold, goldGained) = env.marketSellInventory(agent, key)
                          if amountSold > 0:
                            env.updateAgentInventoryObs(agent, key)
                            logMarketTrade(teamId, "Sold", $stockpileRes, amountSold, goldGained, env.currentStep)
                            traded = true
                        else:
                          let (amountSold, _) = env.marketSellInventory(agent, key)
                          if amountSold > 0:
                            env.updateAgentInventoryObs(agent, key)
                            traded = true
                    if traded:
                      thing.cooldown = DefaultMarketCooldown
                      used = true
              of UseDropoff:
                if thing.teamId == getTeamId(agent):
                  if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
                    used = true
                  # Economy tech research (AoE2-style) - villagers research at economy buildings
                  if not used and thing.cooldown == 0:
                    if env.tryResearchEconomyTech(agent, thing):
                      used = true
                  # Town Center garrison: villagers can garrison if no resources to drop off
                  if not used and thing.kind == TownCenter and agent.unitClass == UnitVillager:
                    if env.garrisonUnitInBuilding(agent, thing):
                      used = true
              of UseDropoffAndTrain:
                if thing.teamId == getTeamId(agent):
                  if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
                    used = true
                  if not used and thing.cooldown == 0 and buildingHasTrain(thing.kind):
                    let teamId = getTeamId(agent)
                    if env.tryTrainUnit(agent, thing, buildingTrainUnit(thing.kind, teamId),
                        buildingTrainCosts(thing.kind), 0):
                      # Trade Cog: remember origin dock for gold calculation
                      if agent.unitClass == UnitTradeCog:
                        agent.tradeHomeDock = thing.pos
                      used = true
              of UseDropoffAndStorage:
                if thing.teamId == getTeamId(agent):
                  if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
                    used = true
                  if not used and env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                    used = true
              of UseStorage:
                if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                  used = true
              of UseTrain:
                # Special case: Monks can deposit relics in Monastery for gold generation
                if thing.kind == Monastery and agent.unitClass == UnitMonk and agent.inventoryRelic > 0:
                  thing.garrisonedRelics = thing.garrisonedRelics + agent.inventoryRelic
                  agent.inventoryRelic = 0
                  env.updateAgentInventoryObs(agent, ItemRelic)
                  used = true
                elif buildingHasTrain(thing.kind) and agent.unitClass == UnitVillager:
                  let teamId = getTeamId(agent)
                  # If queue has a ready entry, convert villager immediately (pre-paid)
                  if thing.productionQueueHasReady():
                    let unitClass = thing.consumeReadyQueueEntry()
                    applyUnitClass(agent, unitClass)
                    env.spawnSpawnEffect(agent.pos)  # Visual effect for unit creation
                    if agent.inventorySpear > 0:
                      agent.inventorySpear = 0
                    # Assign rally point target if building has one
                    if thing.hasRallyPoint():
                      agent.rallyTarget = thing.rallyPoint
                    used = true
                  # Try unit upgrade research if no ready queue entry
                  elif thing.cooldown == 0 and env.tryResearchUnitUpgrade(agent, thing):
                    used = true
                  # Otherwise queue a new training request (pay now, train later)
                  # Use effectiveTrainUnit to train the upgraded version
                  elif env.queueTrainUnit(thing, teamId,
                      env.effectiveTrainUnit(thing.kind, teamId),
                      buildingTrainCosts(thing.kind)):
                    used = true
              of UseTrainAndCraft:
                if thing.cooldown == 0:
                  if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
                  elif buildingHasTrain(thing.kind) and agent.unitClass == UnitVillager:
                    let teamId = getTeamId(agent)
                    if thing.productionQueueHasReady():
                      let unitClass = thing.consumeReadyQueueEntry()
                      applyUnitClass(agent, unitClass)
                      env.spawnSpawnEffect(agent.pos)  # Visual effect for unit creation
                      if agent.inventorySpear > 0:
                        agent.inventorySpear = 0
                      # Assign rally point target if building has one
                      if thing.hasRallyPoint():
                        agent.rallyTarget = thing.rallyPoint
                      used = true
                    elif env.queueTrainUnit(thing, teamId,
                        env.effectiveTrainUnit(thing.kind, teamId),
                        buildingTrainCosts(thing.kind)):
                      used = true
              of UseCraft:
                if thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
                  if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
              of UseUniversity:
                # University: craft items first, then research techs (like Blacksmith)
                if thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
                  if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                    used = true
                # If crafting failed or not possible, try researching
                if not used and thing.cooldown == 0 and thing.teamId == getTeamId(agent):
                  if env.tryResearchUniversityTech(agent, thing):
                    used = true
              of UseCastle:
                # Castle: research unique techs first, then train unique units
                # Research takes priority (like AoE2 where research buttons are distinct)
                if thing.cooldown == 0 and thing.teamId == getTeamId(agent):
                  if env.tryResearchCastleTech(agent, thing):
                    used = true
                # If no research available, try training units
                if not used and buildingHasTrain(thing.kind) and agent.unitClass == UnitVillager:
                  let teamId = getTeamId(agent)
                  if thing.productionQueueHasReady():
                    let unitClass = thing.consumeReadyQueueEntry()
                    applyUnitClass(agent, unitClass)
                    env.spawnSpawnEffect(agent.pos)  # Visual effect for unit creation
                    if agent.inventorySpear > 0:
                      agent.inventorySpear = 0
                    # Assign rally point target if building has one
                    if thing.hasRallyPoint():
                      agent.rallyTarget = thing.rallyPoint
                    used = true
                  elif env.queueTrainUnit(thing, teamId,
                      buildingTrainUnit(thing.kind, teamId),
                      buildingTrainCosts(thing.kind)):
                    used = true
                # Castle garrison: military units can garrison if no other action
                if not used and thing.teamId == getTeamId(agent) and agent.unitClass != UnitVillager:
                  if env.garrisonUnitInBuilding(agent, thing):
                    used = true
              of UseNone:
                # Garrison: any unit can garrison in buildings with garrison capacity
                if thing.teamId == getTeamId(agent) and garrisonCapacity(thing.kind) > 0:
                  if env.garrisonUnitInBuilding(agent, thing):
                    used = true

        if not used:
          block pickupAttempt:
            if isBuildingKind(thing.kind):
              break pickupAttempt
            if thing.kind in {Agent, Tumor, Tree, Wheat, Fish, Relic, Stubble, Stone, Gold, Bush, Cactus, Stalagmite,
                              Cow, Bear, Wolf, Corpse, Skeleton, Spawner, Stump, Wall, Magma, Lantern} or
                thing.kind in CliffKinds:
              break pickupAttempt

            let key = thingItem($thing.kind)
            let current = getInv(agent, key)
            if current >= MapObjectAgentMaxInventory:
              break pickupAttempt
            var resourceNeeded = 0
            for itemKey, count in thing.inventory.pairs:
              if isStockpileResourceKey(itemKey):
                resourceNeeded += count
              else:
                let capacity = MapObjectAgentMaxInventory - getInv(agent, itemKey)
                if capacity < count:
                  break pickupAttempt
            if resourceNeeded > stockpileCapacityLeft(agent):
              break pickupAttempt
            for itemKey, count in thing.inventory.pairs:
              setInv(agent, itemKey, getInv(agent, itemKey) + count)
              env.updateAgentInventoryObs(agent, itemKey)
            setInv(agent, key, current + 1)
            env.updateAgentInventoryObs(agent, key)
            if isValidPos(thing.pos):
              env.updateObservations(ThingAgentLayer, thing.pos, 0)
            removeThing(env, thing)
            used = true

        if used:
          inc env.stats[id].actionUse
          when defined(gatherHeatmap):
            if not thing.isNil:
              let gk = thingToGatherKind(thing.kind)
              if gk != grNone:
                recordGatherEvent(targetPos, gk)
        else:
          inc env.stats[id].actionInvalid
    of 4:
      block swapAction:
        ## Swap
        if argument > 7:
          invalidAndBreak(swapAction)
        let dir = Orientation(argument)
        agent.orientation = dir
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let targetPos = agent.pos + orientationToVec(dir)
        let target = env.getThing(targetPos)
        if isNil(target) or target.kind != Agent or isThingFrozen(target, env):
          inc env.stats[id].actionInvalid
          break swapAction
        let agentOld = agent.pos
        let targetOld = target.pos
        agent.pos = targetOld
        target.pos = agentOld
        env.grid[agentOld.x][agentOld.y] = target
        env.grid[targetOld.x][targetOld.y] = agent
        updateSpatialIndex(env, agent, agentOld)
        updateSpatialIndex(env, target, targetOld)
        env.updateObservations(AgentLayer, agentOld, getTeamId(target) + 1)
        env.updateObservations(AgentLayer, targetOld, getTeamId(agent) + 1)
        env.updateObservations(AgentOrientationLayer, agentOld, target.orientation.int)
        env.updateObservations(AgentOrientationLayer, targetOld, agent.orientation.int)
        inc env.stats[id].actionSwap
    of 5:
      block putAction:
        ## Give items to adjacent teammate in the given direction.
        if argument > 7:
          invalidAndBreak(putAction)
        let dir = Orientation(argument)
        agent.orientation = dir
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = orientationToVec(dir)
        let targetPos = agent.pos + delta
        if not isValidPos(targetPos):
          inc env.stats[id].actionInvalid
          break putAction
        let target = env.getThing(targetPos)
        if isNil(target):
          inc env.stats[id].actionInvalid
          break putAction
        if target.kind != Agent or isThingFrozen(target, env):
          inc env.stats[id].actionInvalid
          break putAction
        var transferred = false
        # Give armor if we have any and target has none
        if agent.inventoryArmor > 0 and target.inventoryArmor == 0:
          target.inventoryArmor = agent.inventoryArmor
          agent.inventoryArmor = 0
          transferred = true
        # Otherwise give food if possible (no obs layer yet)
        elif agent.inventoryBread > 0:
          let capacity = stockpileCapacityLeft(target)
          let giveAmt = min(agent.inventoryBread, capacity)
          if giveAmt > 0:
            agent.inventoryBread = agent.inventoryBread - giveAmt
            target.inventoryBread = target.inventoryBread + giveAmt
            transferred = true
        else:
          let stockpileCapacityLeftTarget = stockpileCapacityLeft(target)
          var bestKey = ItemNone
          var bestCount = 0
          for key, count in agent.inventory.pairs:
            if count <= 0:
              continue
            let capacity =
              if isStockpileResourceKey(key):
                stockpileCapacityLeftTarget
              else:
                MapObjectAgentMaxInventory - getInv(target, key)
            if capacity <= 0:
              continue
            if count > bestCount:
              bestKey = key
              bestCount = count
          if bestKey != ItemNone and bestCount > 0:
            let capacity =
              if isStockpileResourceKey(bestKey):
                stockpileCapacityLeftTarget
              else:
                max(0, MapObjectAgentMaxInventory - getInv(target, bestKey))
            if capacity > 0:
              let moved = min(bestCount, capacity)
              setInv(agent, bestKey, bestCount - moved)
              setInv(target, bestKey, getInv(target, bestKey) + moved)
              env.updateAgentInventoryObs(agent, bestKey)
              env.updateAgentInventoryObs(target, bestKey)
              transferred = true
        if transferred:
          inc env.stats[id].actionPut
          # Update observations for changed inventories
          env.updateAgentInventoryObs(agent, ItemArmor)
          env.updateAgentInventoryObs(agent, ItemBread)
          env.updateAgentInventoryObs(target, ItemArmor)
          env.updateAgentInventoryObs(target, ItemBread)
        else:
          inc env.stats[id].actionInvalid
    of 6:
      block plantAction:
        ## Plant lantern in the given direction.
        if argument > 7:
          inc env.stats[id].actionInvalid
          break plantAction
        let plantOrientation = Orientation(argument)
        agent.orientation = plantOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = orientationToVec(plantOrientation)
        let targetPos = agent.pos + delta

        # Check if position is empty and not water
        if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break plantAction

        if agent.inventoryLantern > 0:
          # Calculate team ID directly from the planting agent's ID
          let teamId = getTeamId(agent)

          # Plant the lantern
          let lantern = acquireThing(env, Lantern)
          lantern.pos = targetPos
          lantern.teamId = teamId
          lantern.lanternHealthy = true

          env.add(lantern)

          # Consume the lantern from agent's inventory
          agent.inventoryLantern = 0

          # Give reward for planting
          env.rewards[id] += env.config.clothReward * 0.5  # Half reward for planting

          inc env.stats[id].actionPlant
        else:
          inc env.stats[id].actionInvalid
    of 7:
      block plantResourceAction:
        ## Plant wheat (args 0-3) or tree (args 4-7) onto an adjacent fertile tile.
        let plantingTree =
          if argument <= 7:
            argument >= 4
          else:
            (argument mod 2) == 1
        let dirIndex =
          if argument <= 7:
            (if plantingTree: argument - 4 else: argument)
          else:
            (if argument mod 2 == 1: (argument div 2) mod 4 else: argument mod 4)
        if dirIndex < 0 or dirIndex > 7:
          inc env.stats[id].actionInvalid
          break plantResourceAction
        let orientation = Orientation(dirIndex)
        agent.orientation = orientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = orientationToVec(orientation)
        let targetPos = agent.pos + delta

        # Occupancy checks
        if not env.isEmpty(targetPos) or not isNil(env.getBackgroundThing(targetPos)) or env.hasDoor(targetPos) or
            isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break plantResourceAction
        if env.terrain[targetPos.x][targetPos.y] != Fertile:
          inc env.stats[id].actionInvalid
          break plantResourceAction

        if plantingTree:
          if agent.inventoryWood <= 0:
            inc env.stats[id].actionInvalid
            break plantResourceAction
          agent.inventoryWood = max(0, agent.inventoryWood - 1)
          let tree = Thing(kind: Tree, pos: targetPos)
          tree.inventory = emptyInventory()
          setInv(tree, ItemWood, ResourceNodeInitial)
          env.add(tree)
        else:
          if agent.inventoryWheat <= 0:
            inc env.stats[id].actionInvalid
            break plantResourceAction
          agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
          let crop = Thing(kind: Wheat, pos: targetPos)
          crop.inventory = emptyInventory()
          setInv(crop, ItemWheat, ResourceNodeInitial)
          env.add(crop)

        env.terrain[targetPos.x][targetPos.y] = Empty
        env.resetTileColor(targetPos)
        env.updateObservations(ThingAgentLayer, targetPos, 0)

        # Consuming fertility (terrain replaced above)
        inc env.stats[id].actionPlantResource
    of 8:
      block buildFromChoices:
        let key = BuildChoices[argument]
        var buildKind: ThingKind
        let isDock = parseThingKey(key, buildKind) and buildKind == Dock

        var offsets: array[9, IVec2]
        var offsetCount = 0
        for offset in [
          orientationToVec(agent.orientation),
          ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
          ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1)
        ]:
          if offset.x == 0'i32 and offset.y == 0'i32:
            continue
          var duplicate = false
          for i in 0 ..< offsetCount:
            if offsets[i] == offset:
              duplicate = true
              break
          if duplicate:
            continue
          offsets[offsetCount] = offset
          inc offsetCount

        var targetPos = ivec2(-1, -1)
        for i in 0 ..< offsetCount:
          let offset = offsets[i]
          let pos = agent.pos + offset
          if (if isDock: env.canPlaceDock(pos) else: env.canPlace(pos)):
            targetPos = pos
            break
        if targetPos.x < 0:
          invalidAndBreak(buildFromChoices)

        let teamId = getTeamId(agent)
        let costs = buildCostsForKey(key)
        if costs.len == 0:
          invalidAndBreak(buildFromChoices)
        let payment = choosePayment(env, agent, costs)
        if payment == PayNone:
          invalidAndBreak(buildFromChoices)

        var placedOk = false
        var placedKind: ThingKind
        var placedKindValid = false
        block placeThing:
          if isThingKey(key) and key.name == "Road":
            if not isBuildableTerrain(env.terrain[targetPos.x][targetPos.y]):
              break placeThing
            env.terrain[targetPos.x][targetPos.y] = Road
            env.resetTileColor(targetPos)
            env.updateObservations(ThingAgentLayer, targetPos, 0)
            placedOk = true
            break placeThing
          if not parseThingKey(key, placedKind):
            break placeThing
          placedKindValid = true
          let isBuilding = isBuildingKind(placedKind)
          let placed = Thing(
            kind: placedKind,
            pos: targetPos
          )
          if isBuilding and placedKind != Barrel:
            placed.teamId = getTeamId(agent)
          case placedKind
          of Lantern:
            placed.teamId = getTeamId(agent)
            placed.lanternHealthy = true
          of Altar:
            placed.inventory = emptyInventory()
            placed.hearts = 0
          of Spawner:
            placed.homeSpawner = targetPos
          else:
            discard
          if isBuilding:
            let capacity = buildingBarrelCapacity(placedKind)
            if capacity > 0:
              placed.barrelCapacity = capacity
          env.add(placed)
          # Apply Masonry and Architecture HP bonuses for buildings
          # Each tech grants +10% building HP
          if isBuilding and placed.maxHp > 0 and placed.teamId >= 0:
            var hpMultiplier = 1.0'f32
            if env.hasUniversityTech(placed.teamId, TechMasonry):
              hpMultiplier += 0.1
            if env.hasUniversityTech(placed.teamId, TechArchitecture):
              hpMultiplier += 0.1
            if hpMultiplier > 1.0:
              placed.maxHp = int(float32(placed.maxHp) * hpMultiplier + 0.5)
          # Player-built buildings start under construction (hp=1)
          # They need villagers to complete construction
          if isBuilding and placed.maxHp > 0:
            placed.hp = 1
          if isBuilding:
            let radius = buildingFertileRadius(placedKind)
            if radius > 0:
              env.applyFertileRadius(placed.pos, radius)
          if isValidPos(targetPos):
            env.updateObservations(ThingAgentLayer, targetPos, 0)
          if placedKind == Altar:
            let teamId = placed.teamId
            if teamId >= 0 and teamId < env.teamColors.len:
              env.altarColors[targetPos] = env.teamColors[teamId]
          when defined(eventLog):
            if isBuilding:
              logBuildingStarted(placed.teamId, $placedKind,
                                 "(" & $placed.pos.x & "," & $placed.pos.y & ")", env.currentStep)
          placedOk = true

        if placedOk:
          discard spendCosts(env, agent, payment, costs)
          when defined(econAudit):
            if payment == PayStockpile:
              # Convert ItemKey costs to StockpileResource costs for tracking
              for cost in costs:
                let res = stockpileResourceForItem(cost.key)
                if res != ResourceNone:
                  recordFlow(teamId, res, -cost.count, rfsBuildingCost, env.currentStep)
          if placedKindValid and placedKind in {Mill, LumberCamp, MiningCamp}:
            # Use spatial query instead of O(n) scan for nearest team anchor
            var anchor = ivec2(-1, -1)
            var bestDist = int.high
            for kind in [TownCenter, Altar]:
              let nearest = findNearestFriendlyThingSpatial(env, targetPos, teamId, kind, 1000)
              if not nearest.isNil:
                let dist = abs(nearest.pos.x - targetPos.x) + abs(nearest.pos.y - targetPos.y)
                if dist < bestDist:
                  bestDist = dist
                  anchor = nearest.pos
            if anchor.x < 0:
              anchor = targetPos
            var pos = targetPos
            while pos.x != anchor.x:
              pos.x += (if anchor.x < pos.x: -1'i32 elif anchor.x > pos.x: 1'i32 else: 0'i32)
              if env.canPlace(pos, checkFrozen = false):
                env.terrain[pos.x][pos.y] = Road
                env.resetTileColor(pos)
                env.updateObservations(ThingAgentLayer, pos, 0)
            while pos.y != anchor.y:
              pos.y += (if anchor.y < pos.y: -1'i32 elif anchor.y > pos.y: 1'i32 else: 0'i32)
              if env.canPlace(pos, checkFrozen = false):
                env.terrain[pos.x][pos.y] = Road
                env.resetTileColor(pos)
                env.updateObservations(ThingAgentLayer, pos, 0)
          inc env.stats[id].actionBuild
        else:
          inc env.stats[id].actionInvalid
    of 9:
      block orientAction:
        ## Change orientation without moving.
        if argument < 0 or argument > 7:
          invalidAndBreak(orientAction)
        let newOrientation = Orientation(argument)
        if agent.orientation != newOrientation:
          agent.orientation = newOrientation
          env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        inc env.stats[id].actionOrient
    of 10:
      block setRallyPointAction:
        ## Set rally point on an adjacent friendly building.
        ## The argument (0-7) is the direction toward the target building.
        ## The rally point is set to the agent's current position.
        if argument < 0 or argument > 7:
          invalidAndBreak(setRallyPointAction)
        let dir = Orientation(argument)
        let delta = orientationToVec(dir)
        let buildingPos = agent.pos + delta
        if not isValidPos(buildingPos):
          invalidAndBreak(setRallyPointAction)
        var thing = env.getThing(buildingPos)
        if isNil(thing) or not isBuildingKind(thing.kind):
          thing = env.getBackgroundThing(buildingPos)
        if isNil(thing) or not isBuildingKind(thing.kind):
          invalidAndBreak(setRallyPointAction)
        if thing.teamId != getTeamId(agent):
          invalidAndBreak(setRallyPointAction)
        thing.setRallyPoint(agent.pos)
        inc env.stats[id].actionSetRallyPoint
    else:
      inc env.stats[id].actionInvalid

  # Apply multi-builder construction speed bonus
  # Treadmill Crane: +20% construction speed from University tech
  for pos, builderCount in env.constructionBuilders.pairs:
    let thing = env.getThing(pos)
    if thing.isNil or thing.maxHp <= 0 or thing.hp >= thing.maxHp:
      continue
    # Calculate effective HP gain with diminishing returns
    # ConstructionBonusTable: [1.0, 1.0, 1.5, 1.83, 2.08, 2.28, 2.45, 2.59, 2.72]
    let tableIdx = min(builderCount, ConstructionBonusTable.high)
    var multiplier = ConstructionBonusTable[tableIdx]
    # Treadmill Crane: +20% construction speed
    if thing.teamId >= 0 and env.hasUniversityTech(thing.teamId, TechTreadmillCrane):
      multiplier = multiplier * 1.2'f32
    let hpGain = int(float32(ConstructionHpPerAction) * multiplier + 0.5)
    when defined(eventLog):
      let wasBelowMax = thing.hp < thing.maxHp
    when defined(audio):
      let wasBelowMaxAudio = thing.hp < thing.maxHp
    thing.hp = min(thing.maxHp, thing.hp + hpGain)
    # Spawn construction dust particles while building is under construction
    if thing.hp < thing.maxHp:
      env.spawnConstructionDust(thing.pos)
    when defined(eventLog):
      if wasBelowMax and thing.hp >= thing.maxHp:
        logBuildingCompleted(thing.teamId, $thing.kind,
                             "(" & $thing.pos.x & "," & $thing.pos.y & ")", env.currentStep)
    when defined(audio):
      if wasBelowMaxAudio and thing.hp >= thing.maxHp:
        audioOnBuildingComplete(thing.pos)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tActionsMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[3] = msBetweenPerfTiming(prfStart, prfNow)  # actions
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[3] = usBetween(fgStart, fgNow)  # actions
    fgStart = fgNow

  # Per-kind object updates: iterate each type separately for cache locality.
  # Same-type objects share field access patterns, so grouping them avoids
  # polymorphic dispatch overhead and reduces cache line waste from loading
  # irrelevant fields of mixed-type objects.
  env.tempTumorsToSpawn.setLen(0)
  env.tempTumorsToProcess.setLen(0)
  env.tempTowerRemovals.setLen(0)

  for i in 0 ..< env.cowHerdCounts.len:
    env.cowHerdCounts[i] = 0
    env.cowHerdSumX[i] = 0
    env.cowHerdSumY[i] = 0

  for i in 0 ..< env.wolfPackCounts.len:
    env.wolfPackCounts[i] = 0
    env.wolfPackSumX[i] = 0
    env.wolfPackSumY[i] = 0

  # Pop caps already pre-computed at step start in env.stepTeamPopCaps

  # Defensive buildings: process tower attacks first to populate tempTowerRemovals
  for thing in env.thingsByKind[GuardTower]:
    env.stepTryTowerAttack(thing, GuardTowerRange, env.tempTowerRemovals)

  for thing in env.thingsByKind[Castle]:
    env.stepTryTowerAttack(thing, CastleRange, env.tempTowerRemovals)
    if thing.cooldown > 0:
      dec thing.cooldown
    thing.processProductionQueue()

  for thing in env.thingsByKind[TownCenter]:
    env.stepTryTownCenterAttack(thing, env.tempTowerRemovals)

  # Resource and economy buildings
  for thing in env.thingsByKind[Altar]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    if env.currentStep == env.config.maxSteps:
      # Use teamVillagers cache instead of iterating all agents (O(team_villagers) vs O(all_agents))
      let teamId = thing.teamId
      if teamId >= 0 and teamId < MapRoomObjectsTeams:
        let altarHearts = thing.hearts.float32
        let perAgentReward = altarHearts / MapAgentsPerTeam.float32
        for agent in env.teamVillagers[teamId]:
          if agent.homeAltar == thing.pos:
            env.rewards[agent.agentId] += perAgentReward

  for thing in env.thingsByKind[Magma]:
    if thing.cooldown > 0:
      dec thing.cooldown

  for thing in env.thingsByKind[Mill]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    else:
      env.applyFertileRadius(thing.pos, max(0, buildingFertileRadius(thing.kind)))
      thing.cooldown = MillFertileCooldown
    # Process farm auto-reseed queue (AoE2-style)
    if thing.farmQueue.len > 0:
      discard env.tryAutoReseedFarm(thing)

  for thing in env.thingsByKind[Temple]:
    if thing.cooldown > 0:
      dec thing.cooldown

  for thing in env.thingsByKind[Monastery]:
    if thing.garrisonedRelics > 0:
      if thing.cooldown > 0:
        dec thing.cooldown
      else:
        let teamId = thing.teamId
        if teamId >= 0 and teamId < MapRoomObjectsTeams:
          let goldAmount = thing.garrisonedRelics * MonasteryRelicGoldAmount
          env.teamStockpiles[teamId].counts[ResourceGold] += goldAmount
          when defined(econAudit):
            recordRelicGold(teamId, goldAmount, env.currentStep)
        thing.cooldown = MonasteryRelicGoldInterval
    else:
      if thing.cooldown > 0:
        dec thing.cooldown
    thing.processProductionQueue()

  for thing in env.thingsByKind[Wonder]:
    if thing.hp > 0 and thing.wonderVictoryCountdown > 0:
      dec thing.wonderVictoryCountdown
      if thing.wonderVictoryCountdown <= 0:
        env.victoryWinner = thing.teamId

  # Production/craft buildings and economy tech buildings: cooldown-only buildings
  for kind in [ClayOven, WeavingLoom, Blacksmith, Market, LumberCamp, MiningCamp, Quarry, TownCenter]:
    for thing in env.thingsByKind[kind]:
      if thing.cooldown > 0:
        dec thing.cooldown

  # Production buildings with training queues
  for kind in [Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop, TrebuchetWorkshop, Dock]:
    for thing in env.thingsByKind[kind]:
      if thing.cooldown > 0:
        dec thing.cooldown
      thing.processProductionQueue()

  # Spawners: check tempTowerRemovals since towers can target spawners
  for thing in env.thingsByKind[Spawner]:
    if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
      continue
    if thing.cooldown > 0:
      thing.cooldown -= 1
    else:
      let nearbyTumorCount = countUnclaimedTumorsInRangeSpatial(env, thing.pos, 5)

      if nearbyTumorCount < MaxTumorsPerSpawner:
        let spawnPos = env.findFirstEmptyPositionAround(thing.pos, 2)
        if spawnPos.x >= 0:

          let newTumor = createTumor(env, spawnPos, thing.pos, stepRng)
          env.tempTumorsToSpawn.add(newTumor)
          when defined(tumorAudit):
            recordTumorSpawned()

          let cooldown = if env.config.tumorSpawnRate > 0.0:
            max(1, int(TumorSpawnCooldownBase / env.config.tumorSpawnRate))
          else:
            TumorSpawnDisabledCooldown
          thing.cooldown = cooldown

  # Cow herd aggregation
  for thing in env.thingsByKind[Cow]:
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

  # Wolf pack aggregation
  for thing in env.thingsByKind[Wolf]:
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

  # Agent state ticks (frozen, trebuchet cooldown)
  for thing in env.thingsByKind[Agent]:
    if thing.frozen > 0:
      thing.frozen -= 1
    if thing.unitClass == UnitTrebuchet and thing.cooldown > 0:
      thing.cooldown -= 1
      if thing.cooldown == 0:
        thing.packed = not thing.packed

  # Tumor collection: check tempTowerRemovals since towers can target tumors
  for thing in env.thingsByKind[Tumor]:
    if env.tempTowerRemovals.len > 0 and thing in env.tempTowerRemovals:
      continue
    if not thing.hasClaimedTerritory:
      env.tempTumorsToProcess.add(thing)

  # Pop cap clamping already done in pre-computation at step start

  if env.tempTowerRemovals.len > 0:
    for target in env.tempTowerRemovals:
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
    if desired.x == 0 and desired.y == 0:
      return
    let nextPos = thing.pos + desired
    if isValidPos(nextPos) and not env.hasDoor(nextPos) and
       not isBlockedTerrain(env.terrain[nextPos.x][nextPos.y]) and env.isEmpty(nextPos):
      let oldPos = thing.pos
      env.grid[thing.pos.x][thing.pos.y] = nil
      thing.pos = nextPos
      env.grid[nextPos.x][nextPos.y] = thing
      updateSpatialIndex(env, thing, oldPos)
      if desired.x < 0:
        thing.orientation = Orientation.W
      elif desired.x > 0:
        thing.orientation = Orientation.E

  let cornerMin = (MapBorder + 2).int32
  let cornerMaxX = (MapWidth - MapBorder - 3).int32
  let cornerMaxY = (MapHeight - MapBorder - 3).int32
  let cornerTargets = [
    ivec2(cornerMin, cornerMin),
    ivec2(cornerMaxX, cornerMin),
    ivec2(cornerMin, cornerMaxY),
    ivec2(cornerMaxX, cornerMaxY)
  ]

  proc selectNewCornerTarget(center, currentTarget: IVec2): IVec2 =
    ## Select a new corner target, preferring the farthest corner from center
    var bestDist = -1
    var candidates: array[4, IVec2]
    var candidateCount = 0
    for corner in cornerTargets:
      if corner == currentTarget:
        continue
      let dist = max(abs(center.x - corner.x), abs(center.y - corner.y))
      if dist > bestDist:
        candidateCount = 0
        candidates[candidateCount] = corner
        inc candidateCount
        bestDist = dist
      elif dist == bestDist:
        candidates[candidateCount] = corner
        inc candidateCount
    if candidateCount == 0:
      cornerTargets[randIntInclusive(stepRng, 0, 3)]
    else:
      candidates[randIntInclusive(stepRng, 0, candidateCount - 1)]

  proc needsNewCornerTarget(center, target: IVec2): bool =
    ## Check if herd/pack needs a new corner target
    let targetInvalid = target.x < 0 or target.y < 0
    if targetInvalid:
      return true
    let distToTarget = max(abs(center.x - target.x), abs(center.y - target.y))
    let nearBorder = center.x <= cornerMin or center.y <= cornerMin or
                     center.x >= cornerMaxX or center.y >= cornerMaxY
    nearBorder and distToTarget <= 3

  for herdId in 0 ..< env.cowHerdCounts.len:
    if env.cowHerdCounts[herdId] <= 0:
      env.cowHerdDrift[herdId] = ivec2(0, 0)
      continue
    let herdAccCount = max(1, env.cowHerdCounts[herdId])
    let center = ivec2((env.cowHerdSumX[herdId] div herdAccCount).int32,
                       (env.cowHerdSumY[herdId] div herdAccCount).int32)
    let target = env.cowHerdTargets[herdId]
    if needsNewCornerTarget(center, target):
      env.cowHerdTargets[herdId] = selectNewCornerTarget(center, target)
    env.cowHerdDrift[herdId] = stepToward(center, env.cowHerdTargets[herdId])

  for packId in 0 ..< env.wolfPackCounts.len:
    if env.wolfPackCounts[packId] <= 0:
      env.wolfPackDrift[packId] = ivec2(0, 0)
      continue
    let packAccCount = max(1, env.wolfPackCounts[packId])
    let center = ivec2((env.wolfPackSumX[packId] div packAccCount).int32,
                       (env.wolfPackSumY[packId] div packAccCount).int32)
    let huntTarget = findNearestPredatorTargetSpatial(env, center, WolfPackAggroRadius)
    if huntTarget.x >= 0:
      env.wolfPackTargets[packId] = huntTarget
    elif needsNewCornerTarget(center, env.wolfPackTargets[packId]):
      env.wolfPackTargets[packId] = selectNewCornerTarget(center, env.wolfPackTargets[packId])
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
    elif (drift.x != 0 or drift.y != 0) and randFloat(stepRng) < CowHerdFollowChance:
      desired = stepToward(thing.pos, herdTarget)
    elif randFloat(stepRng) < CowRandomMoveChance:
      desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]

    tryStep(thing, desired)

  for thing in env.thingsByKind[Wolf]:
    if thing.cooldown > 0:
      thing.cooldown -= 1

    # Handle scattered state - wolves move randomly after pack leader dies
    if thing.scatteredSteps > 0:
      thing.scatteredSteps -= 1
      # Scattered wolves wander randomly
      if randFloat(stepRng) < WolfScatteredMoveChance:
        let desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]
        tryStep(thing, desired)
      continue

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
    elif (drift.x != 0 or drift.y != 0) and randFloat(stepRng) < WolfPackFollowChance:
      desired = stepToward(thing.pos, center + drift * 3)
    elif randFloat(stepRng) < WolfRandomMoveChance:
      desired = CardinalOffsets[randIntInclusive(stepRng, 0, 3)]

    tryStep(thing, desired)

  for thing in env.thingsByKind[Bear]:
    if thing.cooldown > 0:
      thing.cooldown -= 1
    let target = findNearestPredatorTargetSpatial(env, thing.pos, BearAggroRadius)
    var desired = ivec2(0, 0)
    if target.x >= 0:
      let dist = max(abs(target.x - thing.pos.x), abs(target.y - thing.pos.y))
      if dist > 1:
        desired = stepToward(thing.pos, target)
    elif randFloat(stepRng) < BearRandomMoveChance:
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

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[4] = msBetweenPerfTiming(prfStart, prfNow)  # things
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[4] = usBetween(fgStart, fgNow)  # things
    fgStart = fgNow

  env.stepProcessTumors(env.tempTumorsToProcess, env.tempTumorsToSpawn, stepRng)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tTumorsMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[5] = msBetweenPerfTiming(prfStart, prfNow)  # tumors
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[5] = usBetween(fgStart, fgNow)  # tumors
    fgStart = fgNow

  env.stepApplyTumorDamage(stepRng)

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tTumorDamageMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[6] = msBetweenPerfTiming(prfStart, prfNow)  # tumorDamage
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[6] = usBetween(fgStart, fgNow)  # tumorDamage
    fgStart = fgNow

  # Tank aura tints
  env.stepApplyTankAuras()

  # Monk aura tints + healing
  env.stepApplyMonkAuras()

  # Recharge monk faith over time
  env.stepRechargeMonkFaith()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tAurasMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[7] = msBetweenPerfTiming(prfStart, prfNow)  # auras
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[7] = usBetween(fgStart, fgNow)  # auras
    fgStart = fgNow

  # Catch any agents that were reduced to zero HP during the step
  env.enforceZeroHpDeaths()

  # Precompute team population counts (Town Centers + Houses already counted above)
  var teamPopCounts: array[MapRoomObjectsTeams, int]
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let teamId = getTeamId(agent)
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      inc teamPopCounts[teamId]

  # Respawn dead agents at their altars
  for agentId in 0 ..< MapAgents:
    let agent = env.agents[agentId]

    # Check if agent is dead and has a home altar
    if env.terminated[agentId] == 1.0 and agent.homeAltar.x >= 0:
      let teamId = getTeamId(agent)
      if teamId < 0 or teamId >= MapRoomObjectsTeams:
        continue
      if teamPopCounts[teamId] >= env.stepTeamPopCaps[teamId]:
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
          let oldPos = agent.pos
          agent.pos = respawnPos
          agent.inventory = emptyInventory()
          agent.frozen = 0
          applyUnitClass(agent, UnitVillager)
          env.terminated[agentId] = 0.0
          when defined(eventLog):
            logSpawn(teamId, $agent.unitClass,
                     "(" & $respawnPos.x & "," & $respawnPos.y & ")", env.currentStep)

          # Update grid
          env.grid[agent.pos.x][agent.pos.y] = agent
          inc teamPopCounts[teamId]
          updateSpatialIndex(env, agent, oldPos)

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
      if candTeam < 0 or candTeam >= MapRoomObjectsTeams:
        continue
      if parentA.isNil:
        parentA = candidate
        teamId = candTeam
      elif candTeam == teamId and candidate.agentId != parentA.agentId:
        parentB = candidate
        break
    if parentA.isNil or parentB.isNil:
      continue
    if teamPopCounts[teamId] >= env.stepTeamPopCaps[teamId]:
      continue
    # Find a dormant agent slot for this team.
    let teamStart = teamId * MapAgentsPerTeam
    let teamEnd = teamStart + MapAgentsPerTeam
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
    let childOldPos = child.pos
    child.pos = spawnPos
    child.inventory = emptyInventory()
    child.frozen = 0
    applyUnitClass(child, UnitVillager)
    env.terminated[childId] = 0.0
    when defined(eventLog):
      logSpawn(teamId, $child.unitClass,
               "(" & $spawnPos.x & "," & $spawnPos.y & ")", env.currentStep)
    env.grid[child.pos.x][child.pos.y] = child
    inc teamPopCounts[teamId]
    updateSpatialIndex(env, child, childOldPos)
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
    temple.cooldown = TempleHybridCooldown

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tPopRespawnMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[8] = msBetweenPerfTiming(prfStart, prfNow)  # popRespawn
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[8] = usBetween(fgStart, fgNow)  # popRespawn
    fgStart = fgNow

  # Apply per-step survival penalty to all living agents
  env.stepApplySurvivalPenalty()

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tSurvivalMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[9] = msBetweenPerfTiming(prfStart, prfNow)  # survival
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[9] = usBetween(fgStart, fgNow)  # survival
    fgStart = fgNow

  # Update heatmap using batch tint modification system
  # This is much more efficient than updating during each entity move
  env.updateTintModifications()  # Collect all entity contributions
  env.applyTintModifications()   # Apply them to the main color array in one pass

  # Mark observations as dirty for lazy rebuilding
  # This replaces the previous approach of rebuilding every step. Now we only
  # rebuild when observations are actually accessed (via FFI or getObservations).
  # This saves O(agents * observation_tiles) work when observations aren't needed.
  env.observationsDirty = true

  # Spatial index is now maintained incrementally during position updates,
  # so no rebuild needed here. This eliminates O(things) work every step.

  when defined(stepTiming):
    if timing:
      tNow = getMonoTime()
      tTintMs = msBetween(tStart, tNow)
      tStart = tNow

  when defined(perfRegression):
    prfNow = getMonoTime()
    prfSubsystems[10] = msBetweenPerfTiming(prfStart, prfNow)  # tintObs
    prfStart = prfNow

  when defined(flameGraph):
    fgNow = getMonoTime()
    fgSubsystems[10] = usBetween(fgStart, fgNow)  # tintObs
    fgStart = fgNow

  # Check victory conditions
  if env.config.victoryCondition != VictoryNone and env.victoryWinner < 0:
    env.checkVictoryConditions()

  # Check if episode should end (victory or time limit)
  if env.victoryWinner >= 0:
    if not env.territoryScored:
      env.territoryScore = env.scoreTerritory()
      env.territoryScored = true
    # Terminate losing teams, truncate winning team and award victory reward
    for i in 0..<MapAgents:
      if env.terminated[i] == 0.0:
        let teamId = getTeamId(i)
        if teamId == env.victoryWinner:
          env.rewards[i] += VictoryReward
          env.truncated[i] = 1.0  # Winners: episode ended (truncated, not dead)
        else:
          env.terminated[i] = 1.0  # Losers: eliminated
    env.shouldReset = true
  elif env.currentStep >= env.config.maxSteps:
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

      let totalMs = msBetween(tTotalStart, tNow)

      # Per-step echo (original behavior, only when step target is set)
      if perStepTiming:
        let countTumor = env.thingsByKind[Tumor].len
        let countCorpse = env.thingsByKind[Corpse].len
        let countSkeleton = env.thingsByKind[Skeleton].len
        let countCow = env.thingsByKind[Cow].len
        let countStump = env.thingsByKind[Stump].len

        echo "step=", env.currentStep,
          " total_ms=", totalMs,
          " actionTint_ms=", tActionTintMs,
          " shields_ms=", tShieldsMs,
          " preDeaths_ms=", tPreDeathsMs,
          " actions_ms=", tActionsMs,
          " things_ms=", tThingsMs,
          " tumor_ms=", tTumorsMs,
          " tumorDamage_ms=", tTumorDamageMs,
          " auras_ms=", tAurasMs,
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

      # Aggregate timing report
      if aggregateTiming:
        let systemMs = [tActionTintMs, tShieldsMs, tPreDeathsMs, tActionsMs,
                        tThingsMs, tTumorsMs, tTumorDamageMs, tAurasMs,
                        tPopRespawnMs, tSurvivalMs, tTintMs + tEndMs]
        for i in 0 ..< TimingSystemCount:
          recordTimingSample(i, systemMs[i])
        timingCumTotal += totalMs
        inc timingStepCount
        if timingStepCount >= stepTimingInterval:
          printTimingReport(env.currentStep)

  when defined(spatialStats):
    printSpatialReport()

  when defined(perfRegression):
    let prfTotal = msBetweenPerfTiming(prfTotalStart, getMonoTime())
    recordPerfStep(prfSubsystems, prfTotal)
    checkPerfRegression(env.currentStep)

  when defined(flameGraph):
    let fgTotalUs = usBetween(fgTotalStart, getMonoTime())
    recordFlameStep(env.currentStep, fgSubsystems, fgTotalUs)

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

  # Sync contiguous rewards array back to agent objects for backward compatibility
  when defined(rewardBatch):
    let rbStart = getMonoTime()
  for i in 0 ..< MapAgents:
    env.agents[i].reward = env.rewards[i]
  when defined(rewardBatch):
    let rbEnd = getMonoTime()
    rewardBatchCumMs += rewardBatchMsBetween(rbStart, rbEnd)
    inc rewardBatchSteps
    if rewardBatchSteps >= RewardBatchReportInterval:
      reportRewardBatch()

  when defined(combatAudit):
    printCombatReport(env.currentStep)

  when defined(tumorAudit):
    env.printTumorReport()

  when defined(actionAudit):
    printActionAuditReport(env.currentStep)

  when defined(actionFreqCounter):
    printActionFreqReport(env.currentStep)

  when defined(eventLog):
    flushEventSummary(env.currentStep)

  when defined(settlerMetrics):
    if shouldUpdateMetrics(env.currentStep):
      updateSettlerMetrics(env)

  when defined(techAudit):
    maybePrintTechSummary(env, env.currentStep)

  when defined(econAudit):
    maybePrintEconDashboard(env, env.currentStep)

  when defined(stateDiff):
    comparePostStep(env)

  maybeLogReplayStep(env, actions)
  maybeDumpState(env)
  if env.shouldReset:
    maybeFinalizeReplay(env)

  if logRenderEnabled and (env.currentStep mod logRenderEvery == 0):
    var logEntry = "STEP " & $env.currentStep & "\n"
    var teamSeen: array[MapRoomObjectsTeams, bool]
    for agent in env.agents:
      if agent.isNil:
        continue
      let teamId = getTeamId(agent)
      if teamId >= 0 and teamId < teamSeen.len:
        teamSeen[teamId] = true
    logEntry.add("Stockpiles:\n")
    for teamId, seen in teamSeen:
      if not seen:
        continue
      logEntry.add(
        "  t" & $teamId &
        " food=" & $env.stockpileCount(teamId, ResourceFood) &
        " wood=" & $env.stockpileCount(teamId, ResourceWood) &
        " stone=" & $env.stockpileCount(teamId, ResourceStone) &
        " gold=" & $env.stockpileCount(teamId, ResourceGold) & "\n"
      )
    logEntry.add("Agents:\n")
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
      logEntry.add(
        "  a" & $id &
        " t" & $getTeamId(agent) &
        " " & (case agent.agentId mod MapAgentsPerTeam:
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
    logEntry.add("Map:\n")
    logEntry.add(env.render())
    if logRenderBuffer.len < logRenderWindow:
      logRenderBuffer.add(logEntry)
    else:
      logRenderBuffer[logRenderHead] = logEntry
      logRenderHead = (logRenderHead + 1) mod logRenderWindow
    logRenderCount = min(logRenderBuffer.len, logRenderWindow)

    if logRenderCount > 0:
      var output = newStringOfCap(logRenderCount * 512)
      output.add("=== tribal-village log window (" & $logRenderCount & " steps) ===\n")
      for i in 0 ..< logRenderCount:
        let renderIdx = (logRenderHead + i) mod logRenderCount
        output.add(logRenderBuffer[renderIdx])
        output.add("\n")
      writeFile(logRenderPath, output)

  env.maybeRenderConsole()
  when defined(gatherHeatmap):
    env.maybeRenderGatherHeatmap()

proc reset*(env: Environment) =
  maybeFinalizeReplay(env)
  env.currentStep = 0
  env.shouldReset = false
  env.rewards.clear()
  env.terminated.clear()
  env.truncated.clear()
  env.things.setLen(0)
  env.agents.setLen(0)
  env.stats.setLen(0)
  env.templeInteractions.setLen(0)
  env.templeHybridRequests.setLen(0)
  env.grid.clear()
  # Skip env.observations.clear() - rebuildObservations will zero when accessed
  # This is a lazy init optimization to reduce startup overhead
  env.observationsInitialized = false
  env.observationsDirty = true
  # Clear tint arrays in-place via zeroMem (avoids stack-allocated default() copies)
  env.tintMods.clear()
  env.tintStrength.clear()
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags.clear()
  env.tumorTintMods.clear()
  env.tumorStrength.clear()
  env.tumorActiveTiles.positions.setLen(0)
  env.tumorActiveTiles.flags.clear()
  env.projectiles.setLen(0)  # Keeps pre-allocated capacity
  env.projectilePool.stats = PoolStats()  # Reset pool stats
  env.damageNumbers.setLen(0)  # Keeps pre-allocated capacity
  env.debris.setLen(0)  # Keeps pre-allocated capacity
  env.spawnEffects.setLen(0)   # Keeps pre-allocated capacity
  # Reset herd/pack tracking
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
  env.wolfPackLeaders.setLen(0)
  # Reset team state (upgrades, techs, modifiers persist across resets without this)
  env.teamModifiers.clear()
  env.teamBlacksmithUpgrades.clear()
  env.teamUniversityTechs.clear()
  env.teamCastleTechs.clear()
  env.teamUnitUpgrades.clear()
  when defined(techAudit):
    resetTechAudit()
  # Clear colors
  env.agentColors.setLen(0)
  env.teamColors.setLen(0)
  env.altarColors.clear()
  env.territoryScore = default(TerritoryScore)
  env.territoryScored = false
  # Reset victory conditions
  env.victoryWinner = -1
  for teamId in 0 ..< MapRoomObjectsTeams:
    env.victoryStates[teamId].wonderBuiltStep = -1
    env.victoryStates[teamId].relicHoldStartStep = -1
    env.victoryStates[teamId].kingAgentId = -1
    env.victoryStates[teamId].hillControlStartStep = -1
  # Clear fog of war (revealed maps) via zeroMem
  env.revealedMaps.clear()
  # Clear UI selection and control groups to prevent stale references
  selection = @[]
  for i in 0 ..< ControlGroupCount:
    controlGroups[i] = @[]
  # Reset formation state for all control groups
  resetAllFormations()
  env.init()  # init() handles terrain, activeTiles, and tile colors
