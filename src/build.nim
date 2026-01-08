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

let BuildChoices*: array[ActionArgumentCount, ItemKey] = block:
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
