# This file is included by src/ai_defaults.nim
## Meta-role definitions and behavior registry for evolutionary roles.
import std/json

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
    fitness*: float32
    games*: int
    uses*: int

  RoleTier* = object
    behaviorIds*: seq[int]
    weights*: seq[float32]
    selection*: TierSelection

  RoleDef* = object
    id*: int
    name*: string
    kind*: AgentRole
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
    option: option,
    fitness: 0,
    games: 0,
    uses: 0
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
  resultName = stripPrefix(resultName, "Behavior")
  resultName = stripPrefix(resultName, "Gatherer")
  resultName = stripPrefix(resultName, "Builder")
  resultName = stripPrefix(resultName, "Fighter")
  if resultName.len == 0:
    return name
  resultName

proc findRoleId*(catalog: RoleCatalog, name: string): int =
  for role in catalog.roles:
    if role.name == name:
      return role.id
  -1

proc behaviorSelectionWeight*(behavior: BehaviorDef): float32 =
  if behavior.games <= 0:
    return 1.0
  max(0.1, behavior.fitness)

proc recordBehaviorScore*(behavior: var BehaviorDef, score: float32,
                          alpha: float32 = 0.2, weight: int = 1) =
  let count = max(1, weight)
  for _ in 0 ..< count:
    inc behavior.games
    if behavior.games == 1:
      behavior.fitness = score
    else:
      behavior.fitness = behavior.fitness * (1 - alpha) + score * alpha

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
                 origin: string, kind: AgentRole = Scripted): RoleDef =
  result = RoleDef(
    id: catalog.nextRoleId,
    name: name,
    kind: kind,
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
  var nextRole = role
  nextRole.id = id
  catalog.roles.add nextRole
  catalog.nextRoleId = catalog.roles.len
  id

proc tierSelectionToString(selection: TierSelection): string =
  case selection
  of TierFixed: "fixed"
  of TierShuffle: "shuffle"
  of TierWeighted: "weighted"

proc parseTierSelection(value: string): TierSelection =
  case value.toLowerAscii()
  of "shuffle": TierShuffle
  of "weighted": TierWeighted
  else: TierFixed

proc roleKindToString(kind: AgentRole): string =
  case kind
  of Gatherer: "gatherer"
  of Builder: "builder"
  of Fighter: "fighter"
  of Scripted: "scripted"

proc parseRoleKind(value: string): AgentRole =
  case value.toLowerAscii()
  of "gatherer": Gatherer
  of "builder": Builder
  of "fighter": Fighter
  of "scripted": Scripted
  else: Scripted

proc roleTierToJson(tier: RoleTier, catalog: RoleCatalog): JsonNode =
  result = newJObject()
  result["selection"] = %tierSelectionToString(tier.selection)
  var behaviors = newJArray()
  for id in tier.behaviorIds:
    if id >= 0 and id < catalog.behaviors.len:
      behaviors.add %catalog.behaviors[id].name
  result["behaviors"] = behaviors
  if tier.weights.len > 0:
    var weights = newJArray()
    for w in tier.weights:
      weights.add %w
    result["weights"] = weights

proc roleToJson(role: RoleDef, catalog: RoleCatalog): JsonNode =
  result = newJObject()
  result["name"] = %role.name
  result["kind"] = %roleKindToString(role.kind)
  result["origin"] = %role.origin
  result["locked"] = %role.lockedName
  result["fitness"] = %role.fitness
  result["games"] = %role.games
  result["wins"] = %role.wins
  var tiers = newJArray()
  for tier in role.tiers:
    tiers.add roleTierToJson(tier, catalog)
  result["tiers"] = tiers

proc behaviorToJson(behavior: BehaviorDef): JsonNode =
  result = newJObject()
  result["name"] = %behavior.name
  result["fitness"] = %behavior.fitness
  result["games"] = %behavior.games
  result["uses"] = %behavior.uses

proc saveRoleHistory*(catalog: RoleCatalog, path: string) =
  let dir = splitFile(path).dir
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  var root = newJObject()
  var roles = newJArray()
  for role in catalog.roles:
    roles.add roleToJson(role, catalog)
  var behaviors = newJArray()
  for behavior in catalog.behaviors:
    behaviors.add behaviorToJson(behavior)
  root["roles"] = roles
  root["behaviors"] = behaviors
  root["nextNameId"] = %catalog.nextNameId
  writeFile(path, $root)

proc applyBehaviorHistory(catalog: var RoleCatalog, node: JsonNode) =
  if node.kind != JObject:
    return
  if not node.hasKey("behaviors"):
    return
  for entry in node["behaviors"].items:
    if entry.kind != JObject:
      continue
    let name = entry{"name"}.getStr()
    let idx = findBehaviorId(catalog, name)
    if idx < 0:
      continue
    if entry.hasKey("fitness"):
      catalog.behaviors[idx].fitness = entry["fitness"].getFloat().float32
    if entry.hasKey("games"):
      catalog.behaviors[idx].games = entry["games"].getInt()
    if entry.hasKey("uses"):
      catalog.behaviors[idx].uses = entry["uses"].getInt()

proc parseRoleTiers(catalog: RoleCatalog, node: JsonNode): seq[RoleTier] =
  if node.kind != JArray:
    return @[]
  for entry in node.items:
    if entry.kind != JObject:
      continue
    var tier = RoleTier(behaviorIds: @[], weights: @[], selection: TierFixed)
    if entry.hasKey("selection"):
      tier.selection = parseTierSelection(entry["selection"].getStr())
    if entry.hasKey("behaviors"):
      for behaviorNode in entry["behaviors"].items:
        let name = behaviorNode.getStr()
        let id = findBehaviorId(catalog, name)
        if id >= 0:
          tier.behaviorIds.add id
    if entry.hasKey("weights"):
      for weightNode in entry["weights"].items:
        tier.weights.add weightNode.getFloat().float32
    if tier.behaviorIds.len > 0:
      result.add tier

proc applyRoleHistory(catalog: var RoleCatalog, node: JsonNode) =
  if node.kind != JObject:
    return
  if not node.hasKey("roles"):
    return
  for entry in node["roles"].items:
    if entry.kind != JObject:
      continue
    let name = entry{"name"}.getStr()
    let existing = findRoleId(catalog, name)
    if existing >= 0:
      if entry.hasKey("kind"):
        catalog.roles[existing].kind = parseRoleKind(entry["kind"].getStr())
      if entry.hasKey("fitness"):
        catalog.roles[existing].fitness = entry["fitness"].getFloat().float32
      if entry.hasKey("games"):
        catalog.roles[existing].games = entry["games"].getInt()
      if entry.hasKey("wins"):
        catalog.roles[existing].wins = entry["wins"].getInt()
      if entry.hasKey("locked"):
        catalog.roles[existing].lockedName = entry["locked"].getBool()
      continue
    let tiers = parseRoleTiers(catalog, entry{"tiers"})
    if tiers.len == 0:
      continue
    let origin = entry{"origin"}.getStr()
    var kind = Scripted
    if entry.hasKey("kind"):
      kind = parseRoleKind(entry["kind"].getStr())
    var role = newRoleDef(catalog, name, tiers, origin, kind)
    if entry.hasKey("fitness"):
      role.fitness = entry["fitness"].getFloat().float32
    if entry.hasKey("games"):
      role.games = entry["games"].getInt()
    if entry.hasKey("wins"):
      role.wins = entry["wins"].getInt()
    if entry.hasKey("locked"):
      role.lockedName = entry["locked"].getBool()
    discard registerRole(catalog, role)

proc loadRoleHistory*(catalog: var RoleCatalog, path: string) =
  if not fileExists(path):
    return
  let raw = readFile(path)
  if raw.len == 0:
    return
  let node = parseJson(raw)
  applyBehaviorHistory(catalog, node)
  applyRoleHistory(catalog, node)
  if node.kind == JObject and node.hasKey("nextNameId"):
    catalog.nextNameId = node["nextNameId"].getInt()

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
