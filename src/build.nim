proc buildCostsForKey*(key: ItemKey): seq[tuple[res: StockpileResource, count: int]] =
  var kind: ThingKind
  if parseThingKey(key, kind) and isBuildingKind(kind):
    var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
    for input in BuildingRegistry[kind].buildCost:
      if isStockpileResourceKey(input.key):
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
    return costs
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
  choices[BuildIndexDoor] = thingItem("Door")
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
  if key != roadKey:
    var kind: ThingKind
    if not parseThingKey(key, kind):
      inc env.stats[id].actionInvalid
      return

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
      if env.canLayRoad(pos):
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)
    while pos.y != endPos.y:
      pos.y += signi(endPos.y - pos.y)
      if env.canLayRoad(pos):
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
    if env.canPlaceBuilding(pos):
      targetPos = pos
      break
  if targetPos.x < 0:
    inc env.stats[id].actionInvalid
    return

  let teamId = getTeamId(agent.agentId)
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
