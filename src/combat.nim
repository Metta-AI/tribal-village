const BonusDamageByClass: array[AgentUnitClass, array[AgentUnitClass, int]] = [
  # Attacker: UnitVillager
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitManAtArms (infantry > cavalry)
  [0, 0, 0, 1, 1, 0, 0, 0, 0],
  # Attacker: UnitArcher (archer > infantry)
  [0, 1, 0, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitScout (cavalry > archer)
  [0, 0, 1, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitKnight (cavalry > archer)
  [0, 0, 1, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitMonk
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitBatteringRam
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitMangonel
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  # Attacker: UnitBoat
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
]

const BonusDamageTintByClass: array[AgentUnitClass, TileColor] = [
  # UnitVillager
  TileColor(r: 1.00, g: 0.35, b: 0.30, intensity: 1.20),
  # UnitManAtArms
  TileColor(r: 1.00, g: 0.65, b: 0.20, intensity: 1.20),
  # UnitArcher
  TileColor(r: 1.00, g: 0.90, b: 0.25, intensity: 1.20),
  # UnitScout
  TileColor(r: 0.30, g: 1.00, b: 0.35, intensity: 1.18),
  # UnitKnight
  TileColor(r: 0.25, g: 0.95, b: 0.90, intensity: 1.18),
  # UnitMonk
  TileColor(r: 0.30, g: 0.60, b: 1.00, intensity: 1.18),
  # UnitBatteringRam
  TileColor(r: 0.55, g: 0.40, b: 1.00, intensity: 1.18),
  # UnitMangonel
  TileColor(r: 0.85, g: 0.40, b: 1.00, intensity: 1.20),
  # UnitBoat
  TileColor(r: 1.00, g: 0.40, b: 0.80, intensity: 1.18),
]

proc classBonusDamage(attacker, target: AgentUnitClass): int {.inline.} =
  BonusDamageByClass[attacker][target]

proc bonusCritTint(attacker: AgentUnitClass): TileColor {.inline.} =
  BonusDamageTintByClass[attacker]

proc inTankAura(env: Environment, target: Thing): bool =
  let teamId = getTeamId(target)
  if teamId < 0:
    return false
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if getTeamId(agent) != teamId:
      continue
    if agent.unitClass notin {UnitManAtArms, UnitKnight}:
      continue
    if isThingFrozen(agent, env):
      continue
    let radius = if agent.unitClass == UnitKnight: 2 else: 1
    let dx = abs(agent.pos.x - target.pos.x)
    let dy = abs(agent.pos.y - target.pos.y)
    if max(dx, dy) <= radius:
      return true
  return false

proc isAttackableStructure*(kind: ThingKind): bool {.inline.} =
  kind in {Wall, Door, Outpost, GuardTower, Castle, TownCenter}

proc applyStructureDamage*(env: Environment, target: Thing, amount: int,
                           attacker: Thing = nil): bool =
  var damage = max(1, amount)
  if not attacker.isNil and attacker.unitClass in {UnitBatteringRam, UnitMangonel}:
    let bonus = damage * (SiegeStructureMultiplier - 1)
    if bonus > 0:
      env.applyActionTint(target.pos, bonusCritTint(attacker.unitClass), 2, ActionTintAttackBonus)
      damage += bonus
  target.hp = max(0, target.hp - damage)
  if target.hp > 0:
    return false
  if target.kind == Wall:
    updateThingObs(env, target.kind, target.pos, false)
  removeThing(env, target)
  true

proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  let deathPos = victim.pos
  env.grid[deathPos.x][deathPos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)

  env.terminated[victim.agentId] = 1.0
  victim.hp = 0
  victim.reward += env.config.deathPenalty
  let lanternCount = getInv(victim, ItemLantern)
  let relicCount = getInv(victim, ItemRelic)
  if lanternCount > 0:
    setInv(victim, ItemLantern, 0)
  if relicCount > 0:
    setInv(victim, ItemRelic, 0)
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

  if lanternCount > 0 or relicCount > 0:
    var candidates: seq[IVec2] = @[]
    for dy in -1 .. 1:
      for dx in -1 .. 1:
        if dx == 0 and dy == 0:
          continue
        let cand = deathPos + ivec2(dx.int32, dy.int32)
        if not isValidPos(cand):
          continue
        if env.isEmpty(cand) and not env.hasDoor(cand) and
            not isBlockedTerrain(env.terrain[cand.x][cand.y]) and not isTileFrozen(cand, env):
          candidates.add(cand)
    var idx = 0
    for _ in 0 ..< lanternCount:
      if idx >= candidates.len:
        break
      let pos = candidates[idx]
      inc idx
      let lantern = Thing(kind: Lantern, pos: pos, teamId: getTeamId(victim), lanternHealthy: true)
      env.add(lantern)
    for _ in 0 ..< relicCount:
      if idx >= candidates.len:
        break
      let pos = candidates[idx]
      inc idx
      let relic = Thing(kind: Relic, pos: pos)
      relic.inventory = emptyInventory()
      setInv(relic, ItemGold, 0)
      env.add(relic)

  victim.inventory = emptyInventory()
  for key in ObservedItemKeys:
    env.updateAgentInventoryObs(victim, key)
  victim.pos = ivec2(-1, -1)

# Apply damage to an agent; respects armor and marks terminated when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  var remaining = max(1, amount)
  if not attacker.isNil:
    let bonus = classBonusDamage(attacker.unitClass, target.unitClass)
    if bonus > 0:
      env.applyActionTint(target.pos, bonusCritTint(attacker.unitClass), 2, ActionTintAttackBonus)
    remaining = max(1, remaining + bonus)
  if inTankAura(env, target):
    remaining = max(1, (remaining + 1) div 2)
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

# Centralized zero-HP handling so agents instantly freeze/die when drained
proc enforceZeroHpDeaths(env: Environment) =
  for agent in env.agents:
    if env.terminated[agent.agentId] == 0.0 and agent.hp <= 0:
      env.killAgent(agent)
