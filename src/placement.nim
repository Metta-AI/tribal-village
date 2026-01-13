proc parseThingKey(key: ItemKey, kind: var ThingKind): bool =
  if not key.startsWith(ItemThingPrefix):
    return false
  let name = key[ItemThingPrefix.len .. ^1]
  for candidate in ThingKind:
    if $candidate == name:
      kind = candidate
      return true
  false

proc updateThingObs(env: Environment, kind: ThingKind, pos: IVec2, present: bool, hearts = 0) =
  case kind
  of Wall:
    env.updateObservations(WallLayer, pos, if present: 1 else: 0)
  of Magma:
    env.updateObservations(MagmaLayer, pos, if present: 1 else: 0)
  of Altar:
    env.updateObservations(altarLayer, pos, if present: 1 else: 0)
    env.updateObservations(altarHeartsLayer, pos, if present: hearts else: 0)
  else:
    discard

proc removeThing(env: Environment, thing: Thing) =
  if isValidPos(thing.pos):
    if thingBlocksMovement(thing.kind):
      env.grid[thing.pos.x][thing.pos.y] = nil
    else:
      env.overlayGrid[thing.pos.x][thing.pos.y] = nil
  let idx = thing.thingsIndex
  if idx >= 0 and idx < env.things.len and env.things[idx] == thing:
    let lastIdx = env.things.len - 1
    if idx != lastIdx:
      let last = env.things[lastIdx]
      env.things[idx] = last
      last.thingsIndex = idx
    env.things.setLen(lastIdx)
  let kindIdx = thing.kindListIndex
  if kindIdx >= 0 and kindIdx < env.thingsByKind[thing.kind].len and
      env.thingsByKind[thing.kind][kindIdx] == thing:
    let lastKindIdx = env.thingsByKind[thing.kind].len - 1
    if kindIdx != lastKindIdx:
      let lastKindThing = env.thingsByKind[thing.kind][lastKindIdx]
      env.thingsByKind[thing.kind][kindIdx] = lastKindThing
      lastKindThing.kindListIndex = kindIdx
    env.thingsByKind[thing.kind].setLen(lastKindIdx)
  if thing.kind == Altar and env.altarColors.hasKey(thing.pos):
    env.altarColors.del(thing.pos)

proc tryPickupThing(env: Environment, agent: Thing, thing: Thing): bool =
  if isBuildingKind(thing.kind):
    return false
  if thing.kind in {Agent, Tumor, Tree, Wheat, Stubble, Stone, Gold, Bush, Cactus, Stalagmite,
                    Cow, Corpse, Skeleton, Spawner, Stump, Wall, Magma, Lantern}:
    return false

  let key = ItemThingPrefix & $thing.kind
  let current = getInv(agent, key)
  if current >= MapObjectAgentMaxInventory:
    return false
  var resourceNeeded = 0
  for itemKey, count in thing.inventory.pairs:
    if isStockpileResourceKey(itemKey):
      resourceNeeded += count
    else:
      let capacity = MapObjectAgentMaxInventory - getInv(agent, itemKey)
      if capacity < count:
        return false
  if resourceNeeded > (block:
    var total = 0
    for invKey, invCount in agent.inventory.pairs:
      if invCount > 0 and isStockpileResourceKey(invKey):
        total += invCount
    max(0, ResourceCarryCapacity - total)
  ):
    return false
  for itemKey, count in thing.inventory.pairs:
    setInv(agent, itemKey, getInv(agent, itemKey) + count)
    env.updateAgentInventoryObs(agent, itemKey)
  setInv(agent, key, current + 1)
  env.updateAgentInventoryObs(agent, key)
  updateThingObs(env, thing.kind, thing.pos, false)
  removeThing(env, thing)
  true

proc add*(env: Environment, thing: Thing) =
  if thing.kind == Stone:
    if getInv(thing, ItemStone) <= 0:
      setInv(thing, ItemStone, ResourceNodeInitial)
  elif thing.kind == Gold:
    if getInv(thing, ItemGold) <= 0:
      setInv(thing, ItemGold, ResourceNodeInitial)
  env.things.add(thing)
  thing.thingsIndex = env.things.len - 1
  env.thingsByKind[thing.kind].add(thing)
  thing.kindListIndex = env.thingsByKind[thing.kind].len - 1
  if thing.kind == Agent:
    env.agents.add(thing)
    env.stats.add(Stats())
  if isValidPos(thing.pos):
    if thingBlocksMovement(thing.kind):
      env.grid[thing.pos.x][thing.pos.y] = thing
    else:
      env.overlayGrid[thing.pos.x][thing.pos.y] = thing

proc placeThingFromKey(env: Environment, agent: Thing, key: ItemKey, pos: IVec2): bool =
  if key == ItemThingPrefix & "Road":
    if env.terrain[pos.x][pos.y] notin BuildableTerrain:
      return false
    env.terrain[pos.x][pos.y] = Road
    env.resetTileColor(pos)
    return true
  var kind: ThingKind
  if not parseThingKey(key, kind):
    return false
  let placed = Thing(
    kind: kind,
    pos: pos
  )
  if isBuildingKind(kind) and kind != Barrel:
    placed.teamId = getTeamId(agent.agentId)
  if kind == Door:
    placed.hp = DoorMaxHearts
    placed.maxHp = DoorMaxHearts
  case kind
  of Lantern:
    placed.teamId = getTeamId(agent.agentId)
    placed.lanternHealthy = true
  of Altar:
    placed.inventory = emptyInventory()
    placed.hearts = 0
  of Spawner:
    placed.homeSpawner = pos
  else:
    discard
  if isBuildingKind(kind):
    let capacity = buildingBarrelCapacity(kind)
    if capacity > 0:
      placed.barrelCapacity = capacity
  env.add(placed)
  if isBuildingKind(kind):
    let radius = buildingFertileRadius(kind)
    if radius > 0:
      for dx in -radius .. radius:
        for dy in -radius .. radius:
          if dx == 0 and dy == 0:
            continue
          if max(abs(dx), abs(dy)) > radius:
            continue
          let fertilePos = placed.pos + ivec2(dx.int32, dy.int32)
          if not isValidPos(fertilePos):
            continue
          if not env.isEmpty(fertilePos) or env.hasDoor(fertilePos) or
             isBlockedTerrain(env.terrain[fertilePos.x][fertilePos.y]) or isTileFrozen(fertilePos, env):
            continue
          let terrain = env.terrain[fertilePos.x][fertilePos.y]
          if isBuildableTerrain(terrain):
            env.terrain[fertilePos.x][fertilePos.y] = Fertile
            env.resetTileColor(fertilePos)
  updateThingObs(env, kind, pos, true, placed.hearts)
  if kind == Altar:
    let teamId = placed.teamId
    if teamId >= 0 and teamId < env.teamColors.len:
      env.altarColors[pos] = env.teamColors[teamId]
  true
