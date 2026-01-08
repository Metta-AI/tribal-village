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
  let key = choices[argument]

  let roadKey = thingItem("Road")

  var offsets: seq[IVec2] = @[]
  for offset in [
    orientationToVec(agent.orientation),
    ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
    ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1)
  ]:
    if offset.x == 0'i32 and offset.y == 0'i32:
      continue
    var exists = false
    for existing in offsets:
      if existing == offset:
        exists = true
        break
    if not exists:
      offsets.add(offset)

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
        var anchor = ivec2(-1, -1)
        var bestDist = int.high
        for thing in env.things:
          if thing.teamId != teamId:
            continue
          if thing.kind notin {TownCenter, Altar}:
            continue
          let dist = abs(thing.pos.x - targetPos.x) + abs(thing.pos.y - targetPos.y)
          if dist < bestDist:
            bestDist = dist
            anchor = thing.pos
        if anchor.x < 0:
          anchor = targetPos
        var pos = targetPos
        while pos.x != anchor.x:
          pos.x += (if anchor.x < pos.x: -1'i32 elif anchor.x > pos.x: 1'i32 else: 0'i32)
          if env.canLayRoad(pos):
            env.terrain[pos.x][pos.y] = Road
            env.resetTileColor(pos)
        while pos.y != anchor.y:
          pos.y += (if anchor.y < pos.y: -1'i32 elif anchor.y > pos.y: 1'i32 else: 0'i32)
          if env.canLayRoad(pos):
            env.terrain[pos.x][pos.y] = Road
            env.resetTileColor(pos)
    inc env.stats[id].actionBuild
  else:
    inc env.stats[id].actionInvalid
