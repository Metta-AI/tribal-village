proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  if victim.frozen >= 999999:
    return
  let deathPos = victim.pos
  env.grid[deathPos.x][deathPos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)
  env.updateObservations(AgentInventoryOreLayer, victim.pos, 0)
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
  victim.frozen = 999999
  victim.hp = 0
  victim.reward += env.config.deathPenalty
  var hasItems = false
  for key, count in victim.inventory.pairs:
    if count > 0:
      hasItems = true
      break
  if hasItems and isValidPos(deathPos):
    var dropInv = emptyInventory()
    for key, count in victim.inventory.pairs:
      if count > 0:
        dropInv[key] = count
    let skeleton = Thing(kind: Skeleton, pos: deathPos)
    skeleton.inventory = dropInv
    env.add(skeleton)

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

  proc claimAltar(altarThing: Thing) =
    let oldTeam = altarThing.teamId
    altarThing.teamId = attackerTeam
    if attackerTeam >= 0 and attackerTeam < teamColors.len:
      altarColors[altarThing.pos] = teamColors[attackerTeam]
    if oldTeam >= 0:
      for x in 0 ..< MapWidth:
        for y in 0 ..< MapHeight:
          if env.doorTeams[x][y] == oldTeam.int16:
            env.doorTeams[x][y] = attackerTeam.int16

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
        if getTeamId(target.agentId) == attackerTeam:
          continue
        discard env.applyAgentDamage(target, damageAmount, agent)
        attackHit = true
      of Altar:
        if target.teamId == attackerTeam:
          continue
        target.hearts = max(0, target.hearts - 1)
        env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
        attackHit = true
        if target.hearts == 0:
          claimAltar(target)
      else:
        discard
      if attackHit:
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
        discard env.applyAgentDamage(target, damageAmount, agent)
        hit = true
      of Altar:
        if target.teamId == attackerTeam:
          return
        target.hearts = max(0, target.hearts - 1)
        env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
        hit = true
        if target.hearts == 0:
          claimAltar(target)
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
      discard env.applyAgentDamage(target, damageAmount, agent)
      attackHit = true
    of Altar:
      if target.teamId == attackerTeam:
        continue
      target.hearts = max(0, target.hearts - 1)
      env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
      attackHit = true
      if target.hearts == 0:
        claimAltar(target)
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

