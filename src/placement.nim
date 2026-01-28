proc parseThingKey(key: ItemKey, kind: var ThingKind): bool =
  if not isThingKey(key):
    return false
  for candidate in ThingKind:
    if $candidate == key.name:
      kind = candidate
      return true
  false

proc removeThing(env: Environment, thing: Thing) =
  # Remove from spatial index before clearing position
  removeFromSpatialIndex(env, thing)
  if isValidPos(thing.pos):
    if thingBlocksMovement(thing.kind):
      env.grid[thing.pos.x][thing.pos.y] = nil
    else:
      env.backgroundGrid[thing.pos.x][thing.pos.y] = nil
    env.updateObservations(ThingAgentLayer, thing.pos, 0)
  let thingIdx = thing.thingsIndex
  if thingIdx >= 0 and thingIdx < env.things.len and env.things[thingIdx] == thing:
    let lastIdx = env.things.len - 1
    if thingIdx != lastIdx:
      let last = env.things[lastIdx]
      env.things[thingIdx] = last
      last.thingsIndex = thingIdx
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

proc add*(env: Environment, thing: Thing) =
  let isBlocking = thingBlocksMovement(thing.kind)
  if isValidPos(thing.pos) and not isBlocking:
    let existing = env.backgroundGrid[thing.pos.x][thing.pos.y]
    if not isNil(existing):
      if existing.kind in CliffKinds:
        # Cliffs always own their tile; don't place other background things on top.
        return
      if thing.kind in CliffKinds:
        # Cliffs take precedence over other background overlays.
        removeThing(env, existing)
  let defaultMaxHp =
    case thing.kind
    of Wall: WallMaxHp
    of Door: DoorMaxHearts
    of Outpost: OutpostMaxHp
    of GuardTower: GuardTowerMaxHp
    of TownCenter: TownCenterMaxHp
    of Castle: CastleMaxHp
    of Monastery: MonasteryMaxHp
    of Wonder: WonderMaxHp
    else: 0
  if defaultMaxHp > 0:
    if thing.maxHp <= 0:
      thing.maxHp = defaultMaxHp
    if thing.hp <= 0:
      thing.hp = thing.maxHp

  if thing.attackDamage <= 0:
    case thing.kind
    of GuardTower: thing.attackDamage = GuardTowerAttackDamage
    of Castle: thing.attackDamage = CastleAttackDamage
    of TownCenter: thing.attackDamage = TownCenterAttackDamage
    else: discard

  # Initialize rally point to "none" for buildings
  if isBuildingKind(thing.kind):
    thing.rallyPoint = ivec2(-1, -1)

  case thing.kind
  of Stone:
    if getInv(thing, ItemStone) <= 0:
      setInv(thing, ItemStone, MineDepositAmount)
  of Gold:
    if getInv(thing, ItemGold) <= 0:
      setInv(thing, ItemGold, MineDepositAmount)
  else:
    discard
  env.things.add(thing)
  thing.thingsIndex = env.things.len - 1
  env.thingsByKind[thing.kind].add(thing)
  thing.kindListIndex = env.thingsByKind[thing.kind].len - 1
  if thing.kind == Agent:
    thing.rallyTarget = ivec2(-1, -1)
    if thing.teamIdOverride == 0:
      thing.teamIdOverride = -1
    if thing.embarkedUnitClass == UnitVillager and thing.unitClass != UnitVillager:
      thing.embarkedUnitClass = thing.unitClass
    env.agents.add(thing)
    env.stats.add(Stats())
  if isValidPos(thing.pos):
    if isBlocking:
      env.grid[thing.pos.x][thing.pos.y] = thing
    else:
      env.backgroundGrid[thing.pos.x][thing.pos.y] = thing
    env.updateObservations(ThingAgentLayer, thing.pos, 0)
    # Add to spatial index
    addToSpatialIndex(env, thing)
