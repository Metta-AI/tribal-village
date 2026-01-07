proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  let deathPos = victim.pos
  env.grid[deathPos.x][deathPos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryGoldLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryStoneLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryBarLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWaterLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWheatLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryWoodLayer, victim.pos, 0)
  env.updateObservations(AgentInventorySpearLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryLanternLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryArmorLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryBreadLayer, victim.pos, 0)

  env.terminated[victim.agentId] = 1.0
  victim.hp = 0
  victim.reward += env.config.deathPenalty
  var dropInv = emptyInventory()
  var hasItems = false
  for key, count in victim.inventory.pairs:
    if count > 0:
      dropInv[key] = count
      hasItems = true
  let corpseKind = if hasItems: Corpse else: Skeleton
  let corpse = Thing(kind: corpseKind, pos: deathPos)
  corpse.inventory = dropInv
  env.add(corpse)

  victim.inventory = emptyInventory()
  victim.pos = ivec2(-1, -1)

# Apply damage to an agent; respects armor and marks terminated when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  var remaining = amount
  if target.inventoryArmor > 0:
    let absorbed = min(remaining, target.inventoryArmor)
    target.inventoryArmor = max(0, target.inventoryArmor - absorbed)
    remaining -= absorbed
    env.updateObservations(AgentInventoryArmorLayer, target.pos, target.inventoryArmor)

  if remaining > 0:
    target.hp = max(0, target.hp - remaining)

  if target.hp <= 0:
    env.killAgent(target)
    return true

  return false

# Heal an agent up to its max HP. Returns the amount actually healed.
proc applyAgentHeal(env: Environment, target: Thing, amount: int): int =
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
    if env.terminated[agent.agentId] == 0.0 and agent.hp <= 0:
      env.killAgent(agent)

proc attackAction(env: Environment, id: int, agent: Thing) =
  ## Attack an entity in facing direction. Spears extend range to 2 tiles.
  let attackOrientation = agent.orientation
  let delta = getOrientationDelta(attackOrientation)
  let attackerTeam = getTeamId(agent.agentId)
  let baseDamage = agent.attackDamage
  let damageAmount = max(1, baseDamage)
  let rangedRange = case agent.unitClass
    of UnitArcher: ArcherBaseRange
    of UnitSiege: SiegeBaseRange
    else: 0
  let hasSpear = agent.inventorySpear > 0 and rangedRange == 0
  let maxRange = if hasSpear: 2 else: 1

  proc tryDamageDoor(pos: IVec2): bool =
    let door = env.getOverlayThing(pos)
    if isNil(door) or door.kind != Door:
      return false
    if door.teamId == attackerTeam:
      return false
    door.hp = max(0, door.hp - 1)
    if door.hp <= 0:
      removeThing(env, door)
    return true

  proc claimAltar(altarThing: Thing) =
    let oldTeam = altarThing.teamId
    altarThing.teamId = attackerTeam
    if attackerTeam >= 0 and attackerTeam < env.teamColors.len:
      env.altarColors[altarThing.pos] = env.teamColors[attackerTeam]
    if oldTeam >= 0:
      for door in env.thingsByKind[Door]:
        if door.teamId == oldTeam:
          door.teamId = attackerTeam
  
  proc spawnCorpseAt(pos: IVec2, key: ItemKey, amount: int) =
    let remaining = amount
    if remaining <= 0:
      return
    let corpse = Thing(kind: Corpse, pos: pos)
    corpse.inventory = emptyInventory()
    setInv(corpse, key, remaining)
    env.add(corpse)

  proc tryHitAt(pos: IVec2): bool =
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      return false
    if tryDamageDoor(pos):
      return true
    let target = env.getThing(pos)
    if isNil(target):
      return false
    case target.kind
    of Tumor:
      env.grid[pos.x][pos.y] = nil
      env.updateObservations(AgentLayer, pos, 0)
      env.updateObservations(AgentOrientationLayer, pos, 0)
      removeThing(env, target)
      agent.reward += env.config.tumorKillReward
      return true
    of Spawner:
      env.grid[pos.x][pos.y] = nil
      removeThing(env, target)
      return true
    of Agent:
      if target.agentId == agent.agentId:
        return false
      if getTeamId(target.agentId) == attackerTeam:
        return false
      discard env.applyAgentDamage(target, damageAmount, agent)
      return true
    of Altar:
      if target.teamId == attackerTeam:
        return false
      target.hearts = max(0, target.hearts - 1)
      env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
      if target.hearts == 0:
        claimAltar(target)
      return true
    of Cow:
      setInv(agent, ItemMeat, getInv(agent, ItemMeat) + 1)
      env.updateAgentInventoryObs(agent, ItemMeat)
      removeThing(env, target)
      spawnCorpseAt(pos, ItemMeat, ResourceNodeInitial - 1)
      return true
    of Pine, Palm:
      env.harvestTree(agent, target)
      return true
    else:
      return false

  if agent.unitClass == UnitMonk:
    let healPos = agent.pos + ivec2(delta.x, delta.y)
    let target = env.getThing(healPos)
    if not isNil(target) and target.kind == Agent and getTeamId(target.agentId) == attackerTeam:
      discard env.applyAgentHeal(target, 1)
      env.applyActionTint(healPos, TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1), 2, ActionTintHeal)
      inc env.stats[id].actionAttack
    else:
      inc env.stats[id].actionInvalid
    return

  if rangedRange > 0:
    var attackHit = false
    for distance in 1 .. rangedRange:
      let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
      if tryHitAt(attackPos):
        attackHit = true
        break
    if attackHit:
      inc env.stats[id].actionAttack
    else:
      inc env.stats[id].actionInvalid
    return

  # Special combat visuals
  if hasSpear:
    env.applySpearStrike(agent, attackOrientation)
  if agent.inventoryArmor > 0:
    env.applyShieldBand(agent, attackOrientation)
    env.shieldCountdown[agent.agentId] = 2

  # Spear: area strike (3 forward + diagonals)
  if hasSpear:
    var hit = false
    let left = ivec2(-delta.y, delta.x)
    let right = ivec2(delta.y, -delta.x)
    for step in 1 .. 3:
      let forward = agent.pos + ivec2(delta.x * step, delta.y * step)
      if tryHitAt(forward):
        hit = true
      # Keep spear width contiguous (no skipping): lateral offset is fixed 1 tile.
      if tryHitAt(forward + left):
        hit = true
      if tryHitAt(forward + right):
        hit = true

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
    if tryHitAt(attackPos):
      attackHit = true
      break

  if attackHit:
    if hasSpear:
      agent.inventorySpear = max(0, agent.inventorySpear - 1)
      env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
    inc env.stats[id].actionAttack
  else:
    inc env.stats[id].actionInvalid
