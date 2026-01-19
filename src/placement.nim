proc parseThingKey(key: ItemKey, kind: var ThingKind): bool =
  if not isThingKey(key):
    return false
  let name = key.name
  for candidate in ThingKind:
    if $candidate == name:
      kind = candidate
      return true
  false

proc removeThing(env: Environment, thing: Thing) =
  if isValidPos(thing.pos):
    let isBlocking = thingBlocksMovement(thing.kind)
    if isBlocking:
      env.grid[thing.pos.x][thing.pos.y] = nil
    else:
      env.backgroundGrid[thing.pos.x][thing.pos.y] = nil
    env.updateObservations(ThingAgentLayer, thing.pos, 0)
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
  if thing.kind in {Wall, Door, Outpost, GuardTower, TownCenter, Castle}:
    if thing.maxHp <= 0:
      case thing.kind
      of Wall:
        thing.maxHp = WallMaxHp
      of Door:
        thing.maxHp = DoorMaxHearts
      of Outpost:
        thing.maxHp = OutpostMaxHp
      of GuardTower:
        thing.maxHp = GuardTowerMaxHp
      of TownCenter:
        thing.maxHp = TownCenterMaxHp
      of Castle:
        thing.maxHp = CastleMaxHp
      else:
        discard
    if thing.hp <= 0:
      thing.hp = thing.maxHp
    if thing.attackDamage <= 0:
      case thing.kind
      of GuardTower:
        thing.attackDamage = GuardTowerAttackDamage
      of Castle:
        thing.attackDamage = CastleAttackDamage
      else:
        discard
  if thing.kind == Stone:
    if getInv(thing, ItemStone) <= 0:
      setInv(thing, ItemStone, MineDepositAmount)
  elif thing.kind == Gold:
    if getInv(thing, ItemGold) <= 0:
      setInv(thing, ItemGold, MineDepositAmount)
  env.things.add(thing)
  thing.thingsIndex = env.things.len - 1
  env.thingsByKind[thing.kind].add(thing)
  thing.kindListIndex = env.thingsByKind[thing.kind].len - 1
  if thing.kind == Agent:
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
