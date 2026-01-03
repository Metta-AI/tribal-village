proc dropStump(env: Environment, pos: IVec2, woodCount: int) =
  let stump = Thing(kind: Stump, pos: pos)
  stump.inventory = emptyInventory()
  if woodCount > 0:
    setInv(stump, ItemWood, woodCount)
  env.add(stump)

proc thingKey(kind: ThingKind): ItemKey =
  ItemThingPrefix & $kind

proc parseThingKey(key: ItemKey, kind: var ThingKind): bool =
  if not key.startsWith(ItemThingPrefix):
    return false
  let name = key[ItemThingPrefix.len .. ^1]
  for candidate in ThingKind:
    if $candidate == name:
      kind = candidate
      return true
  false

proc tryPickupThing(env: Environment, agent: Thing, thing: Thing): bool =
  if thing.kind in {Agent, Tumor, TreeObject, Cow, Altar, TownCenter, House, Barracks,
                    ArcheryRange, Stable, SiegeWorkshop, Blacksmith, Market, Dock, Monastery,
                    University, Castle, Stump}:
    return false
  if thing.kind == Skeleton:
    var resourceNeeded = 0
    for itemKey, count in thing.inventory.pairs:
      if isStockpileResourceKey(itemKey):
        resourceNeeded += count
      else:
        let capacity = MapObjectAgentMaxInventory - getInv(agent, itemKey)
        if capacity < count:
          return false
    if resourceNeeded > resourceCarryCapacityLeft(agent):
      return false
    for itemKey, count in thing.inventory.pairs:
      setInv(agent, itemKey, getInv(agent, itemKey) + count)
      env.updateAgentInventoryObs(agent, itemKey)
    removeThing(env, thing)
    return true

  let key = thingKey(thing.kind)
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
  if resourceNeeded > resourceCarryCapacityLeft(agent):
    return false
  for itemKey, count in thing.inventory.pairs:
    setInv(agent, itemKey, getInv(agent, itemKey) + count)
    env.updateAgentInventoryObs(agent, itemKey)
  setInv(agent, key, current + 1)
  env.updateAgentInventoryObs(agent, key)
  case thing.kind
  of Wall:
    env.updateObservations(WallLayer, thing.pos, 0)
  of Mine:
    env.updateObservations(MineLayer, thing.pos, 0)
    env.updateObservations(MineResourceLayer, thing.pos, 0)
    env.updateObservations(MineReadyLayer, thing.pos, 0)
  of Converter:
    env.updateObservations(ConverterLayer, thing.pos, 0)
    env.updateObservations(ConverterReadyLayer, thing.pos, 0)
  of Altar:
    env.updateObservations(altarLayer, thing.pos, 0)
    env.updateObservations(altarHeartsLayer, thing.pos, 0)
    env.updateObservations(altarReadyLayer, thing.pos, 0)
  else:
    discard
  removeThing(env, thing)
  true

proc removeThing(env: Environment, thing: Thing) =
  if isValidPos(thing.pos):
    env.grid[thing.pos.x][thing.pos.y] = nil
  let idx = env.things.find(thing)
  if idx >= 0:
    env.things.del(idx)
  if thing.kind == Altar and altarColors.hasKey(thing.pos):
    altarColors.del(thing.pos)

proc firstThingItem(agent: Thing): ItemKey =
  var keys: seq[ItemKey] = @[]
  for key, count in agent.inventory.pairs:
    if count > 0 and key.startsWith(ItemThingPrefix):
      keys.add(key)
  if keys.len == 0:
    return ItemNone
  keys.sort()
  keys[0]

proc placeThingFromKey(env: Environment, agent: Thing, key: ItemKey, pos: IVec2): bool =
  if key == ItemThingPrefix & "Road":
    if env.terrain[pos.x][pos.y] != Empty:
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
  case kind
  of Barrel:
    placed.barrelCapacity = BarrelCapacity
  of Mill, LumberCamp, MiningCamp:
    placed.barrelCapacity = BarrelCapacity
    placed.teamId = getTeamId(agent.agentId)
  of Farm:
    placed.barrelCapacity = BarrelCapacity
    placed.teamId = getTeamId(agent.agentId)
  of PlantedLantern:
    placed.teamId = getTeamId(agent.agentId)
    placed.lanternHealthy = true
  of Armory, Forge, TownCenter, House, Barracks, ArcheryRange, Stable, SiegeWorkshop, Blacksmith,
     Market, Dock, Monastery, University, Castle, Outpost:
    placed.teamId = getTeamId(agent.agentId)
  of Altar:
    placed.teamId = getTeamId(agent.agentId)
    placed.inventory = emptyInventory()
    placed.hearts = 0
  of Spawner:
    placed.homeSpawner = pos
  of Mine:
    placed.inventory = emptyInventory()
    placed.mineKind = MineGold
    placed.resources = MapObjectMineInitialResources
  else:
    discard
  env.add(placed)
  if kind == Farm or kind == Mill:
    let offsets = [
      ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
      ivec2(-1, 0), ivec2(1, 0),
      ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1)
    ]
    for offset in offsets:
      let farmPos = placed.pos + offset
      if not isValidPos(farmPos):
        continue
      if not env.isEmpty(farmPos) or env.hasDoor(farmPos) or isBlockedTerrain(env.terrain[farmPos.x][farmPos.y]) or isTileFrozen(farmPos, env):
        continue
      if env.terrain[farmPos.x][farmPos.y] == Empty:
        env.terrain[farmPos.x][farmPos.y] = Wheat
        env.resetTileColor(farmPos)
  case kind
  of Wall:
    env.updateObservations(WallLayer, pos, 1)
  of Mine:
    env.updateObservations(MineLayer, pos, 1)
    env.updateObservations(MineResourceLayer, pos, placed.resources)
    env.updateObservations(MineReadyLayer, pos, placed.cooldown)
  of Converter:
    env.updateObservations(ConverterLayer, pos, 1)
    env.updateObservations(ConverterReadyLayer, pos, placed.cooldown)
  of Altar:
    env.updateObservations(altarLayer, pos, 1)
    env.updateObservations(altarHeartsLayer, pos, placed.hearts)
    env.updateObservations(altarReadyLayer, pos, placed.cooldown)
  else:
    discard
  if kind == Altar:
    let teamId = placed.teamId
    if teamId >= 0 and teamId < teamColors.len:
      altarColors[pos] = teamColors[teamId]
  true


proc add(env: Environment, thing: Thing) =
  if thing.inventory.len == 0:
    thing.inventory = emptyInventory()
  env.things.add(thing)
  if thing.kind == Agent:
    env.agents.add(thing)
    env.stats.add(Stats())
  if isValidPos(thing.pos):
    env.grid[thing.pos.x][thing.pos.y] = thing
