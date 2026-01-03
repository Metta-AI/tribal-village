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

const
  BuildIndexOutpost* = 13
  BuildIndexRoad* = 15

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

  proc isBuildablePos(pos: IVec2): bool =
    if not isValidPos(pos):
      return false
    if not env.isEmpty(pos) or env.hasDoor(pos) or isTileFrozen(pos, env):
      return false
    let terrain = env.terrain[pos.x][pos.y]
    terrain in {Empty, Grass, Sand, Snow}

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
