proc buildCostsForKey(key: ItemKey): seq[tuple[res: StockpileResource, count: int]] =
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

let BuildChoices*: array[ActionArgumentCount, ItemKey] = [
  thingItem("House"),
  thingItem("TownCenter"),
  thingItem("Mill"),
  thingItem("LumberCamp"),
  thingItem("MiningCamp"),
  thingItem("Farm"),
  thingItem("Dock"),
  thingItem("Market"),
  thingItem("Barracks"),
  thingItem("ArcheryRange"),
  thingItem("Stable"),
  thingItem("SiegeWorkshop"),
  thingItem("Castle"),
  thingItem("Outpost"),
  thingItem("Wall"),
  thingItem("Road"),
  thingItem("Blacksmith"),
  thingItem("Monastery"),
  thingItem("University"),
  thingItem("Armory"),
  thingItem("ClayOven"),
  thingItem("WeavingLoom"),
  thingItem("Table"),
  thingItem("Bed"),
  thingItem("Chair"),
  thingItem("Statue"),
  thingItem("Barrel"),
  ItemNone
]

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

  let targetPos = agent.pos + orientationToVec(agent.orientation)
  if not isValidPos(targetPos):
    inc env.stats[id].actionInvalid
    return
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos):
    inc env.stats[id].actionInvalid
    return
  if env.terrain[targetPos.x][targetPos.y] != Empty or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]):
    inc env.stats[id].actionInvalid
    return
  if isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  let roadKey = thingItem("Road")
  if key != roadKey:
    var kind: ThingKind
    if not parseThingKey(key, kind):
      inc env.stats[id].actionInvalid
      return

  let costs = buildCostsForKey(key)
  if costs.len == 0:
    inc env.stats[id].actionInvalid
    return
  let teamId = getTeamId(agent.agentId)
  if not env.canSpendStockpile(teamId, costs):
    inc env.stats[id].actionInvalid
    return

  discard env.spendStockpile(teamId, costs)
  if placeThingFromKey(env, agent, key, targetPos):
    inc env.stats[id].actionBuild
  else:
    inc env.stats[id].actionInvalid
