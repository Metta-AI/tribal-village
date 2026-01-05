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
  proc tryHarvestTerrainResource(key: ItemKey, reward: float32, clearOnDeplete: bool): bool =
    let remaining = env.terrainResources[targetPos.x][targetPos.y]
    if remaining <= 0:
      return false
    if not env.giveItem(agent, key):
      return false
    env.terrainResources[targetPos.x][targetPos.y] = remaining - 1
    if reward != 0:
      agent.reward += reward
    if env.terrainResources[targetPos.x][targetPos.y] <= 0 and clearOnDeplete:
      env.terrain[targetPos.x][targetPos.y] = Empty
      env.terrainResources[targetPos.x][targetPos.y] = 0
      env.resetTileColor(targetPos)
    true
  if isNil(thing):
    # Terrain use only when no Thing occupies the tile.
    var used = false
    case env.terrain[targetPos.x][targetPos.y]:
    of Water:
      if env.giveItem(agent, ItemWater):
        agent.reward += env.config.waterReward
        used = true
    of Wheat:
      used = tryHarvestTerrainResource(ItemWheat, env.config.wheatReward, true)
    of Tree, Palm:
      used = tryHarvestTerrainResource(ItemWood, env.config.woodReward, true)
    of Rock:
      used = tryHarvestTerrainResource(ItemStone, 0.0, true)
    of Stalagmite:
      used = tryHarvestTerrainResource(ItemStone, 0.0, true)
    of Gold:
      used = tryHarvestTerrainResource(ItemGold, 0.0, true)
    of Bush, Cactus:
      used = tryHarvestTerrainResource(ItemPlant, 0.0, true)
    of Animal:
      used = tryHarvestTerrainResource(ItemFish, 0.0, true)
    of Empty, Grass, Dune, Sand, Snow, Road:
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
    of Bridge, Fertile:
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
    let stored = getInv(thing, ItemWood)
    if stored > 0 and env.giveItem(agent, ItemWood):
      let remaining = stored - 1
      agent.reward += env.config.woodReward
      if remaining <= 0:
        removeThing(env, thing)
      elif remaining < ResourceNodeInitial:
        removeThing(env, thing)
        env.dropStump(thing.pos, remaining)
      else:
        setInv(thing, ItemWood, remaining)
      used = true
  of Stump:
    let stored = getInv(thing, ItemWood)
    if stored > 0 and env.giveItem(agent, ItemWood):
      let remaining = stored - 1
      agent.reward += env.config.woodReward
      if remaining <= 0:
        removeThing(env, thing)
      else:
        setInv(thing, ItemWood, remaining)
      used = true
  of Magma:  # Magma smelting
    if thing.cooldown == 0 and getInv(agent, ItemGold) > 0 and agent.inventoryBar < MapObjectAgentMaxInventory:
      setInv(agent, ItemGold, getInv(agent, ItemGold) - 1)
      agent.inventoryBar = agent.inventoryBar + 1
      env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, ItemGold))
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.cooldown = 0
      if agent.inventoryBar == 1: agent.reward += env.config.barReward
      used = true
  of WeavingLoom:
    if thing.cooldown == 0 and agent.inventoryLantern == 0 and
        (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
      if agent.inventoryWood > 0:
        agent.inventoryWood = agent.inventoryWood - 1
        env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      else:
        agent.inventoryWheat = agent.inventoryWheat - 1
        env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
      agent.inventoryLantern = 1
      thing.cooldown = 15
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
    if agent.inventorySpear > 0:
      let stored = getInv(thing, ItemFish)
      if stored > 0:
        agent.inventorySpear = max(0, agent.inventorySpear - 1)
        env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
        removeThing(env, thing)
        let skeleton = Thing(kind: Skeleton, pos: thing.pos)
        skeleton.inventory = emptyInventory()
        setInv(skeleton, ItemFish, stored)
        env.add(skeleton)
        used = true
  of Skeleton:
    let stored = getInv(thing, ItemFish)
    if stored > 0 and env.giveItem(agent, ItemFish):
      let remaining = stored - 1
      if remaining <= 0:
        removeThing(env, thing)
      else:
        setInv(thing, ItemFish, remaining)
      used = true
  of Altar:
    if thing.cooldown == 0 and agent.inventoryBar >= 1:
      agent.inventoryBar = agent.inventoryBar - 1
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.hearts = thing.hearts + 1
      thing.cooldown = MapObjectAltarCooldown
      env.updateObservations(altarHeartsLayer, thing.pos, thing.hearts)
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
    if not used and thing.teamId == getTeamId(agent.agentId):
      if env.useStorageBuilding(agent, thing, @[ItemArmor, ItemSpear]):
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
  of MiningCamp:
    if thing.teamId == getTeamId(agent.agentId):
      if env.useDropoffBuilding(agent, {ResourceGold, ResourceStone}):
        used = true
      if not used and env.useStorageBuilding(agent, thing, @[ItemRock]):
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
