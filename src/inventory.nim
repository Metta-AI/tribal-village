proc getInv*(thing: Thing, key: ItemKey): int =
  if key.len == 0:
    return 0
  if thing.inventory.hasKey(key):
    return thing.inventory[key]
  0

proc setInv*(thing: Thing, key: ItemKey, value: int) =
  if key.len == 0:
    return
  if value <= 0:
    if thing.inventory.hasKey(key):
      thing.inventory.del(key)
  else:
    thing.inventory[key] = value

proc addInv*(thing: Thing, key: ItemKey, delta: int): int =
  if key.len == 0 or delta == 0:
    return getInv(thing, key)
  let newVal = getInv(thing, key) + delta
  setInv(thing, key, newVal)
  newVal

proc updateAgentInventoryObs*(env: Environment, agent: Thing, key: ItemKey) =
  if key == ItemGold:
    env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, key))
  elif key == ItemStone:
    env.updateObservations(AgentInventoryStoneLayer, agent.pos, getInv(agent, key))
  elif key == ItemBar:
    env.updateObservations(AgentInventoryBarLayer, agent.pos, getInv(agent, key))
  elif key == ItemWater:
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, getInv(agent, key))
  elif key == ItemWheat:
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, getInv(agent, key))
  elif key == ItemWood:
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, getInv(agent, key))
  elif key == ItemSpear:
    env.updateObservations(AgentInventorySpearLayer, agent.pos, getInv(agent, key))
  elif key == ItemLantern:
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, getInv(agent, key))
  elif key == ItemArmor:
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, getInv(agent, key))
  elif key == ItemBread:
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, getInv(agent, key))

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

proc teamPopulation*(env: Environment, teamId: int): int =
  result = 0
  for agent in env.agents:
    if agent.isNil:
      continue
    if env.terminated[agent.agentId] != 0.0:
      continue
    if getTeamId(agent.agentId) == teamId:
      inc result

proc teamPopCap*(env: Environment, teamId: int): int =
  var cap = 0
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId != teamId:
      continue
    case thing.kind
    of TownCenter:
      cap += TownCenterPopCap
    of House:
      cap += HousePopCap
    else:
      discard
  cap

proc agentMostHeldItem(agent: Thing): tuple[key: ItemKey, count: int] =
  ## Pick the item with the highest count to deposit into an empty barrel.
  result = (key: ItemNone, count: 0)
  for key, count in agent.inventory.pairs:
    if count > result.count:
      result = (key: key, count: count)

proc hearts*(thing: Thing): int =
  getInv(thing, ItemHearts)

proc `hearts=`*(thing: Thing, value: int) =
  setInv(thing, ItemHearts, value)

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
