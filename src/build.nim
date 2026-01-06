proc buildCostsForKey*(key: ItemKey): seq[tuple[res: StockpileResource, count: int]] =
  for recipe in CraftRecipes:
    for output in recipe.outputs:
      if output.key != key:
        continue
      var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
      for input in recipe.inputs:
        if not isStockpileResourceKey(input.key):
          continue
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
      return costs
  @[]

const
  BuildIndexWall* = 14
  BuildIndexRoad* = 15
  BuildIndexDoor* = 19

proc initBuildChoices(): array[ActionArgumentCount, ItemKey] =
  var choices: array[ActionArgumentCount, ItemKey]
  for i in 0 ..< choices.len:
    choices[i] = ItemNone
  for kind in ThingKind:
    if not isBuildingKind(kind):
      continue
    if not buildingBuildable(kind):
      continue
    let idx = BuildingRegistry[kind].buildIndex
    if idx >= 0 and idx < choices.len:
      choices[idx] = thingItem($kind)
  choices[BuildIndexWall] = thingItem("Wall")
  choices[BuildIndexRoad] = thingItem("Road")
  choices[BuildIndexDoor] = ItemDoor
  choices

let BuildChoices*: array[ActionArgumentCount, ItemKey] = initBuildChoices()

proc buildFromChoices(env: Environment, id: int, agent: Thing, argument: int,
                      choices: array[ActionArgumentCount, ItemKey]) =
  if argument < 0 or argument >= choices.len:
    inc env.stats[id].actionInvalid
    return
  if agent.unitClass != UnitVillager:
    inc env.stats[id].actionInvalid
    return
  let key = choices[argument]
  if key == ItemNone:
    inc env.stats[id].actionInvalid
    return

  let roadKey = thingItem("Road")
  if key != roadKey and key != ItemDoor:
    var kind: ThingKind
    if not parseThingKey(key, kind):
      inc env.stats[id].actionInvalid
      return

  proc isBuildablePos(pos: IVec2): bool =
    if not isValidPos(pos):
      return false
    if not env.isEmpty(pos) or env.hasDoor(pos) or isTileFrozen(pos, env):
      return false
    let terrain = env.terrain[pos.x][pos.y]
    terrain in {Empty, Grass, Sand, Snow, Dune, Stalagmite, Road}

  proc canLayRoad(pos: IVec2): bool =
    if not isValidPos(pos):
      return false
    if env.hasDoor(pos):
      return false
    if not env.isEmpty(pos):
      return false
    let terrain = env.terrain[pos.x][pos.y]
    terrain in {Empty, Grass, Sand, Snow, Dune, Stalagmite, Road}

  proc signi(x: int32): int32 =
    if x < 0: -1
    elif x > 0: 1
    else: 0

  proc nearestTeamAnchor(teamId: int, fromPos: IVec2): IVec2 =
    var best = ivec2(-1, -1)
    var bestDist = int.high
    for thing in env.things:
      if thing.teamId != teamId:
        continue
      if thing.kind notin {TownCenter, Altar}:
        continue
      let dist = abs(thing.pos.x - fromPos.x) + abs(thing.pos.y - fromPos.y)
      if dist < bestDist:
        bestDist = dist
        best = thing.pos
    if best.x < 0:
      return fromPos
    best

  proc layRoadBetween(startPos, endPos: IVec2) =
    var pos = startPos
    while pos.x != endPos.x:
      pos.x += signi(endPos.x - pos.x)
      if canLayRoad(pos):
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)
    while pos.y != endPos.y:
      pos.y += signi(endPos.y - pos.y)
      if canLayRoad(pos):
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)

  var offsets: seq[IVec2] = @[]
  proc addOffset(offset: IVec2) =
    if offset.x == 0'i32 and offset.y == 0'i32:
      return
    for existing in offsets:
      if existing == offset:
        return
    offsets.add(offset)

  addOffset(orientationToVec(agent.orientation))
  addOffset(ivec2(0, -1))
  addOffset(ivec2(1, 0))
  addOffset(ivec2(0, 1))
  addOffset(ivec2(-1, 0))
  addOffset(ivec2(-1, -1))
  addOffset(ivec2(1, -1))
  addOffset(ivec2(-1, 1))
  addOffset(ivec2(1, 1))

  var targetPos = ivec2(-1, -1)
  for offset in offsets:
    let pos = agent.pos + offset
    if isBuildablePos(pos):
      targetPos = pos
      break
  if targetPos.x < 0:
    inc env.stats[id].actionInvalid
    return

  let teamId = getTeamId(agent.agentId)
  if key == ItemDoor:
    if not canLayRoad(targetPos):
      inc env.stats[id].actionInvalid
      return
    let doorCost = @[(res: ResourceWood, count: 1)]
    if not env.canSpendStockpile(teamId, doorCost):
      inc env.stats[id].actionInvalid
      return
    discard env.spendStockpile(teamId, doorCost)
    env.doorTeams[targetPos.x][targetPos.y] = teamId.int16
    env.doorHearts[targetPos.x][targetPos.y] = DoorMaxHearts.int8
    inc env.stats[id].actionBuild
    return

  let costs = buildCostsForKey(key)
  if costs.len == 0:
    inc env.stats[id].actionInvalid
    return
  if not env.canSpendStockpile(teamId, costs):
    inc env.stats[id].actionInvalid
    return

  discard env.spendStockpile(teamId, costs)
  if placeThingFromKey(env, agent, key, targetPos):
    var kind: ThingKind
    if parseThingKey(key, kind):
      if kind in {Mill, LumberCamp, MiningCamp}:
        let anchor = nearestTeamAnchor(getTeamId(agent.agentId), targetPos)
        layRoadBetween(targetPos, anchor)
    inc env.stats[id].actionBuild
  else:
    inc env.stats[id].actionInvalid
