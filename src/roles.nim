# This file is included by src/ai_defaults.nim
## Meta-role definitions and behavior registry for evolutionary roles.

type
  BehaviorSource* = enum
    BehaviorGatherer
    BehaviorBuilder
    BehaviorFighter
    BehaviorCustom

  TierSelection* = enum
    TierFixed       # Keep behavior order as provided
    TierShuffle     # Shuffle behavior order per materialization
    TierWeighted    # Weighted shuffle using tier weights

  BehaviorDef* = object
    id*: int
    name*: string
    source*: BehaviorSource
    option*: OptionDef

  RoleTier* = object
    behaviorIds*: seq[int]
    weights*: seq[float32]
    selection*: TierSelection

  RoleDef* = object
    id*: int
    name*: string
    tiers*: seq[RoleTier]
    origin*: string
    lockedName*: bool
    fitness*: float32
    games*: int
    wins*: int

  RoleCatalog* = object
    behaviors*: seq[BehaviorDef]
    roles*: seq[RoleDef]
    nextRoleId*: int
    nextNameId*: int

proc initRoleCatalog*(): RoleCatalog =
  RoleCatalog(nextRoleId: 0, nextNameId: 0)

proc findBehaviorId*(catalog: RoleCatalog, name: string): int =
  for behavior in catalog.behaviors:
    if behavior.name == name:
      return behavior.id
  -1

proc addBehavior*(catalog: var RoleCatalog, option: OptionDef,
                  source: BehaviorSource): int =
  let existing = findBehaviorId(catalog, option.name)
  if existing >= 0:
    return existing
  let id = catalog.behaviors.len
  catalog.behaviors.add BehaviorDef(
    id: id,
    name: option.name,
    source: source,
    option: option
  )
  id

proc addBehaviorSet*(catalog: var RoleCatalog, options: openArray[OptionDef],
                     source: BehaviorSource) =
  for opt in options:
    discard catalog.addBehavior(opt, source)

proc stripPrefix(name, prefix: string): string =
  if name.len >= prefix.len and name[0 ..< prefix.len] == prefix:
    if prefix.len <= name.high:
      return name[prefix.len .. ^1]
    return ""
  name

proc shortBehaviorName*(name: string): string =
  var resultName = name
  resultName = stripPrefix(resultName, "Gatherer")
  resultName = stripPrefix(resultName, "Builder")
  resultName = stripPrefix(resultName, "Fighter")
  if resultName.len == 0:
    return name
  resultName

proc generateRoleName*(catalog: var RoleCatalog, tiers: seq[RoleTier]): string =
  var baseName = "Role"
  if tiers.len > 0 and tiers[0].behaviorIds.len > 0:
    let id = tiers[0].behaviorIds[0]
    if id >= 0 and id < catalog.behaviors.len:
      baseName = shortBehaviorName(catalog.behaviors[id].name)
  let suffix = catalog.nextNameId
  inc catalog.nextNameId
  baseName & "-" & $suffix

proc newRoleDef*(catalog: var RoleCatalog, name: string, tiers: seq[RoleTier],
                 origin: string): RoleDef =
  result = RoleDef(
    id: catalog.nextRoleId,
    name: name,
    tiers: tiers,
    origin: origin,
    lockedName: false,
    fitness: 0,
    games: 0,
    wins: 0
  )
  inc catalog.nextRoleId

proc registerRole*(catalog: var RoleCatalog, role: RoleDef): int =
  let id = catalog.roles.len
  catalog.roles.add role
  id

proc shuffleIds(rng: var Rand, ids: var seq[int]) =
  if ids.len < 2:
    return
  var i = ids.high
  while i > 0:
    let j = randIntInclusive(rng, 0, i)
    let tmp = ids[i]
    ids[i] = ids[j]
    ids[j] = tmp
    dec i

proc weightedPickIndex(rng: var Rand, weights: openArray[float32]): int =
  if weights.len == 0:
    return 0
  var total = 0.0
  for w in weights:
    if w > 0:
      total += float64(w)
  if total <= 0:
    return randIntExclusive(rng, 0, weights.len)
  let roll = randFloat(rng) * total
  var acc = 0.0
  for i, w in weights:
    if w <= 0:
      continue
    acc += float64(w)
    if roll <= acc:
      return i
  weights.len - 1

proc resolveTierOrder(rng: var Rand, tier: RoleTier): seq[int] =
  if tier.behaviorIds.len == 0:
    return @[]
  case tier.selection
  of TierFixed:
    result = tier.behaviorIds
  of TierShuffle:
    result = tier.behaviorIds
    shuffleIds(rng, result)
  of TierWeighted:
    var ids = tier.behaviorIds
    var weights: seq[float32]
    if tier.weights.len == ids.len:
      weights = tier.weights
    else:
      weights = newSeq[float32](ids.len)
      for i in 0 ..< weights.len:
        weights[i] = 1
    while ids.len > 0:
      let idx = weightedPickIndex(rng, weights)
      result.add ids[idx]
      ids.delete(idx)
      weights.delete(idx)

proc materializeRoleOptions*(catalog: RoleCatalog, role: RoleDef,
                             rng: var Rand, maxOptions: int = 0): seq[OptionDef] =
  for tier in role.tiers:
    let orderedIds = resolveTierOrder(rng, tier)
    for id in orderedIds:
      if id >= 0 and id < catalog.behaviors.len:
        result.add catalog.behaviors[id].option
        if maxOptions > 0 and result.len >= maxOptions:
          return

proc seedDefaultBehaviorCatalog*(catalog: var RoleCatalog) =
  when declared(GathererOptions):
    catalog.addBehaviorSet(GathererOptions, BehaviorGatherer)
  when declared(BuilderOptions):
    catalog.addBehaviorSet(BuilderOptions, BehaviorBuilder)
  when declared(FighterOptions):
    catalog.addBehaviorSet(FighterOptions, BehaviorFighter)
  when declared(MetaBehaviorOptions):
    catalog.addBehaviorSet(MetaBehaviorOptions, BehaviorCustom)
