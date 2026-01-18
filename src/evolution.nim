# This file is included by src/ai_defaults.nim
## Evolution helpers for sampling and recombining role definitions.

type
  EvolutionConfig* = object
    minTiers*: int
    maxTiers*: int
    minTierSize*: int
    maxTierSize*: int
    mutationRate*: float32
    lockFitnessThreshold*: float32

proc defaultEvolutionConfig*(): EvolutionConfig =
  EvolutionConfig(
    minTiers: 2,
    maxTiers: 4,
    minTierSize: 1,
    maxTierSize: 3,
    mutationRate: 0.15,
    lockFitnessThreshold: 0.7
  )

proc sampleUniqueIds(rng: var Rand, maxId: int, count: int,
                     used: var seq[int]): seq[int] =
  if maxId <= 0 or count <= 0:
    return @[]
  var attempts = 0
  let maxAttempts = maxId * 4
  while result.len < count and attempts < maxAttempts:
    let id = randIntExclusive(rng, 0, maxId)
    var exists = false
    for usedId in used:
      if usedId == id:
        exists = true
        break
    if not exists:
      used.add id
      result.add id
    inc attempts
  if result.len == 0:
    let fallback = randIntExclusive(rng, 0, maxId)
    result.add fallback
    used.add fallback

proc sampleRole*(catalog: var RoleCatalog, rng: var Rand,
                 config: EvolutionConfig = defaultEvolutionConfig()): RoleDef =
  let behaviorCount = catalog.behaviors.len
  if behaviorCount == 0:
    return RoleDef(name: "EmptyRole")
  let tierCount = randIntInclusive(rng, config.minTiers, config.maxTiers)
  var tiers: seq[RoleTier] = @[]
  var used: seq[int] = @[]
  for _ in 0 ..< tierCount:
    let tierSize = randIntInclusive(rng, config.minTierSize, config.maxTierSize)
    let ids = sampleUniqueIds(rng, behaviorCount, min(tierSize, behaviorCount), used)
    let selection = if randChance(rng, 0.5): TierShuffle else: TierFixed
    tiers.add RoleTier(behaviorIds: ids, selection: selection)
  let name = generateRoleName(catalog, tiers)
  newRoleDef(catalog, name, tiers, "sampled")

proc recombineRoles*(catalog: var RoleCatalog, rng: var Rand,
                     left, right: RoleDef): RoleDef =
  if left.tiers.len == 0 and right.tiers.len == 0:
    return RoleDef(name: "EmptyRole")
  if left.tiers.len == 0:
    return right
  if right.tiers.len == 0:
    return left
  let cutLeft = randIntInclusive(rng, 0, left.tiers.len)
  let cutRight = randIntInclusive(rng, 0, right.tiers.len)
  var tiers: seq[RoleTier] = @[]
  if cutLeft > 0:
    tiers.add left.tiers[0 ..< cutLeft]
  if cutRight < right.tiers.len:
    tiers.add right.tiers[cutRight .. ^1]
  if tiers.len == 0:
    tiers.add left.tiers[0]
  let name = generateRoleName(catalog, tiers)
  newRoleDef(catalog, name, tiers, "recombined")

proc mutateRole*(catalog: RoleCatalog, rng: var Rand, role: RoleDef,
                 mutationRate: float32 = 0.15): RoleDef =
  result = role
  if catalog.behaviors.len == 0:
    return
  for i in 0 ..< result.tiers.len:
    if result.tiers[i].behaviorIds.len == 0:
      continue
    if randChance(rng, mutationRate):
      let idx = randIntExclusive(rng, 0, result.tiers[i].behaviorIds.len)
      let replacement = randIntExclusive(rng, 0, catalog.behaviors.len)
      result.tiers[i].behaviorIds[idx] = replacement
    if randChance(rng, mutationRate * 0.5):
      result.tiers[i].selection = if result.tiers[i].selection == TierFixed: TierShuffle else: TierFixed

proc recordRoleScore*(role: var RoleDef, score: float32,
                      won: bool, alpha: float32 = 0.2) =
  inc role.games
  if won:
    inc role.wins
  if role.games == 1:
    role.fitness = score
  else:
    role.fitness = role.fitness * (1 - alpha) + score * alpha

proc lockRoleNameIfFit*(role: var RoleDef, threshold: float32) =
  if role.fitness >= threshold:
    role.lockedName = true

proc roleSelectionWeight*(role: RoleDef): float32 =
  if role.games <= 0:
    return 0.1
  max(0.1, role.fitness)
