proc useAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Use terrain or building with a single action (requires holding needed resource if any)
  if argument > 7:
    inc env.stats[id].actionInvalid
    return

  # Calculate target position based on orientation argument
  let useOrientation = Orientation(argument)
  let delta = getOrientationDelta(useOrientation)
  var targetPos = agent.pos
  targetPos.x += int32(delta.x)
  targetPos.y += int32(delta.y)

  # Check bounds
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return

  # Frozen tiles are non-interactable (terrain or things sitting on them)
  if isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  let thing = env.getThing(targetPos)
  if isNil(thing):
    # Terrain use only when no Thing occupies the tile.
    var used = false
    case env.terrain[targetPos.x][targetPos.y]:
    of Water:
      if env.giveItem(agent, ItemWater):
        agent.reward += env.config.waterReward
        used = true
      elif env.giveItem(agent, ItemFish):
        used = true
    of Wheat:
      used = env.tryHarvestWithCarry(agent, targetPos, ItemWheat, 2, env.config.wheatReward) or
        env.tryGiveFirstAndClear(agent, targetPos, [ItemSeeds, ItemPlant])
    of Tree, Palm:
      used = env.tryHarvestWithCarry(agent, targetPos, ItemWood, 2, env.config.woodReward) or
        env.tryGiveFirstAndClear(agent, targetPos, [ItemBranch])
    of Rock, Stalagmite:
      used = env.tryGiveFirstAndClear(agent, targetPos, [ItemBoulder, ItemRock])
    of Gem:
      used = env.tryGiveAndClear(agent, targetPos, ItemRock)
    of Bush, Cactus:
      used = env.tryGiveFirstAndClear(agent, targetPos, [ItemSeeds, ItemPlant])
    of Animal:
      used = env.tryGiveFirstAndClear(agent, targetPos, [ItemMeat, ItemCorpse, ItemEgg])
    of Empty:
      if env.hasDoor(targetPos):
        used = false
      elif agent.inventoryBread > 0:
        agent.inventoryBread = max(0, agent.inventoryBread - 1)
        env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
        env.applyHealBurst(agent)
        used = true
      else:
        if agent.inventoryWater > 0:
          agent.inventoryWater = max(0, agent.inventoryWater - 1)
          env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)
          env.terrain[targetPos.x][targetPos.y] = Fertile
          env.resetTileColor(targetPos)
          env.updateObservations(TintLayer, targetPos, 0)
          used = true
    of Bridge, Fertile, Road, Grass, Dune, Sand, Snow:
      used = false

    if used:
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
    return
  # Building use
  # Prevent interacting with frozen objects/buildings
  if isThingFrozen(thing, env):
    inc env.stats[id].actionInvalid
    return

  var used = false
  case thing.kind:
  of Pine, Palm:
    removeThing(env, thing)
    env.dropStump(thing.pos, 5)
    used = true
  of Stump:
    let stored = getInv(thing, ItemWood)
    if stored > 0:
      let capacity = resourceCarryCapacityLeft(agent)
      if capacity > 0:
        let moved = min(stored, capacity)
        setInv(agent, ItemWood, getInv(agent, ItemWood) + moved)
        setInv(thing, ItemWood, stored - moved)
        env.updateAgentInventoryObs(agent, ItemWood)
        agent.reward += env.config.woodReward
        if getInv(thing, ItemWood) == 0:
          removeThing(env, thing)
        used = true
  of Mine:
    if thing.cooldown == 0:
      if thing.resources <= 0:
        inc env.stats[id].actionInvalid
        return
      let resourceKey = if thing.mineKind == MineStone: ItemStone else: ItemGold
      if env.giveItem(agent, resourceKey):
        thing.resources = thing.resources - 1
        env.updateObservations(MineResourceLayer, thing.pos, thing.resources)
        thing.cooldown = MapObjectMineCooldown
        env.updateObservations(MineReadyLayer, thing.pos, thing.cooldown)
        if resourceKey == ItemGold and getInv(agent, resourceKey) == 1:
          agent.reward += env.config.oreReward
        used = true
        if thing.resources <= 0:
          env.updateObservations(MineLayer, thing.pos, 0)
          env.updateObservations(MineResourceLayer, thing.pos, 0)
          env.updateObservations(MineReadyLayer, thing.pos, 0)
          removeThing(env, thing)
  of Magma:  # Magma smelting
    if thing.cooldown == 0 and getInv(agent, ItemGold) > 0 and agent.inventoryBar < MapObjectAgentMaxInventory:
      setInv(agent, ItemGold, getInv(agent, ItemGold) - 1)
      agent.inventoryBar = agent.inventoryBar + 1
      env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, ItemGold))
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.cooldown = 0
      env.updateObservations(MagmaReadyLayer, thing.pos, 1)
      if agent.inventoryBar == 1: agent.reward += env.config.barReward
      used = true
  of WeavingLoom:
    if thing.cooldown == 0 and agent.inventoryWheat > 0 and agent.inventoryLantern == 0:
      agent.inventoryWheat = agent.inventoryWheat - 1
      agent.inventoryLantern = 1
      thing.cooldown = 15
      env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
      env.updateObservations(AgentInventoryLanternLayer, agent.pos, agent.inventoryLantern)
      agent.reward += env.config.clothReward
      used = true
    elif thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationLoom, thing):
        used = true
  of Armory:
    if thing.teamId == getTeamId(agent.agentId) and thing.cooldown == 0 and agent.inventoryArmor < ArmorPoints:
      if env.spendStockpile(thing.teamId, @[(res: ResourceWood, count: 1)]):
        agent.inventoryArmor = ArmorPoints
        thing.cooldown = 20
        env.updateObservations(AgentInventoryArmorLayer, agent.pos, agent.inventoryArmor)
        agent.reward += env.config.armorReward
        used = true
  of ClayOven:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationOven, thing):
        used = true
      elif agent.inventoryWheat > 0:
        agent.inventoryWheat = agent.inventoryWheat - 1
        agent.inventoryBread = agent.inventoryBread + 1
        thing.cooldown = 10
        env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
        env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
        # No observation layer for bread; optional for UI later
        agent.reward += env.config.foodReward
        used = true
  of Cow:
    if agent.inventorySpear > 0 and getInv(agent, ItemMilk) == 0:
      if env.giveItem(agent, ItemMeat):
        agent.inventorySpear = max(0, agent.inventorySpear - 1)
        env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
        env.grid[thing.pos.x][thing.pos.y] = nil
        let idx = env.things.find(thing)
        if idx >= 0:
          env.things.del(idx)
        used = true
    elif thing.cooldown == 0:
      if env.giveItem(agent, ItemMilk):
        thing.cooldown = CowMilkCooldown
        used = true
  of Altar:
    if thing.cooldown == 0 and agent.inventoryBar >= 1:
      agent.inventoryBar = agent.inventoryBar - 1
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.hearts = thing.hearts + 1
      thing.cooldown = MapObjectAltarCooldown
      env.updateObservations(altarHeartsLayer, thing.pos, thing.hearts)
      env.updateObservations(altarReadyLayer, thing.pos, thing.cooldown)
      agent.reward += env.config.heartReward
      used = true
  of Barrel:
    if env.useStorageBuilding(agent, thing, @[]):
      used = true
  of Blacksmith:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationBlacksmith, thing):
        used = true
      elif env.tryBlacksmithService(agent, thing):
        used = true
  of TownCenter:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceFood, ResourceWood, ResourceGold, ResourceStone}):
        used = true
  of Mill:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceFood}):
        used = true
      if not used and env.useStorageBuilding(agent, thing, @[ItemWheat]):
        used = true
  of LumberCamp:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceWood}):
        used = true
      if not used and env.useStorageBuilding(agent, thing, @[ItemBranch]):
        used = true
  of MiningCamp:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceGold, ResourceStone}):
        used = true
      if not used and env.useStorageBuilding(agent, thing, @[ItemBoulder]):
        used = true
  of Farm:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useStorageBuilding(agent, thing, @[ItemWheat, ItemSeeds, ItemPlant]):
        used = true
  of Dock:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceFood}):
        used = true
  of Barracks:
    if thing.cooldown == 0:
      if env.tryTrainUnit(agent, thing, UnitManAtArms,
          @[(res: ResourceFood, count: 3), (res: ResourceGold, count: 1)], 8):
        used = true
  of ArcheryRange:
    if thing.cooldown == 0:
      if env.tryTrainUnit(agent, thing, UnitArcher,
          @[(res: ResourceWood, count: 2), (res: ResourceGold, count: 2)], 8):
        used = true
  of Stable:
    if thing.cooldown == 0:
      if env.tryTrainUnit(agent, thing, UnitScout, @[(res: ResourceFood, count: 3)], 8):
        used = true
  of SiegeWorkshop:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationSiegeWorkshop, thing):
        used = true
      elif env.tryTrainUnit(agent, thing, UnitSiege,
          @[(res: ResourceWood, count: 3), (res: ResourceStone, count: 2)], 10):
        used = true
  of Monastery:
    if thing.cooldown == 0:
      if env.tryTrainUnit(agent, thing, UnitMonk, @[(res: ResourceGold, count: 2)], 10):
        used = true
  of Castle:
    if thing.cooldown == 0:
      if env.tryTrainUnit(agent, thing, UnitKnight,
          @[(res: ResourceFood, count: 4), (res: ResourceGold, count: 2)], 12):
        used = true
  of University:
    discard
  of Market:
    if thing.cooldown == 0 and env.tryMarketTrade(agent, thing):
      used = true
  else:
    discard

  if not used:
    if tryPickupThing(env, agent, thing):
      used = true

  if used:
    inc env.stats[id].actionUse
  else:
    inc env.stats[id].actionInvalid
