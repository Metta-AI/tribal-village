# This file is included by src/environment.nim
proc noopAction(env: Environment, id: int, agent: Thing) =
  inc env.stats[id].actionNoop

proc add(env: Environment, thing: Thing)
proc removeThing(env: Environment, thing: Thing)

proc canCarry(agent: Thing, key: ItemKey, count: int = 1): bool =
  getInv(agent, key) + count <= MapObjectAgentMaxInventory

proc giveItem(env: Environment, agent: Thing, key: ItemKey, count: int = 1): bool =
  if count <= 0 or not agent.canCarry(key, count):
    return false
  setInv(agent, key, getInv(agent, key) + count)
  env.updateAgentInventoryObs(agent, key)
  true

proc giveFirstAvailable(env: Environment, agent: Thing, keys: openArray[ItemKey]): bool =
  for key in keys:
    if agent.canCarry(key, 1):
      return env.giveItem(agent, key, 1)
  false

proc storageKeyAllowed(key: ItemKey, allowed: openArray[ItemKey]): bool =
  if allowed.len == 0:
    return true
  for allowedKey in allowed:
    if key == allowedKey:
      return true
  false

proc selectAllowedItem(agent: Thing, allowed: openArray[ItemKey]): tuple[key: ItemKey, count: int] =
  result = (key: ItemNone, count: 0)
  if allowed.len == 0:
    return agentMostHeldItem(agent)
  for key in allowed:
    let count = getInv(agent, key)
    if count > result.count:
      result = (key: key, count: count)

proc useStorageBuilding(env: Environment, agent: Thing, storage: Thing, allowed: openArray[ItemKey]): bool =
  if storage.inventory.len > 0:
    var storedKey = ItemNone
    var storedCount = 0
    for key, count in storage.inventory.pairs:
      if count > 0:
        storedKey = key
        storedCount = count
        break
    if storedKey.len == 0 or not storageKeyAllowed(storedKey, allowed):
      return false
    let agentCount = getInv(agent, storedKey)
    let storageSpace = max(0, storage.barrelCapacity - storedCount)
    if agentCount > 0 and storageSpace > 0:
      let moved = min(agentCount, storageSpace)
      setInv(agent, storedKey, agentCount - moved)
      setInv(storage, storedKey, storedCount + moved)
      env.updateAgentInventoryObs(agent, storedKey)
      return true
    let capacityLeft = max(0, MapObjectAgentMaxInventory - agentCount)
    if capacityLeft > 0:
      let moved = min(storedCount, capacityLeft)
      if moved > 0:
        setInv(agent, storedKey, agentCount + moved)
        let remaining = storedCount - moved
        setInv(storage, storedKey, remaining)
        env.updateAgentInventoryObs(agent, storedKey)
        return true
    return false

  let choice = selectAllowedItem(agent, allowed)
  if choice.count > 0 and choice.key != ItemNone:
    let moved = min(choice.count, storage.barrelCapacity)
    setInv(agent, choice.key, choice.count - moved)
    setInv(storage, choice.key, moved)
    env.updateAgentInventoryObs(agent, choice.key)
    return true
  false

proc stationForThing(kind: ThingKind): CraftStation =
  case kind
  of Forge: StationForge
  of Armory: StationArmory
  of WeavingLoom: StationLoom
  of ClayOven: StationOven
  of Table: StationTable
  of Chair: StationChair
  of Bed: StationBed
  of Statue: StationStatue
  else: StationTable

proc canApplyRecipe(agent: Thing, recipe: CraftRecipe): bool =
  for input in recipe.inputs:
    if getInv(agent, input.key) < input.count:
      return false
  for output in recipe.outputs:
    if getInv(agent, output.key) + output.count > MapObjectAgentMaxInventory:
      return false
  true

proc applyRecipe(env: Environment, agent: Thing, recipe: CraftRecipe) =
  for input in recipe.inputs:
    setInv(agent, input.key, getInv(agent, input.key) - input.count)
    env.updateAgentInventoryObs(agent, input.key)
  for output in recipe.outputs:
    setInv(agent, output.key, getInv(agent, output.key) + output.count)
    env.updateAgentInventoryObs(agent, output.key)

proc tryCraftAtStation(env: Environment, agent: Thing, station: CraftStation, stationThing: Thing): bool =
  for recipe in CraftRecipes:
    if recipe.station != station:
      continue
    if not canApplyRecipe(agent, recipe):
      continue
    env.applyRecipe(agent, recipe)
    if stationThing != nil:
      stationThing.cooldown = max(1, recipe.cooldown)
    return true
  false


proc moveAction(env: Environment, id: int, agent: Thing, argument: int) =
  if argument < 0 or argument > 7:
    inc env.stats[id].actionInvalid
    return

  let moveOrientation = Orientation(argument)
  let delta = getOrientationDelta(moveOrientation)

  var step1 = agent.pos
  step1.x += int32(delta.x)
  step1.y += int32(delta.y)

  # Prevent moving onto blocked terrain (bridges remain walkable).
  if isBlockedTerrain(env.terrain[step1.x][step1.y]):
    inc env.stats[id].actionInvalid
    return

  if not env.canAgentPassDoor(agent, step1):
    inc env.stats[id].actionInvalid
    return

  let newOrientation = moveOrientation
  # Allow walking through planted lanterns by relocating the lantern, preferring push direction (up to 2 tiles ahead)
  proc canEnter(pos: IVec2): bool =
    var canMove = env.isEmpty(pos)
    if canMove:
      return true
    let blocker = env.getThing(pos)
    if isNil(blocker) or blocker.kind != PlantedLantern:
      return false

    var relocated = false
    # Helper to ensure lantern spacing (Chebyshev >= 3 from other lanterns)
    template spacingOk(nextPos: IVec2): bool =
      var ok = true
      for t in env.things:
        if t.kind == PlantedLantern and t != blocker:
          let dist = max(abs(t.pos.x - nextPos.x), abs(t.pos.y - nextPos.y))
          if dist < 3'i32:
            ok = false
            break
      ok
    # Preferred push positions in move direction
    let ahead1 = ivec2(pos.x + delta.x, pos.y + delta.y)
    let ahead2 = ivec2(pos.x + delta.x * 2, pos.y + delta.y * 2)
    if ahead2.x >= 0 and ahead2.x < MapWidth and ahead2.y >= 0 and ahead2.y < MapHeight and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and not isBlockedTerrain(env.terrain[ahead2.x][ahead2.y]) and spacingOk(ahead2):
      env.grid[blocker.pos.x][blocker.pos.y] = nil
      blocker.pos = ahead2
      env.grid[blocker.pos.x][blocker.pos.y] = blocker
      relocated = true
    elif ahead1.x >= 0 and ahead1.x < MapWidth and ahead1.y >= 0 and ahead1.y < MapHeight and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and not isBlockedTerrain(env.terrain[ahead1.x][ahead1.y]) and spacingOk(ahead1):
      env.grid[blocker.pos.x][blocker.pos.y] = nil
      blocker.pos = ahead1
      env.grid[blocker.pos.x][blocker.pos.y] = blocker
      relocated = true
    # Fallback to any adjacent empty tile around the lantern
    if not relocated:
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          if dx == 0 and dy == 0: continue
          let alt = ivec2(pos.x + dx, pos.y + dy)
          if alt.x < 0 or alt.y < 0 or alt.x >= MapWidth or alt.y >= MapHeight: continue
          if env.isEmpty(alt) and not env.hasDoor(alt) and not isBlockedTerrain(env.terrain[alt.x][alt.y]) and spacingOk(alt):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = alt
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            relocated = true
            break
        if relocated: break
    return relocated

  var finalPos = step1
  if not canEnter(step1):
    inc env.stats[id].actionInvalid
    return

  # Roads accelerate movement in the direction of entry.
  if env.terrain[step1.x][step1.y] == Road:
    let step2 = ivec2(agent.pos.x + delta.x.int32 * 2, agent.pos.y + delta.y.int32 * 2)
    if isValidPos(step2) and not isBlockedTerrain(env.terrain[step2.x][step2.y]) and env.canAgentPassDoor(agent, step2):
      if canEnter(step2):
        finalPos = step2

  env.grid[agent.pos.x][agent.pos.y] = nil
  # Clear old position and set new position
  env.updateObservations(AgentLayer, agent.pos, 0)  # Clear old
  agent.pos = finalPos
  agent.orientation = newOrientation
  env.grid[agent.pos.x][agent.pos.y] = agent

  # Update observations for new position only
  env.updateObservations(AgentLayer, agent.pos, getTeamId(agent.agentId) + 1)
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  inc env.stats[id].actionMove

proc transferAgentInventory(env: Environment, killer, victim: Thing) =
  ## Move the victim's inventory to the killer before the victim dies
  var keys: seq[ItemKey] = @[]
  for key, count in victim.inventory.pairs:
    if count > 0:
      keys.add(key)

  for key in keys:
    let count = getInv(victim, key)
    if count <= 0:
      continue
    let capacity = max(0, MapObjectAgentMaxInventory - getInv(killer, key))
    let moved = min(count, capacity)
    if moved > 0:
      setInv(killer, key, getInv(killer, key) + moved)
      env.updateAgentInventoryObs(killer, key)
    setInv(victim, key, 0)  # drop any overflow on the ground (currently unused)

proc thingKey(kind: ThingKind): ItemKey =
  ItemThingPrefix & $kind

proc parseThingKey(key: ItemKey, kind: var ThingKind): bool =
  if not key.startsWith(ItemThingPrefix):
    return false
  let name = key[ItemThingPrefix.len .. ^1]
  case name
  of "Wall": kind = Wall
  of "Mine": kind = Mine
  of "Converter": kind = Converter
  of "assembler": kind = assembler
  of "Spawner": kind = Spawner
  of "Armory": kind = Armory
  of "Forge": kind = Forge
  of "ClayOven": kind = ClayOven
  of "WeavingLoom": kind = WeavingLoom
  of "Bed": kind = Bed
  of "Chair": kind = Chair
  of "Table": kind = Table
  of "Statue": kind = Statue
  of "WatchTower": kind = WatchTower
  of "Barrel": kind = Barrel
  of "Mill": kind = Mill
  of "LumberCamp": kind = LumberCamp
  of "MiningCamp": kind = MiningCamp
  of "PlantedLantern": kind = PlantedLantern
  else:
    return false
  true

proc tryPickupThing(env: Environment, agent: Thing, thing: Thing): bool =
  if thing.kind in {Agent, Tumor, TreeObject, Cow, assembler}:
    return false
  let key = thingKey(thing.kind)
  let current = getInv(agent, key)
  if current >= MapObjectAgentMaxInventory:
    return false
  for itemKey, count in thing.inventory.pairs:
    let capacity = MapObjectAgentMaxInventory - getInv(agent, itemKey)
    if capacity < count:
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
  of assembler:
    env.updateObservations(assemblerLayer, thing.pos, 0)
    env.updateObservations(assemblerHeartsLayer, thing.pos, 0)
    env.updateObservations(assemblerReadyLayer, thing.pos, 0)
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
  if thing.kind == assembler and assemblerColors.hasKey(thing.pos):
    assemblerColors.del(thing.pos)

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
  of PlantedLantern:
    placed.teamId = getTeamId(agent.agentId)
    placed.lanternHealthy = true
  of assembler:
    placed.teamId = getTeamId(agent.agentId)
    placed.inventory = emptyInventory()
    placed.hearts = 0
  of Spawner:
    placed.homeSpawner = pos
  of Mine:
    placed.inventory = emptyInventory()
    placed.resources = MapObjectMineInitialResources
  else:
    discard
  env.add(placed)
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
  of assembler:
    env.updateObservations(assemblerLayer, pos, 1)
    env.updateObservations(assemblerHeartsLayer, pos, placed.hearts)
    env.updateObservations(assemblerReadyLayer, pos, placed.cooldown)
  else:
    discard
  if kind == assembler:
    let teamId = placed.teamId
    if teamId >= 0 and teamId < teamColors.len:
      assemblerColors[pos] = teamColors[teamId]
  true

proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  if victim.frozen >= 999999:
    return

  env.grid[victim.pos.x][victim.pos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryOreLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryBarLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWaterLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWheatLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWoodLayer, victim.pos, 0)
  env.updateObservations(AgentInventorySpearLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryLanternLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryArmorLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryBreadLayer, victim.pos, 0)

  env.terminated[victim.agentId] = 1.0
  victim.frozen = 999999
  victim.hp = 0
  victim.reward += env.config.deathPenalty

  victim.inventory = emptyInventory()

# Apply damage to an agent; respects armor and only freezes when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  if target.isNil or amount <= 0:
    return false

  var remaining = amount
  if target.inventoryArmor > 0:
    let absorbed = min(remaining, target.inventoryArmor)
    target.inventoryArmor = max(0, target.inventoryArmor - absorbed)
    remaining -= absorbed
    env.updateObservations(AgentInventoryArmorLayer, target.pos, target.inventoryArmor)

  if remaining > 0:
    target.hp = max(0, target.hp - remaining)

  if target.hp <= 0:
    if attacker != nil:
      env.transferAgentInventory(attacker, target)
    env.killAgent(target)
    return true

  return false

# Heal an agent up to its max HP. Returns the amount actually healed.
proc applyAgentHeal(env: Environment, target: Thing, amount: int): int =
  if target.isNil or amount <= 0:
    return 0
  let before = target.hp
  target.hp = min(target.maxHp, target.hp + amount)
  result = target.hp - before

# Heal burst around an agent (used when consuming bread)
proc applyHealBurst(env: Environment, agent: Thing) =
  let tint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1)
  for dx in -1 .. 1:
    for dy in -1 .. 1:
      let p = agent.pos + ivec2(dx, dy)
      env.applyActionTint(p, tint, 2, ActionTintHeal)
      let occ = env.getThing(p)
      if not occ.isNil and occ.kind == Agent:
        let healAmt = min(BreadHealAmount, occ.maxHp - occ.hp)
        if healAmt > 0:
          discard env.applyAgentHeal(occ, healAmt)

# Centralized zero-HP handling so agents instantly freeze/die when drained
proc enforceZeroHpDeaths(env: Environment) =
  for agent in env.agents:
    if agent.isNil:
      continue
    if env.terminated[agent.agentId] == 0.0 and agent.hp <= 0:
      env.killAgent(agent)

proc attackAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Attack an entity in one of eight directions. Spears extend range to 2 tiles.
  if argument < 0 or argument > 7:
    inc env.stats[id].actionInvalid
    return

  let attackOrientation = Orientation(argument)
  let delta = getOrientationDelta(attackOrientation)
  let hasSpear = agent.inventorySpear > 0
  let maxRange = if hasSpear: 2 else: 1
  let attackerTeam = getTeamId(agent.agentId)

  proc tryDamageDoor(pos: IVec2): bool =
    if not env.hasDoor(pos):
      return false
    if env.getDoorTeam(pos) == attackerTeam:
      return false
    if env.doorHearts[pos.x][pos.y] > 0:
      env.doorHearts[pos.x][pos.y] = env.doorHearts[pos.x][pos.y] - 1
      if env.doorHearts[pos.x][pos.y] <= 0:
        env.doorHearts[pos.x][pos.y] = 0
        env.doorTeams[pos.x][pos.y] = -1
    return true

  proc claimAssembler(assemblerThing: Thing) =
    let oldTeam = assemblerThing.teamId
    assemblerThing.teamId = attackerTeam
    if attackerTeam >= 0 and attackerTeam < teamColors.len:
      assemblerColors[assemblerThing.pos] = teamColors[attackerTeam]
    if oldTeam >= 0:
      for x in 0 ..< MapWidth:
        for y in 0 ..< MapHeight:
          if env.doorTeams[x][y] == oldTeam.int16:
            env.doorTeams[x][y] = attackerTeam.int16

  # Special combat visuals
  if hasSpear:
    env.applySpearStrike(agent, attackOrientation)
  if agent.inventoryArmor > 0:
    env.applyShieldBand(agent, attackOrientation)
    env.shieldCountdown[agent.agentId] = 2

  # Spear: area strike (3 forward + diagonals)
  if hasSpear:
    var hit = false
    proc applyDamageAt(pos: IVec2) =
      if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
        return
      if tryDamageDoor(pos):
        hit = true
        return
      let target = env.getThing(pos)
      if isNil(target):
        return
      case target.kind
      of Tumor:
        env.grid[pos.x][pos.y] = nil
        env.updateObservations(AgentLayer, pos, 0)
        env.updateObservations(AgentOrientationLayer, pos, 0)
        let idx = env.things.find(target)
        if idx >= 0: env.things.del(idx)
        agent.reward += env.config.tumorKillReward
        hit = true
      of Spawner:
        env.grid[pos.x][pos.y] = nil
        let idx = env.things.find(target)
        if idx >= 0: env.things.del(idx)
        hit = true
      of Agent:
        if target.agentId == agent.agentId: return
        if getTeamId(target.agentId) == getTeamId(agent.agentId): return
        discard env.applyAgentDamage(target, 1, agent)
        hit = true
      of assembler:
        if target.teamId == attackerTeam:
          return
        target.hearts = max(0, target.hearts - 1)
        env.updateObservations(assemblerHeartsLayer, target.pos, target.hearts)
        hit = true
        if target.hearts == 0:
          claimAssembler(target)
      else:
        discard

    let left = ivec2(-delta.y, delta.x)
    let right = ivec2(delta.y, -delta.x)
    for step in 1 .. 3:
      let forward = agent.pos + ivec2(delta.x * step, delta.y * step)
      applyDamageAt(forward)
      # Keep spear width contiguous (no skipping): lateral offset is fixed 1 tile.
      applyDamageAt(forward + left)
      applyDamageAt(forward + right)

    if hit:
      agent.inventorySpear = max(0, agent.inventorySpear - 1)
      env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
      inc env.stats[id].actionAttack
    else:
      inc env.stats[id].actionInvalid
    return

  var attackHit = false

  for distance in 1 .. maxRange:
    let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
    if attackPos.x < 0 or attackPos.x >= MapWidth or attackPos.y < 0 or attackPos.y >= MapHeight:
      continue

    if tryDamageDoor(attackPos):
      attackHit = true
      break

    let target = env.getThing(attackPos)
    if isNil(target):
      continue

    case target.kind
    of Tumor:
      env.grid[attackPos.x][attackPos.y] = nil
      env.updateObservations(AgentLayer, attackPos, 0)
      env.updateObservations(AgentOrientationLayer, attackPos, 0)
      let idx = env.things.find(target)
      if idx >= 0:
        env.things.del(idx)
      agent.reward += env.config.tumorKillReward
      attackHit = true
    of Spawner:
      env.grid[attackPos.x][attackPos.y] = nil
      let idx = env.things.find(target)
      if idx >= 0:
        env.things.del(idx)
      attackHit = true
    of Agent:
      if target.agentId == agent.agentId:
        continue
      if getTeamId(target.agentId) == getTeamId(agent.agentId):
        continue
      discard env.applyAgentDamage(target, 1, agent)
      attackHit = true
    of assembler:
      if target.teamId == attackerTeam:
        continue
      target.hearts = max(0, target.hearts - 1)
      env.updateObservations(assemblerHeartsLayer, target.pos, target.hearts)
      attackHit = true
      if target.hearts == 0:
        claimAssembler(target)
    else:
      discard

    if attackHit:
      break

  if attackHit:
    if hasSpear:
      agent.inventorySpear = max(0, agent.inventorySpear - 1)
      env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
    inc env.stats[id].actionAttack
  else:
    inc env.stats[id].actionInvalid

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
    case env.terrain[targetPos.x][targetPos.y]:
    of Bridge:
      # Bridges are walkable and have no direct interaction
      inc env.stats[id].actionInvalid
      return
    of Road:
      # Roads are for movement only
      inc env.stats[id].actionInvalid
      return
    of Water:
      if agent.inventoryWater < MapObjectAgentMaxInventory:
        agent.inventoryWater = agent.inventoryWater + 1
        env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)
        agent.reward += env.config.waterReward
        inc env.stats[id].actionUse
        return
      if env.giveItem(agent, ItemFishRaw):
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Wheat:
      if agent.inventoryWheat < MapObjectAgentMaxInventory:
        let gain = min(2, MapObjectAgentMaxInventory - agent.inventoryWheat)
        agent.inventoryWheat = agent.inventoryWheat + gain
        env.terrain[targetPos.x][targetPos.y] = Empty
        agent.reward += env.config.wheatReward
        env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
        inc env.stats[id].actionUse
        return
      if env.giveFirstAvailable(agent, [ItemSeeds, ItemPlant]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Tree, Palm:
      if getInv(agent, ItemAxe) <= 0:
        inc env.stats[id].actionInvalid
        return
      if agent.inventoryWood < MapObjectAgentMaxInventory:
        let gain = min(2, MapObjectAgentMaxInventory - agent.inventoryWood)
        agent.inventoryWood = agent.inventoryWood + gain
        env.terrain[targetPos.x][targetPos.y] = Empty
        agent.reward += env.config.woodReward
        env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
        inc env.stats[id].actionUse
        return
      if env.giveItem(agent, ItemBranch):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Rock:
      if env.giveFirstAvailable(agent, [ItemBoulder, ItemRock]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Stalagmite:
      if env.giveFirstAvailable(agent, [ItemBoulder, ItemRock]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Gem:
      if env.giveItem(agent, ItemRough):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Bush:
      if env.giveFirstAvailable(agent, [ItemPlantGrowth, ItemSeeds, ItemPlant]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Cactus:
      if env.giveFirstAvailable(agent, [ItemPlantGrowth, ItemSeeds, ItemPlant]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Animal:
      if env.giveFirstAvailable(agent, [ItemMeat, ItemSkinTanned, ItemTotem, ItemCorpse,
                                        ItemCorpsePiece, ItemRemains, ItemGlob, ItemVermin,
                                        ItemPet, ItemEgg]):
        env.terrain[targetPos.x][targetPos.y] = Empty
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
    of Grass:
      # Decorative ground cover only
      inc env.stats[id].actionInvalid
      return
    of Sand, Snow, Dune:
      # Decorative/blocked ground cover only
      inc env.stats[id].actionInvalid
      return
    of Fertile:
      # Nothing to harvest directly from fertile soil
      inc env.stats[id].actionInvalid
      return
    of Empty:
      if env.hasDoor(targetPos):
        inc env.stats[id].actionInvalid
        return
      # Heal burst: consume bread to heal nearby allied agents (and self) for 1 HP
      if agent.inventoryBread > 0:
        agent.inventoryBread = max(0, agent.inventoryBread - 1)
        env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
        env.applyHealBurst(agent)
        inc env.stats[id].actionUse
        return
      # Place any carried Thing onto the empty tile.
      let carriedThing = firstThingItem(agent)
      if carriedThing != ItemNone:
        if placeThingFromKey(env, agent, carriedThing, targetPos):
          setInv(agent, carriedThing, getInv(agent, carriedThing) - 1)
          env.updateAgentInventoryObs(agent, carriedThing)
          inc env.stats[id].actionUse
          return
      # Build a barrel on an empty tile using wood (only if not carrying water)
      if agent.inventoryWood > 0 and agent.inventoryWater == 0:
        agent.inventoryWood = max(0, agent.inventoryWood - 1)
        env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
        env.add(Thing(
          kind: Barrel,
          pos: targetPos,
          barrelCapacity: BarrelCapacity
        ))
        inc env.stats[id].actionUse
        return
      # Water an empty tile adjacent to wheat or trees to encourage growth
      if agent.inventoryWater > 0:
        agent.inventoryWater = max(0, agent.inventoryWater - 1)
        env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)

        # Create fertile terrain for future planting
        env.terrain[targetPos.x][targetPos.y] = Fertile
        env.resetTileColor(targetPos)
        env.updateObservations(TintLayer, targetPos, 0)  # ensure obs consistency

        inc env.stats[id].actionUse
        return
      # Build a watchtower on an empty tile
      if agent.inventoryWood >= WatchTowerWoodCost:
        agent.inventoryWood = max(0, agent.inventoryWood - WatchTowerWoodCost)
        env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
        env.add(Thing(
          kind: WatchTower,
          pos: targetPos
        ))
        inc env.stats[id].actionUse
        return
      inc env.stats[id].actionInvalid
      return
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
  of TreeObject:
    let hasAxe = getInv(agent, ItemAxe) > 0
    if agent.inventoryWood < MapObjectAgentMaxInventory:
      let baseGain =
        if hasAxe:
          if thing.treeVariant == TreeVariantPine: 5 else: 2
        else:
          1
      let gain = min(baseGain, MapObjectAgentMaxInventory - agent.inventoryWood)
      agent.inventoryWood = agent.inventoryWood + gain
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      agent.reward += env.config.woodReward
      if hasAxe:
        removeThing(env, thing)
      used = true
    elif env.giveItem(agent, ItemBranch):
      if hasAxe:
        removeThing(env, thing)
      used = true
    else:
      inc env.stats[id].actionInvalid
      return
  of Mine:
    if thing.cooldown == 0 and agent.inventoryOre < MapObjectAgentMaxInventory:
      agent.inventoryOre = agent.inventoryOre + 1
      env.updateObservations(AgentInventoryOreLayer, agent.pos, agent.inventoryOre)
      thing.cooldown = MapObjectMineCooldown
      env.updateObservations(MineReadyLayer, thing.pos, thing.cooldown)
      if agent.inventoryOre == 1: agent.reward += env.config.oreReward
      used = true
  of Converter:
    if thing.cooldown == 0 and agent.inventoryOre > 0 and agent.inventoryBar < MapObjectAgentMaxInventory:
      agent.inventoryOre = agent.inventoryOre - 1
      agent.inventoryBar = agent.inventoryBar + 1
      env.updateObservations(AgentInventoryOreLayer, agent.pos, agent.inventoryOre)
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.cooldown = 0
      env.updateObservations(ConverterReadyLayer, thing.pos, 1)
      if agent.inventoryBar == 1: agent.reward += env.config.barReward
      used = true
  of Forge:
    if thing.cooldown == 0 and agent.inventoryWood > 0 and agent.inventorySpear == 0:
      agent.inventoryWood = agent.inventoryWood - 1
      agent.inventorySpear = SpearCharges
      thing.cooldown = 5
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
      agent.reward += env.config.spearReward
      used = true
    elif thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationForge, thing):
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
    if thing.cooldown == 0 and agent.inventoryWood > 0 and agent.inventoryArmor == 0:
      agent.inventoryWood = agent.inventoryWood - 1
      agent.inventoryArmor = ArmorPoints
      thing.cooldown = 20
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      env.updateObservations(AgentInventoryArmorLayer, agent.pos, agent.inventoryArmor)
      agent.reward += env.config.armorReward
      used = true
    elif thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationArmory, thing):
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
  of Table:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationTable, thing):
        used = true
  of Chair:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationChair, thing):
        used = true
  of Bed:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationBed, thing):
        used = true
  of Statue:
    if thing.cooldown == 0:
      if env.tryCraftAtStation(agent, StationStatue, thing):
        used = true
  of assembler:
    if thing.cooldown == 0 and agent.inventoryBar >= 1:
      agent.inventoryBar = agent.inventoryBar - 1
      env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
      thing.hearts = thing.hearts + 1
      thing.cooldown = MapObjectassemblerCooldown
      env.updateObservations(assemblerHeartsLayer, thing.pos, thing.hearts)
      env.updateObservations(assemblerReadyLayer, thing.pos, thing.cooldown)
      agent.reward += env.config.heartReward
      used = true
  of Barrel:
    if env.useStorageBuilding(agent, thing, @[]):
      used = true
  of Mill:
    if env.useStorageBuilding(agent, thing, @[ItemWheat]):
      used = true
  of LumberCamp:
    if env.useStorageBuilding(agent, thing, @[ItemWood, ItemBranch]):
      used = true
  of MiningCamp:
    if env.useStorageBuilding(agent, thing, @[ItemOre, ItemBoulder, ItemRough]):
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

proc swapAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Swap
  if argument > 1:
    inc env.stats[id].actionInvalid
    return
  let
    targetPos = agent.pos + orientationToVec(agent.orientation)
    target = env.getThing(targetPos)
  if target == nil:
    inc env.stats[id].actionInvalid
    return
  if target.kind == Agent and not isThingFrozen(target, env):
    var temp = agent.pos
    agent.pos = target.pos
    target.pos = temp
    inc env.stats[id].actionSwap
    # REMOVED: expensive per-agent full grid rebuilds
  else:
    inc env.stats[id].actionInvalid



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
    if env.isEmpty(targetPos) and not env.hasDoor(targetPos) and not isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) and not isTileFrozen(targetPos, env):
      let carriedThing = firstThingItem(agent)
      if carriedThing != ItemNone:
        if placeThingFromKey(env, agent, carriedThing, targetPos):
          setInv(agent, carriedThing, getInv(agent, carriedThing) - 1)
          env.updateAgentInventoryObs(agent, carriedThing)
          inc env.stats[id].actionPut
          return
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
  elif agent.inventoryBread > 0 and target.inventoryBread < MapObjectAgentMaxInventory:
    let giveAmt = min(agent.inventoryBread, MapObjectAgentMaxInventory - target.inventoryBread)
    agent.inventoryBread = agent.inventoryBread - giveAmt
    target.inventoryBread = target.inventoryBread + giveAmt
    transferred = true
  else:
    var bestKey = ItemNone
    var bestCount = 0
    for key, count in agent.inventory.pairs:
      if count <= 0:
        continue
      let capacity = MapObjectAgentMaxInventory - getInv(target, key)
      if capacity <= 0:
        continue
      if count > bestCount:
        bestKey = key
        bestCount = count
    if bestKey != ItemNone and bestCount > 0:
      let capacity = max(0, MapObjectAgentMaxInventory - getInv(target, bestKey))
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
# ============== CLIPPY AI ==============




{.push inline.}
proc isValidEmptyPosition(env: Environment, pos: IVec2): bool =
  ## Check if a position is within map bounds, empty, and not blocked terrain
  pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
  pos.y >= MapBorder and pos.y < MapHeight - MapBorder and
  env.isEmpty(pos) and not env.hasDoor(pos) and not isBlockedTerrain(env.terrain[pos.x][pos.y])

proc generateRandomMapPosition(r: var Rand): IVec2 =
  ## Generate a random position within map boundaries
  ivec2(
    int32(randIntExclusive(r, MapBorder, MapWidth - MapBorder)),
    int32(randIntExclusive(r, MapBorder, MapHeight - MapBorder))
  )
{.pop.}

proc findEmptyPositionsAround*(env: Environment, center: IVec2, radius: int): seq[IVec2] =
  ## Find empty positions around a center point within a given radius
  result = @[]
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        result.add(pos)

proc findFirstEmptyPositionAround*(env: Environment, center: IVec2, radius: int): IVec2 =
  ## Find first empty position around center (no allocation)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        return pos
  return ivec2(-1, -1)  # No empty position found


const
  TumorBranchRange = 5
  TumorBranchMinAge = 2
  TumorBranchChance = 0.1
  TumorAdjacencyDeathChance = 1.0 / 3.0

proc findTumorBranchTarget(tumor: Thing, env: Environment, r: var Rand): IVec2 =
  ## Pick a random empty tile within the tumor's branching range
  var candidates: seq[IVec2] = @[]

  for dx in -TumorBranchRange .. TumorBranchRange:
    for dy in -TumorBranchRange .. TumorBranchRange:
      if dx == 0 and dy == 0:
        continue
      if max(abs(dx), abs(dy)) > TumorBranchRange:
        continue
      let candidate = ivec2(tumor.pos.x + dx, tumor.pos.y + dy)
      if not env.isValidEmptyPosition(candidate):
        continue

      var adjacentTumor = false
      for adj in [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]:
        let checkPos = candidate + adj
        if not isValidPos(checkPos):
          continue
        let occupant = env.getThing(checkPos)
        if not isNil(occupant) and occupant.kind == Tumor:
          adjacentTumor = true
          break
      if not adjacentTumor:
        candidates.add(candidate)

  if candidates.len == 0:
    return ivec2(-1, -1)

  return candidates[randIntExclusive(r, 0, candidates.len)]

proc randomEmptyPos(r: var Rand, env: Environment): IVec2 =
  # Try with moderate attempts first
  for i in 0 ..< 100:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  # Try harder with more attempts
  for i in 0 ..< 1000:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  quit("Failed to find an empty position, map too full!")

proc clearTintModifications(env: Environment) =
  ## Clear only active tile modifications for performance
  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
      env.tintMods[tileX][tileY] = TintModification(r: 0, g: 0, b: 0)
      env.activeTiles.flags[tileX][tileY] = false

  # Clear the active list for next frame
  env.activeTiles.positions.setLen(0)

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Clear previous frame's modifications
  env.clearTintModifications()

  template markActiveTile(tileX, tileY: int) =
    if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
      if not env.activeTiles.flags[tileX][tileY]:
        env.activeTiles.flags[tileX][tileY] = true
        env.activeTiles.positions.add(ivec2(tileX, tileY))

  # Helper: add team tint in a radius with simple Manhattan falloff
  proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        let tileX = baseX + dx
        let tileY = baseY + dy
        if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
          let dist = abs(dx) + abs(dy)
          let falloff = max(1, radius * 2 + 1 - dist)
          markActiveTile(tileX, tileY)
          let strength = scale.float32 * falloff.float32
          safeTintAdd(env.tintMods[tileX][tileY].r, int((color.r - 0.7) * strength))
          safeTintAdd(env.tintMods[tileX][tileY].g, int((color.g - 0.65) * strength))
          safeTintAdd(env.tintMods[tileX][tileY].b, int((color.b - 0.6) * strength))

  # Process all entities and mark their affected positions as active
  for thing in env.things:
    let pos = thing.pos
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    let baseX = pos.x.int
    let baseY = pos.y.int

    case thing.kind
    of Tumor:
      # Tumors create creep spread in 5x5 area (active seeds glow brighter)
      let creepIntensity = if thing.hasClaimedTerritory: 2 else: 1

      for dx in -2 .. 2:
        for dy in -2 .. 2:
          let tileX = baseX + dx
          let tileY = baseY + dy
          if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
            # Distance-based falloff for more organic look
            let manDist = abs(dx) + abs(dy)  # Manhattan distance
            let falloff = max(1, 5 - manDist)  # Stronger at center, weaker at edges (5x5 grid)
            markActiveTile(tileX, tileY)

            # Tumor creep effect with overflow protection
            safeTintAdd(env.tintMods[tileX][tileY].r, -15 * creepIntensity * falloff)
            safeTintAdd(env.tintMods[tileX][tileY].g, -8 * creepIntensity * falloff)
            safeTintAdd(env.tintMods[tileX][tileY].b, 20 * creepIntensity * falloff)

    of Agent:
      let tribeId = thing.agentId
      if tribeId < agentVillageColors.len:
        addTintArea(baseX, baseY, agentVillageColors[tribeId], radius = 2, scale = 90)

    of PlantedLantern:
      if thing.lanternHealthy and thing.teamId >= 0 and thing.teamId < teamColors.len:
        addTintArea(baseX, baseY, teamColors[thing.teamId], radius = 2, scale = 60)

    else:
      discard

proc applyTintModifications(env: Environment) =
  ## Apply tint modifications to entity positions and their surrounding areas

  # Apply modifications only to tiles touched this frame
  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      continue

    # Skip if tint modifications are below minimum threshold
    let tint = env.tintMods[tileX][tileY]
    if abs(tint.r) < MinTintEpsilon and abs(tint.g) < MinTintEpsilon and abs(tint.b) < MinTintEpsilon:
      continue

    # Skip tinting on water tiles (rivers should remain clean)
    if env.terrain[tileX][tileY] == Water:
      continue

    # Get current color as integers (scaled by 1000 for precision)
    var r = int(env.tileColors[tileX][tileY].r * 1000)
    var g = int(env.tileColors[tileX][tileY].g * 1000)
    var b = int(env.tileColors[tileX][tileY].b * 1000)

    # Apply unified tint modifications
    r += tint.r div 10  # 10% of the modification
    g += tint.g div 10
    b += tint.b div 10

    # Convert back to float with clamping
    env.tileColors[tileX][tileY].r = min(max(r.float32 / 1000.0, 0.3), 1.2)
    env.tileColors[tileX][tileY].g = min(max(g.float32 / 1000.0, 0.3), 1.2)
    env.tileColors[tileX][tileY].b = min(max(b.float32 / 1000.0, 0.3), 1.2)

  # Apply global decay to ALL tiles (but infrequently for performance)
  if env.currentStep mod 30 == 0 and env.currentStep > 0:
    let decay = 0.98'f32  # 2% decay every 30 steps

    for x in 0 ..< MapWidth:
      for y in 0 ..< MapHeight:
        # Get the base color for this tile (could be team color for houses)
        let baseR = env.baseTileColors[x][y].r
        let baseG = env.baseTileColors[x][y].g
        let baseB = env.baseTileColors[x][y].b

        # Only decay if color differs from base (avoid floating point errors)
        # Lowered threshold to allow subtle creep effects to be balanced by decay
        if abs(env.tileColors[x][y].r - baseR) > 0.001 or
           abs(env.tileColors[x][y].g - baseG) > 0.001 or
           abs(env.tileColors[x][y].b - baseB) > 0.001:
          env.tileColors[x][y].r = env.tileColors[x][y].r * decay + baseR * (1.0 - decay)
          env.tileColors[x][y].g = env.tileColors[x][y].g * decay + baseG * (1.0 - decay)
          env.tileColors[x][y].b = env.tileColors[x][y].b * decay + baseB * (1.0 - decay)

        # Also decay intensity back to base intensity
        let baseIntensity = env.baseTileColors[x][y].intensity
        if abs(env.tileColors[x][y].intensity - baseIntensity) > 0.01:
          env.tileColors[x][y].intensity = env.tileColors[x][y].intensity * decay + baseIntensity * (1.0 - decay)

proc add(env: Environment, thing: Thing) =
  if thing.inventory.len == 0:
    thing.inventory = emptyInventory()
  env.things.add(thing)
  if thing.kind == Agent:
    env.agents.add(thing)
    env.stats.add(Stats())
  if isValidPos(thing.pos):
    env.grid[thing.pos.x][thing.pos.y] = thing

proc plantAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant lantern at agent's current position - argument specifies direction (0=N, 1=S, 2=W, 3=E, 4=NW, 5=NE, 6=SW, 7=SE)
  if argument > 7:
    inc env.stats[id].actionInvalid
    return

  # Calculate target position based on orientation argument
  let plantOrientation = Orientation(argument)
  let delta = getOrientationDelta(plantOrientation)
  var targetPos = agent.pos
  targetPos.x += int32(delta.x)
  targetPos.y += int32(delta.y)

  # Check bounds
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return

  # Check if position is empty and not water
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  if agent.inventoryLantern > 0:
    # Calculate team ID directly from the planting agent's ID
    let teamId = getTeamId(agent.agentId)

    # Plant the lantern
    let lantern = Thing(
      kind: PlantedLantern,
      pos: targetPos,
      teamId: teamId,
      lanternHealthy: true
    )

    env.add(lantern)

    # Consume the lantern from agent's inventory
    agent.inventoryLantern = 0

    # Give reward for planting
    agent.reward += env.config.clothReward * 0.5  # Half reward for planting

    inc env.stats[id].actionPlant
  elif agent.inventoryWood >= RoadWoodCost:
    # Build a road tile on empty terrain
    if env.terrain[targetPos.x][targetPos.y] != Empty:
      inc env.stats[id].actionInvalid
      return

    agent.inventoryWood = max(0, agent.inventoryWood - RoadWoodCost)
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)

    env.terrain[targetPos.x][targetPos.y] = Road
    env.resetTileColor(targetPos)
    env.updateObservations(TintLayer, targetPos, 0)

    inc env.stats[id].actionPlant
  else:
    inc env.stats[id].actionInvalid

proc plantResourceAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant wheat (args 0-3) or tree (args 4-7) onto an adjacent fertile tile
  if argument < 0 or argument >= 8:
    inc env.stats[id].actionInvalid
    return

  let plantingTree = argument >= 4
  let dirIndex = if plantingTree: argument - 4 else: argument
  let orientation = Orientation(dirIndex)
  let delta = getOrientationDelta(orientation)
  let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)

  # Bounds and occupancy checks
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return
  if env.terrain[targetPos.x][targetPos.y] != Fertile:
    inc env.stats[id].actionInvalid
    return

  if plantingTree:
    if agent.inventoryWood <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWood = max(0, agent.inventoryWood - 1)
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
    env.terrain[targetPos.x][targetPos.y] = Empty
    env.resetTileColor(targetPos)
    env.add(Thing(
      kind: TreeObject,
      pos: targetPos,
      treeVariant: TreeVariantPine
    ))
  else:
    if agent.inventoryWheat <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
    env.terrain[targetPos.x][targetPos.y] = Wheat
    env.resetTileColor(targetPos)

  # Consuming fertility (terrain replaced above)
  inc env.stats[id].actionPlantResource
