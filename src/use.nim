proc useAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Use terrain or building with a single action (requires holding needed resource if any)
  # Use current facing; argument is ignored for direction.
  discard argument
  let useOrientation = agent.orientation
  let delta = getOrientationDelta(useOrientation)
  var targetPos = agent.pos
  targetPos.x += int32(delta.x)
  targetPos.y += int32(delta.y)

  if not isValidPos(targetPos):
    inc env.stats[id].actionInvalid
    return

  # Frozen tiles are non-interactable (terrain or things sitting on them)
  if isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  let thing = env.getThing(targetPos)
  template setInvAndObs(key: ItemKey, value: int) =
    setInv(agent, key, value)
    env.updateAgentInventoryObs(agent, key)

  template decInv(key: ItemKey) =
    setInvAndObs(key, getInv(agent, key) - 1)

  template incInv(key: ItemKey) =
    setInvAndObs(key, getInv(agent, key) + 1)

  if isNil(thing):
    # Terrain use only when no Thing occupies the tile.
    var used = false
    case env.terrain[targetPos.x][targetPos.y]:
    of Water:
      if env.giveItem(agent, ItemWater):
        agent.reward += env.config.waterReward
        used = true
    of Empty, Grass, Dune, Sand, Snow, Road:
      if env.hasDoor(targetPos):
        used = false
      elif agent.inventoryBread > 0:
        decInv(ItemBread)
        env.applyHealBurst(agent)
        used = true
      else:
        if agent.inventoryWater > 0:
          decInv(ItemWater)
          env.terrain[targetPos.x][targetPos.y] = Fertile
          env.resetTileColor(targetPos)
          env.updateObservations(TintLayer, targetPos, 0)
          used = true
    else:
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
  template takeFromThing(key: ItemKey, rewardAmount: float32 = 0.0) =
    let stored = getInv(thing, key)
    if stored <= 0:
      removeThing(env, thing)
      used = true
    elif env.giveItem(agent, key):
      let remaining = stored - 1
      if rewardAmount != 0:
        agent.reward += rewardAmount
      if remaining <= 0:
        removeThing(env, thing)
      else:
        setInv(thing, key, remaining)
      used = true
  case thing.kind:
  of Wheat:
    takeFromThing(ItemWheat, env.config.wheatReward)
  of Stone:
    takeFromThing(ItemStone)
  of Gold:
    takeFromThing(ItemGold)
  of Bush, Cactus:
    takeFromThing(ItemPlant)
  of Stalagmite:
    takeFromThing(ItemStone)
  of Stump:
    env.grantWood(agent)
    agent.reward += env.config.woodReward
    let remaining = getInv(thing, ItemWood) - 1
    if remaining <= 0:
      removeThing(env, thing)
    else:
      setInv(thing, ItemWood, remaining)
    used = true
  of Pine, Palm:
    env.harvestTree(agent, thing)
    used = true
  of Corpse:
    var lootKey = ItemNone
    var lootCount = 0
    for key, count in thing.inventory.pairs:
      if count > 0:
        lootKey = key
        lootCount = count
        break
    if lootKey != ItemNone:
      var didTake = false
      if lootKey == ItemMeat:
        setInv(agent, ItemMeat, getInv(agent, ItemMeat) + 1)
        env.updateAgentInventoryObs(agent, ItemMeat)
        didTake = true
      else:
        didTake = env.giveItem(agent, lootKey)
      if didTake:
        let remaining = lootCount - 1
        if remaining <= 0:
          thing.inventory.del(lootKey)
        else:
          setInv(thing, lootKey, remaining)
        var hasItems = false
        for _, count in thing.inventory.pairs:
          if count > 0:
            hasItems = true
            break
        if not hasItems:
          removeThing(env, thing)
          if lootKey != ItemMeat:
            let skeleton = Thing(kind: Skeleton, pos: thing.pos)
            skeleton.inventory = emptyInventory()
            env.add(skeleton)
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
        decInv(ItemWood)
      else:
        decInv(ItemWheat)
      setInvAndObs(ItemLantern, 1)
      thing.cooldown = 15
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
        decInv(ItemWheat)
        incInv(ItemBread)
        thing.cooldown = 10
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
          decInv(ItemBar)
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
            decInv(ItemWheat)
            incInv(ItemBread)
            thing.cooldown = 10
            agent.reward += env.config.foodReward
            used = true
      of UseWeavingLoom:
        if thing.cooldown == 0 and agent.inventoryLantern == 0 and
            (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
          if agent.inventoryWood > 0:
            decInv(ItemWood)
          else:
            decInv(ItemWheat)
          setInvAndObs(ItemLantern, 1)
          thing.cooldown = 15
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
