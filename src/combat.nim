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

const BonusDamageTint = TileColor(r: 1.0, g: 0.45, b: 0.15, intensity: 1.15)

proc classBonusDamage(attacker, target: AgentUnitClass): int {.inline.} =
  BonusDamageByClass[attacker][target]

proc isAttackableStructure*(kind: ThingKind): bool {.inline.} =
  kind in {Wall, Door, Outpost, GuardTower, Castle, TownCenter}

proc applyStructureDamage*(env: Environment, target: Thing, amount: int,
                           attacker: Thing = nil): bool =
  var damage = max(1, amount)
  if not attacker.isNil and attacker.unitClass in {UnitBatteringRam, UnitMangonel}:
    let bonus = damage * (SiegeStructureMultiplier - 1)
    if bonus > 0:
      env.applyActionTint(target.pos, BonusDamageTint, 2, ActionTintAttack)
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
  for key in ObservedItemKeys:
    env.updateAgentInventoryObs(victim, key)
  victim.pos = ivec2(-1, -1)

# Apply damage to an agent; respects armor and marks terminated when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  var remaining = amount
  if not attacker.isNil:
    let bonus = classBonusDamage(attacker.unitClass, target.unitClass)
    if bonus > 0:
      env.applyActionTint(target.pos, BonusDamageTint, 2, ActionTintAttack)
    remaining += bonus
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
