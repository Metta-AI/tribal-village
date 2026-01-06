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

proc dropStump(env: Environment, pos: IVec2, woodRemaining: int) =
  let stump = Thing(kind: Stump, pos: pos)
  stump.inventory = emptyInventory()
  if woodRemaining > 0:
    setInv(stump, ItemWood, woodRemaining)
  env.add(stump)

proc updateThingObsOnRemove(env: Environment, kind: ThingKind, pos: IVec2) =
  case kind
  of Wall:
    env.updateObservations(WallLayer, pos, 0)
  of Magma:
    env.updateObservations(MagmaLayer, pos, 0)
  of Altar:
    env.updateObservations(altarLayer, pos, 0)
    env.updateObservations(altarHeartsLayer, pos, 0)
  else:
    discard

proc updateThingObsOnAdd(env: Environment, kind: ThingKind, pos: IVec2, placed: Thing) =
  case kind
  of Wall:
    env.updateObservations(WallLayer, pos, 1)
  of Magma:
    env.updateObservations(MagmaLayer, pos, 1)
  of Altar:
    env.updateObservations(altarLayer, pos, 1)
    env.updateObservations(altarHeartsLayer, pos, placed.hearts)
  else:
    discard

proc tryPickupThing(env: Environment, agent: Thing, thing: Thing): bool =
  if isBuildingKind(thing.kind):
    return false
  if thing.kind in {Agent, Tumor, Pine, Palm, Cow, Corpse, Skeleton, Spawner, Stump, Wall, Magma, Lantern}:
    return false

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
  env.updateThingObsOnRemove(thing.kind, thing.pos)
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

proc placeThingFromKey(env: Environment, agent: Thing, key: ItemKey, pos: IVec2): bool =
  if key == ItemThingPrefix & "Road":
    if env.terrain[pos.x][pos.y] notin {Empty, Grass, Sand, Snow, Dune, Stalagmite, Road}:
      return false
    env.terrain[pos.x][pos.y] = Road
    env.resetTileColor(pos)
    return true
  var kind: ThingKind
  if not parseThingKey(key, kind):
    return false
  if kind == Wall and env.terrain[pos.x][pos.y] == Wheat:
    return false
  let placed = Thing(
    kind: kind,
    pos: pos
  )
  if isBuildingKind(kind) and buildingTeamOwned(kind):
    placed.teamId = getTeamId(agent.agentId)
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
          if terrain in {Empty, Grass, Sand, Snow, Dune, Stalagmite, Road}:
            env.terrain[fertilePos.x][fertilePos.y] = Fertile
            env.resetTileColor(fertilePos)
  env.updateThingObsOnAdd(kind, pos, placed)
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
