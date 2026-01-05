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
    of Pine, Palm:
      let remaining = env.terrainResources[targetPos.x][targetPos.y]
      if remaining > 0 and env.giveItem(agent, ItemWood):
        let newRemaining = remaining - 1
        agent.reward += env.config.woodReward
        if newRemaining <= 0:
          env.terrain[targetPos.x][targetPos.y] = Empty
          env.terrainResources[targetPos.x][targetPos.y] = 0
          env.resetTileColor(targetPos)
        else:
          # Convert immediately to a stump after the first harvest.
          env.terrain[targetPos.x][targetPos.y] = Empty
          env.terrainResources[targetPos.x][targetPos.y] = 0
          env.resetTileColor(targetPos)
          env.dropStump(targetPos, newRemaining)
        used = true
    of Stone:
      used = tryHarvestTerrainResource(ItemStone, 0.0, true)
    of Stalagmite:
      used = tryHarvestTerrainResource(ItemStone, 0.0, true)
    of Gold:
      used = tryHarvestTerrainResource(ItemGold, 0.0, true)
    of Bush, Cactus:
      used = tryHarvestTerrainResource(ItemPlant, 0.0, true)
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
  of Skeleton:
    let stored = getInv(thing, ItemFish)
    if stored > 0 and env.giveItem(agent, ItemFish):
      let remaining = stored - 1
      if remaining <= 0:
        removeThing(env, thing)
      else:
        setInv(thing, ItemFish, remaining)
      used = true
  else:
    if isBuildingKind(thing.kind):
      let useKind = buildingUseKind(thing.kind)
      case useKind
      of UseAltar:
        if thing.cooldown == 0 and agent.inventoryBar >= 1:
          agent.inventoryBar = agent.inventoryBar - 1
          env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
          thing.hearts = thing.hearts + 1
          thing.cooldown = MapObjectAltarCooldown
          env.updateObservations(altarHeartsLayer, thing.pos, thing.hearts)
          agent.reward += env.config.heartReward
          used = true
      of UseArmory:
        discard
      of UseClayOven:
        if thing.cooldown == 0:
          if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
            used = true
          elif agent.inventoryWheat > 0:
            agent.inventoryWheat = agent.inventoryWheat - 1
            agent.inventoryBread = agent.inventoryBread + 1
            thing.cooldown = 10
            env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
            env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
            agent.reward += env.config.foodReward
            used = true
      of UseWeavingLoom:
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
        elif thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
          if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
            used = true
      of UseBlacksmith:
        if thing.cooldown == 0:
          if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
            used = true
        if not used and thing.teamId == getTeamId(agent.agentId):
          if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
            used = true
      of UseMarket:
        if thing.cooldown == 0 and env.tryMarketTrade(agent, thing):
          used = true
      of UseDropoff:
        if thing.teamId == getTeamId(agent.agentId):
          if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
            used = true
      of UseDropoffAndStorage:
        if thing.teamId == getTeamId(agent.agentId):
          if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
            used = true
          if not used and env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
            used = true
      of UseStorage:
        if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
          used = true
      of UseTrain:
        if thing.cooldown == 0 and buildingHasTrain(thing.kind):
          if env.tryTrainUnit(agent, thing, buildingTrainUnit(thing.kind),
              buildingTrainCosts(thing.kind), buildingTrainCooldown(thing.kind)):
            used = true
      of UseTrainAndCraft:
        if thing.cooldown == 0:
          if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
            used = true
          elif buildingHasTrain(thing.kind):
            if env.tryTrainUnit(agent, thing, buildingTrainUnit(thing.kind),
                buildingTrainCosts(thing.kind), buildingTrainCooldown(thing.kind)):
              used = true
      of UseCraft:
        if thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
          if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
            used = true
      of UseNone:
        discard

  if not used:
    if tryPickupThing(env, agent, thing):
      used = true

  if used:
    inc env.stats[id].actionUse
  else:
    inc env.stats[id].actionInvalid
