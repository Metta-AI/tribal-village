proc putAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Give items to adjacent teammate. Argument is direction (0..7)
  if argument > 7:
    inc env.stats[id].actionInvalid
    return
  let dir = Orientation(argument)
  let delta = getOrientationDelta(dir)
  let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return
  let target = env.getThing(targetPos)
  if isNil(target):
    inc env.stats[id].actionInvalid
    return
  if target.kind != Agent or isThingFrozen(target, env):
    inc env.stats[id].actionInvalid
    return
  var transferred = false
  # Give armor if we have any and target has none
  if agent.inventoryArmor > 0 and target.inventoryArmor == 0:
    target.inventoryArmor = agent.inventoryArmor
    agent.inventoryArmor = 0
    transferred = true
  # Otherwise give food if possible (no obs layer yet)
  elif agent.inventoryBread > 0:
    let capacity = resourceCarryCapacityLeft(target)
    let giveAmt = min(agent.inventoryBread, capacity)
    if giveAmt > 0:
      agent.inventoryBread = agent.inventoryBread - giveAmt
      target.inventoryBread = target.inventoryBread + giveAmt
      transferred = true
  else:
    var bestKey = ItemNone
    var bestCount = 0
    for key, count in agent.inventory.pairs:
      if count <= 0:
        continue
      let capacity =
        if isStockpileResourceKey(key):
          resourceCarryCapacityLeft(target)
        else:
          MapObjectAgentMaxInventory - getInv(target, key)
      if capacity <= 0:
        continue
      if count > bestCount:
        bestKey = key
        bestCount = count
    if bestKey != ItemNone and bestCount > 0:
      let capacity =
        if isStockpileResourceKey(bestKey):
          resourceCarryCapacityLeft(target)
        else:
          max(0, MapObjectAgentMaxInventory - getInv(target, bestKey))
      if capacity > 0:
        let moved = min(bestCount, capacity)
        setInv(agent, bestKey, bestCount - moved)
        setInv(target, bestKey, getInv(target, bestKey) + moved)
        env.updateAgentInventoryObs(agent, bestKey)
        env.updateAgentInventoryObs(target, bestKey)
        transferred = true
  if transferred:
    inc env.stats[id].actionPut
    # Update observations for changed inventories
    env.updateAgentInventoryObs(agent, ItemArmor)
    env.updateAgentInventoryObs(agent, ItemBread)
    env.updateAgentInventoryObs(target, ItemArmor)
    env.updateAgentInventoryObs(target, ItemBread)
  else:
    inc env.stats[id].actionInvalid
