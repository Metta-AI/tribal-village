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

proc addInv*(thing: Thing, key: ItemKey, delta: int): int =
  if key.len == 0 or delta == 0:
    return getInv(thing, key)
  let newVal = getInv(thing, key) + delta
  setInv(thing, key, newVal)
  newVal

proc addInv*(thing: Thing, kind: ItemKind, delta: int): int =
  ## Type-safe overload using ItemKind enum
  if kind == ikNone or delta == 0:
    return getInv(thing, kind)
  let newVal = getInv(thing, kind) + delta
  setInv(thing, kind, newVal)
  newVal

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
  else:
    discard  # Non-observed items (plant, fish, meat, hearts, none)

proc updateAgentInventoryObs*(env: Environment, agent: Thing, kind: ItemKind) =
  ## Type-safe overload using ItemKind enum
  updateAgentInventoryObs(env, agent, toItemKey(kind))

proc stockpileCount*(env: Environment, teamId: int, res: StockpileResource): int =
  if teamId < 0 or teamId >= env.teamStockpiles.len:
    return 0
  env.teamStockpiles[teamId].counts[res]

proc addToStockpile*(env: Environment, teamId: int, res: StockpileResource, amount: int) =
  if teamId < 0 or teamId >= env.teamStockpiles.len:
    return
  if amount <= 0:
    return
  env.teamStockpiles[teamId].counts[res] += amount

proc canSpendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  if teamId < 0 or teamId >= env.teamStockpiles.len:
    return false
  for cost in costs:
    if cost.count <= 0:
      continue
    if env.teamStockpiles[teamId].counts[cost.res] < cost.count:
      return false
  true

proc spendStockpile*(env: Environment, teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  if not env.canSpendStockpile(teamId, costs):
    return false
  for cost in costs:
    if cost.count <= 0:
      continue
    env.teamStockpiles[teamId].counts[cost.res] -= cost.count
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

proc hearts*(thing: Thing): int =
  getInv(thing, ItemHearts)

proc `hearts=`*(thing: Thing, value: int) =
  setInv(thing, ItemHearts, value)
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
