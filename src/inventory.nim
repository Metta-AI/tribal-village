{.push inline.}
proc getInv*(thing: Thing, key: ItemKey): int =
  if key.len == 0:
    return 0
  if thing.inventory.hasKey(key):
    return thing.inventory[key]
  0

proc getInv*(thing: Thing, kind: ItemKind): int =
  ## Type-safe overload using ItemKind enum
  if kind == ikNone:
    return 0
  getInv(thing, toItemKey(kind))

proc setInv*(thing: Thing, key: ItemKey, value: int) =
  if key.len == 0:
    return
  if value <= 0:
    if thing.inventory.hasKey(key):
      thing.inventory.del(key)
  else:
    thing.inventory[key] = value

proc setInv*(thing: Thing, kind: ItemKind, value: int) =
  ## Type-safe overload using ItemKind enum
  if kind == ikNone:
    return
  setInv(thing, toItemKey(kind), value)

proc updateAgentInventoryObs*(env: Environment, agent: Thing, key: ItemKey) =
  ## Update observation layer for agent inventory - uses ItemKind enum for type safety
  let kind = toItemKind(key)
  let value = getInv(agent, key)
  case kind
  of ikGold:
    env.updateObservations(AgentInventoryGoldLayer, agent.pos, value)
  of ikStone:
    env.updateObservations(AgentInventoryStoneLayer, agent.pos, value)
  of ikBar:
    env.updateObservations(AgentInventoryBarLayer, agent.pos, value)
  of ikWater:
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, value)
  of ikWheat:
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, value)
  of ikWood:
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, value)
  of ikSpear:
    env.updateObservations(AgentInventorySpearLayer, agent.pos, value)
  of ikLantern:
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, value)
  of ikArmor:
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, value)
  of ikBread:
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, value)
  of ikMeat:
    env.updateObservations(AgentInventoryMeatLayer, agent.pos, value)
  of ikFish:
    env.updateObservations(AgentInventoryFishLayer, agent.pos, value)
  of ikPlant:
    env.updateObservations(AgentInventoryPlantLayer, agent.pos, value)
  else:
    discard  # Non-observed items (hearts, none)

proc updateAgentInventoryObs*(env: Environment, agent: Thing, kind: ItemKind) =
  ## Type-safe overload using ItemKind enum
  updateAgentInventoryObs(env, agent, toItemKey(kind))

proc stockpileCount*(env: Environment, teamId: int, res: StockpileResource): int =
  env.teamStockpiles[teamId].counts[res]

proc addToStockpile*(env: Environment, teamId: int, res: StockpileResource, amount: int) =
  env.teamStockpiles[teamId].counts[res] += amount

proc canSpendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  for cost in costs:
    if env.teamStockpiles[teamId].counts[cost.res] < cost.count:
      return false
  true

proc spendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  if not env.canSpendStockpile(teamId, costs):
    return false
  for cost in costs:
    env.teamStockpiles[teamId].counts[cost.res] -= cost.count
  true

proc canSpendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  for cost in costs:
    if not isStockpileResourceKey(cost.key):
      return false
    let res = stockpileResourceForItem(cost.key)
    if env.teamStockpiles[teamId].counts[res] < cost.count:
      return false
  true

proc spendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  if not env.canSpendStockpile(teamId, costs):
    return false
  for cost in costs:
    let res = stockpileResourceForItem(cost.key)
    env.teamStockpiles[teamId].counts[res] -= cost.count
  true

proc canSpendInventory*(agent: Thing, costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  for cost in costs:
    if getInv(agent, cost.key) < cost.count:
      return false
  true

proc spendInventory*(env: Environment, agent: Thing, costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  if not canSpendInventory(agent, costs):
    return false
  for cost in costs:
    setInv(agent, cost.key, getInv(agent, cost.key) - cost.count)
    env.updateAgentInventoryObs(agent, cost.key)
  true

proc applyUnitClass*(agent: Thing, unitClass: AgentUnitClass) =
  agent.unitClass = unitClass
  case unitClass
  of UnitVillager:
    agent.maxHp = VillagerMaxHp
    agent.attackDamage = VillagerAttackDamage
  of UnitManAtArms:
    agent.maxHp = ManAtArmsMaxHp
    agent.attackDamage = ManAtArmsAttackDamage
  of UnitArcher:
    agent.maxHp = ArcherMaxHp
    agent.attackDamage = ArcherAttackDamage
  of UnitScout:
    agent.maxHp = ScoutMaxHp
    agent.attackDamage = ScoutAttackDamage
  of UnitKnight:
    agent.maxHp = KnightMaxHp
    agent.attackDamage = KnightAttackDamage
  of UnitMonk:
    agent.maxHp = MonkMaxHp
    agent.attackDamage = MonkAttackDamage
  of UnitSiege:
    agent.maxHp = SiegeMaxHp
    agent.attackDamage = SiegeAttackDamage
  agent.hp = agent.maxHp
{.pop.}

template defineInventoryAccessors(name, key: untyped) =
  proc `name`*(agent: Thing): int =
    getInv(agent, key)

  proc `name=`*(agent: Thing, value: int) =
    setInv(agent, key, value)

defineInventoryAccessors(inventoryGold, ItemGold)
defineInventoryAccessors(inventoryStone, ItemStone)
defineInventoryAccessors(inventoryBar, ItemBar)
defineInventoryAccessors(inventoryWater, ItemWater)
defineInventoryAccessors(inventoryWheat, ItemWheat)
defineInventoryAccessors(inventoryWood, ItemWood)
defineInventoryAccessors(inventorySpear, ItemSpear)
defineInventoryAccessors(inventoryLantern, ItemLantern)
defineInventoryAccessors(inventoryArmor, ItemArmor)
defineInventoryAccessors(inventoryBread, ItemBread)
defineInventoryAccessors(hearts, ItemHearts)
