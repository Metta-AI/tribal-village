# This file is included by src/environment.nim
proc noopAction(env: Environment, id: int, agent: Thing) =
  inc env.stats[id].actionNoop


proc moveAction(env: Environment, id: int, agent: Thing, argument: int) =
  if argument < 0 or argument > 7:
    inc env.stats[id].actionInvalid
    return

  let moveOrientation = Orientation(argument)
  let delta = getOrientationDelta(moveOrientation)

  var newPos = agent.pos
  newPos.x += int32(delta.x)
  newPos.y += int32(delta.y)

  # Prevent moving onto water tiles (bridges remain walkable).
  if env.terrain[newPos.x][newPos.y] == Water:
    inc env.stats[id].actionInvalid
    return

  if not env.canAgentPassDoor(agent, newPos):
    inc env.stats[id].actionInvalid
    return

  let newOrientation = moveOrientation
  # Allow walking through planted lanterns by relocating the lantern, preferring push direction (up to 2 tiles ahead)
  var canMove = env.isEmpty(newPos)
  if not canMove:
    let blocker = env.getThing(newPos)
    if not isNil(blocker) and blocker.kind == PlantedLantern:
      var relocated = false
      # Helper to ensure lantern spacing (Chebyshev >= 3 from other lanterns)
      template spacingOk(newPos: IVec2): bool =
        var ok = true
        for t in env.things:
          if t.kind == PlantedLantern and t != blocker:
            let dist = max(abs(t.pos.x - newPos.x), abs(t.pos.y - newPos.y))
            if dist < 3'i32:
              ok = false
              break
        ok
      # Preferred push positions in move direction
      let ahead1 = ivec2(newPos.x + delta.x, newPos.y + delta.y)
      let ahead2 = ivec2(newPos.x + delta.x * 2, newPos.y + delta.y * 2)
      if ahead2.x >= 0 and ahead2.x < MapWidth and ahead2.y >= 0 and ahead2.y < MapHeight and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and env.terrain[ahead2.x][ahead2.y] != Water and spacingOk(ahead2):
        env.grid[blocker.pos.x][blocker.pos.y] = nil
        blocker.pos = ahead2
        env.grid[blocker.pos.x][blocker.pos.y] = blocker
        relocated = true
      elif ahead1.x >= 0 and ahead1.x < MapWidth and ahead1.y >= 0 and ahead1.y < MapHeight and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and env.terrain[ahead1.x][ahead1.y] != Water and spacingOk(ahead1):
        env.grid[blocker.pos.x][blocker.pos.y] = nil
        blocker.pos = ahead1
        env.grid[blocker.pos.x][blocker.pos.y] = blocker
        relocated = true
      # Fallback to any adjacent empty tile around the lantern
      if not relocated:
        for dy in -1 .. 1:
          for dx in -1 .. 1:
            if dx == 0 and dy == 0: continue
            let alt = ivec2(newPos.x + dx, newPos.y + dy)
            if alt.x < 0 or alt.y < 0 or alt.x >= MapWidth or alt.y >= MapHeight: continue
            if env.isEmpty(alt) and not env.hasDoor(alt) and env.terrain[alt.x][alt.y] != Water and spacingOk(alt):
              env.grid[blocker.pos.x][blocker.pos.y] = nil
              blocker.pos = alt
              env.grid[blocker.pos.x][blocker.pos.y] = blocker
              relocated = true
              break
          if relocated: break
      if relocated:
        canMove = true

  if canMove:
    env.grid[agent.pos.x][agent.pos.y] = nil
    # Clear old position and set new position
    env.updateObservations(AgentLayer, agent.pos, 0)  # Clear old
    agent.pos = newPos
    agent.orientation = newOrientation
    env.grid[agent.pos.x][agent.pos.y] = agent

    # Update observations for new position only
    env.updateObservations(AgentLayer, agent.pos, getTeamId(agent.agentId) + 1)
    env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
    inc env.stats[id].actionMove
  else:
    inc env.stats[id].actionInvalid

proc transferAgentInventory(env: Environment, killer, victim: Thing) =
  ## Move the victim's inventory to the killer before the victim dies
  template moveAll(field: untyped, layer: ObservationName) =
    if victim.field > 0:
      let capacity = max(0, MapObjectAgentMaxInventory - killer.field)
      let gained = min(victim.field, capacity)
      if gained > 0:
        killer.field += gained
        env.updateObservations(layer, killer.pos, killer.field)
      victim.field = 0  # drop any overflow on the ground (currently unused)

  moveAll(inventoryOre, AgentInventoryOreLayer)
  moveAll(inventoryBattery, AgentInventoryBatteryLayer)
  moveAll(inventoryWater, AgentInventoryWaterLayer)
  moveAll(inventoryWheat, AgentInventoryWheatLayer)
  moveAll(inventoryWood, AgentInventoryWoodLayer)
  moveAll(inventorySpear, AgentInventorySpearLayer)
  moveAll(inventoryLantern, AgentInventoryLanternLayer)
  moveAll(inventoryArmor, AgentInventoryArmorLayer)
  moveAll(inventoryBread, AgentInventoryBreadLayer)

proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  if victim.frozen >= 999999:
    return

  env.grid[victim.pos.x][victim.pos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryOreLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryBatteryLayer, victim.pos, 0)
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

  victim.inventoryOre = 0
  victim.inventoryBattery = 0
  victim.inventoryWater = 0
  victim.inventoryWheat = 0
  victim.inventoryWood = 0
  victim.inventorySpear = 0
  victim.inventoryLantern = 0
  victim.inventoryArmor = 0
  victim.inventoryBread = 0

# Apply damage to an agent; respects armor and only freezes when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  if target.isNil or amount <= 0:
    return false

  var remaining = amount
  if target.inventoryArmor > 0:
    let absorbed = min(remaining, target.inventoryArmor)
    target.inventoryArmor -= absorbed
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

  # Terrain use first
  case env.terrain[targetPos.x][targetPos.y]:
  of Bridge:
    # Bridges are walkable and have no direct interaction
    inc env.stats[id].actionInvalid
    return
  of Water:
    if agent.inventoryWater < MapObjectAgentMaxInventory:
      agent.inventoryWater += 1
      env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)
      agent.reward += env.config.waterReward
      inc env.stats[id].actionUse
      return
    else:
      inc env.stats[id].actionInvalid
      return
  of Wheat:
    if agent.inventoryWheat < MapObjectAgentMaxInventory:
      let gain = min(2, MapObjectAgentMaxInventory - agent.inventoryWheat)
      agent.inventoryWheat += gain
      env.terrain[targetPos.x][targetPos.y] = Empty
      agent.reward += env.config.wheatReward
      env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
      inc env.stats[id].actionUse
      return
    else:
      inc env.stats[id].actionInvalid
      return
  of Tree:
    if agent.inventoryWood < MapObjectAgentMaxInventory:
      let gain = min(2, MapObjectAgentMaxInventory - agent.inventoryWood)
      agent.inventoryWood += gain
      env.terrain[targetPos.x][targetPos.y] = Empty
      agent.reward += env.config.woodReward
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      inc env.stats[id].actionUse
      return
    else:
      inc env.stats[id].actionInvalid
      return
  of Fertile:
    # Nothing to harvest directly from fertile soil
    inc env.stats[id].actionInvalid
    return
  of Empty:
    # Only treat as terrain if the tile has no occupying Thing; otherwise fall through to building logic.
    if env.isEmpty(targetPos) and not env.hasDoor(targetPos):
      # Heal burst: consume bread to heal nearby allied agents (and self) for 1 HP
      if agent.inventoryBread > 0:
        agent.inventoryBread = max(0, agent.inventoryBread - 1)
        env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
        env.applyHealBurst(agent)
        inc env.stats[id].actionUse
        return
      # Water an empty tile adjacent to wheat or trees to encourage growth
      if agent.inventoryWater > 0:
        agent.inventoryWater = max(0, agent.inventoryWater - 1)
        env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)

        # Create fertile terrain for future planting
        env.terrain[targetPos.x][targetPos.y] = Fertile
        env.tileColors[targetPos.x][targetPos.y] = BaseTileColorDefault
        env.baseTileColors[targetPos.x][targetPos.y] = BaseTileColorDefault
        env.updateObservations(TintLayer, targetPos, 0)  # ensure obs consistency

        inc env.stats[id].actionUse
        return

    discard

  # Building use
  let thing = env.getThing(targetPos)
  if isNil(thing):
    inc env.stats[id].actionInvalid
    return
  # Prevent interacting with frozen objects/buildings
  if isThingFrozen(thing, env):
    inc env.stats[id].actionInvalid
    return

  case thing.kind:
  of Mine:
    if thing.cooldown == 0 and agent.inventoryOre < MapObjectAgentMaxInventory:
      agent.inventoryOre += 1
      env.updateObservations(AgentInventoryOreLayer, agent.pos, agent.inventoryOre)
      thing.cooldown = MapObjectMineCooldown
      env.updateObservations(MineReadyLayer, thing.pos, thing.cooldown)
      if agent.inventoryOre == 1: agent.reward += env.config.oreReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of Converter:
    if thing.cooldown == 0 and agent.inventoryOre > 0 and agent.inventoryBattery < MapObjectAgentMaxInventory:
      agent.inventoryOre -= 1
      agent.inventoryBattery += 1
      env.updateObservations(AgentInventoryOreLayer, agent.pos, agent.inventoryOre)
      env.updateObservations(AgentInventoryBatteryLayer, agent.pos, agent.inventoryBattery)
      thing.cooldown = 0
      env.updateObservations(ConverterReadyLayer, thing.pos, 1)
      if agent.inventoryBattery == 1: agent.reward += env.config.batteryReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of Forge:
    if thing.cooldown == 0 and agent.inventoryWood > 0 and agent.inventorySpear == 0:
      agent.inventoryWood -= 1
      agent.inventorySpear = SpearCharges
      thing.cooldown = 5
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
      agent.reward += env.config.spearReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of WeavingLoom:
    if thing.cooldown == 0 and agent.inventoryWheat > 0 and agent.inventoryLantern == 0:
      agent.inventoryWheat -= 1
      agent.inventoryLantern = 1
      thing.cooldown = 15
      env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
      env.updateObservations(AgentInventoryLanternLayer, agent.pos, agent.inventoryLantern)
      agent.reward += env.config.clothReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of Armory:
    if thing.cooldown == 0 and agent.inventoryWood > 0 and agent.inventoryArmor == 0:
      agent.inventoryWood -= 1
      agent.inventoryArmor = ArmorPoints
      thing.cooldown = 20
      env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
      env.updateObservations(AgentInventoryArmorLayer, agent.pos, agent.inventoryArmor)
      agent.reward += env.config.armorReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of ClayOven:
    if thing.cooldown == 0 and agent.inventoryWheat > 0:
      agent.inventoryWheat -= 1
      agent.inventoryBread += 1
      thing.cooldown = 10
      env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
      env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
      # No observation layer for bread; optional for UI later
      agent.reward += env.config.foodReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
  of assembler:
    if thing.cooldown == 0 and agent.inventoryBattery >= 1:
      agent.inventoryBattery -= 1
      env.updateObservations(AgentInventoryBatteryLayer, agent.pos, agent.inventoryBattery)
      thing.hearts += 1
      thing.cooldown = MapObjectassemblerCooldown
      env.updateObservations(assemblerHeartsLayer, thing.pos, thing.hearts)
      env.updateObservations(assemblerReadyLayer, thing.pos, thing.cooldown)
      agent.reward += env.config.heartReward
      inc env.stats[id].actionUse
    else:
      inc env.stats[id].actionInvalid
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
  if isNil(target) or target.kind != Agent or isThingFrozen(target, env):
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
    agent.inventoryBread -= giveAmt
    target.inventoryBread += giveAmt
    transferred = true
  if transferred:
    inc env.stats[id].actionPut
    # Update observations for changed inventories
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, agent.inventoryArmor)
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)
    env.updateObservations(AgentInventoryArmorLayer, target.pos, target.inventoryArmor)
    env.updateObservations(AgentInventoryBreadLayer, target.pos, target.inventoryBread)
  else:
    inc env.stats[id].actionInvalid
# ============== CLIPPY AI ==============




{.push inline.}
proc isValidEmptyPosition(env: Environment, pos: IVec2): bool =
  ## Check if a position is within map bounds, empty, and not water
  pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
  pos.y >= MapBorder and pos.y < MapHeight - MapBorder and
  env.isEmpty(pos) and not env.hasDoor(pos) and env.terrain[pos.x][pos.y] != Water

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

  # Check if agent has a lantern
  if agent.inventoryLantern <= 0:
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
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or env.terrain[targetPos.x][targetPos.y] == Water or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

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
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or env.terrain[targetPos.x][targetPos.y] == Water or isTileFrozen(targetPos, env):
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
    env.terrain[targetPos.x][targetPos.y] = Tree
    env.tileColors[targetPos.x][targetPos.y] = BaseTileColorDefault
    env.baseTileColors[targetPos.x][targetPos.y] = BaseTileColorDefault
  else:
    if agent.inventoryWheat <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
    env.terrain[targetPos.x][targetPos.y] = Wheat
    env.tileColors[targetPos.x][targetPos.y] = BaseTileColorDefault
    env.baseTileColors[targetPos.x][targetPos.y] = BaseTileColorDefault

  # Consuming fertility (terrain replaced above)
  inc env.stats[id].actionPlantResource

