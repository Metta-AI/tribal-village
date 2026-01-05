proc resourceCarryTotal(agent: Thing): int =
  result = 0
  for key, count in agent.inventory.pairs:
    if count > 0 and isStockpileResourceKey(key):
      result += count

proc resourceCarryCapacityLeft(agent: Thing): int =
  max(0, ResourceCarryCapacity - resourceCarryTotal(agent))

proc canCarry(agent: Thing, key: ItemKey, count: int = 1): bool =
  if count <= 0:
    return true
  if isStockpileResourceKey(key):
    return resourceCarryTotal(agent) + count <= ResourceCarryCapacity
  getInv(agent, key) + count <= MapObjectAgentMaxInventory

proc giveItem(env: Environment, agent: Thing, key: ItemKey, count: int = 1): bool =
  if count <= 0 or not agent.canCarry(key, count):
    return false
  setInv(agent, key, getInv(agent, key) + count)
  env.updateAgentInventoryObs(agent, key)
  true

proc clearTerrain(env: Environment, pos: IVec2) =
  env.terrain[pos.x][pos.y] = Empty
  env.terrainResources[pos.x][pos.y] = 0

proc storageKeyAllowed(key: ItemKey, allowed: openArray[ItemKey]): bool =
  if allowed.len == 0:
    return true
  for allowedKey in allowed:
    if key == allowedKey:
      return true
  false

proc selectAllowedItem(agent: Thing, allowed: openArray[ItemKey]): tuple[key: ItemKey, count: int] =
  result = (key: ItemNone, count: 0)
  if allowed.len == 0:
    return agentMostHeldItem(agent)
  for key in allowed:
    let count = getInv(agent, key)
    if count > result.count:
      result = (key: key, count: count)

proc useStorageBuilding(env: Environment, agent: Thing, storage: Thing, allowed: openArray[ItemKey]): bool =
  if storage.inventory.len > 0:
    var storedKey = ItemNone
    var storedCount = 0
    for key, count in storage.inventory.pairs:
      if count > 0:
        storedKey = key
        storedCount = count
        break
    if storedKey.len == 0 or not storageKeyAllowed(storedKey, allowed):
      return false
    let agentCount = getInv(agent, storedKey)
    let storageSpace = max(0, storage.barrelCapacity - storedCount)
    if agentCount > 0 and storageSpace > 0:
      let moved = min(agentCount, storageSpace)
      setInv(agent, storedKey, agentCount - moved)
      setInv(storage, storedKey, storedCount + moved)
      env.updateAgentInventoryObs(agent, storedKey)
      return true
    let capacityLeft =
      if isStockpileResourceKey(storedKey):
        resourceCarryCapacityLeft(agent)
      else:
        max(0, MapObjectAgentMaxInventory - agentCount)
    if capacityLeft > 0:
      let moved = min(storedCount, capacityLeft)
      if moved > 0:
        setInv(agent, storedKey, agentCount + moved)
        let remaining = storedCount - moved
        setInv(storage, storedKey, remaining)
        env.updateAgentInventoryObs(agent, storedKey)
        return true
    return false

  let choice = selectAllowedItem(agent, allowed)
  if choice.count > 0 and choice.key != ItemNone:
    let moved = min(choice.count, storage.barrelCapacity)
    setInv(agent, choice.key, choice.count - moved)
    setInv(storage, choice.key, moved)
    env.updateAgentInventoryObs(agent, choice.key)
    return true
  false

proc useDropoffBuilding(env: Environment, agent: Thing, allowed: set[StockpileResource]): bool =
  let teamId = getTeamId(agent.agentId)
  var depositKeys: seq[ItemKey] = @[]
  for key, count in agent.inventory.pairs:
    if count <= 0:
      continue
    if not isStockpileResourceKey(key):
      continue
    let res = stockpileResourceForItem(key)
    if res in allowed:
      depositKeys.add(key)
  if depositKeys.len == 0:
    return false
  for key in depositKeys:
    let count = getInv(agent, key)
    if count <= 0:
      continue
    let res = stockpileResourceForItem(key)
    env.addToStockpile(teamId, res, count)
    setInv(agent, key, 0)
    env.updateAgentInventoryObs(agent, key)
  true
