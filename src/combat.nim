const BonusDamageByClass: array[AgentUnitClass, array[AgentUnitClass, int]] = block:
  var table: array[AgentUnitClass, array[AgentUnitClass, int]]
  for (attacker, target, value) in [
    # Infantry > cavalry
    (UnitManAtArms, UnitScout, 1),
    (UnitManAtArms, UnitKnight, 1),
    # Archer > infantry
    (UnitArcher, UnitManAtArms, 1),
    # Cavalry > archer
    (UnitScout, UnitArcher, 1),
    (UnitKnight, UnitArcher, 1)
  ]:
    table[attacker][target] = value
  table

const BonusDamageTintByClass: array[AgentUnitClass, TileColor] = [
  # UnitVillager
  TileColor(r: 1.00, g: 0.35, b: 0.30, intensity: 1.20),
  # UnitManAtArms (infantry counter - orange)
  TileColor(r: 1.00, g: 0.65, b: 0.20, intensity: 1.20),
  # UnitArcher (archer counter - yellow)
  TileColor(r: 1.00, g: 0.90, b: 0.25, intensity: 1.20),
  # UnitScout (cavalry counter - green)
  TileColor(r: 0.30, g: 1.00, b: 0.35, intensity: 1.18),
  # UnitKnight (cavalry counter - cyan)
  TileColor(r: 0.25, g: 0.95, b: 0.90, intensity: 1.18),
  # UnitMonk
  TileColor(r: 0.30, g: 0.60, b: 1.00, intensity: 1.18),
  # UnitBatteringRam (siege - stronger purple, higher intensity)
  TileColor(r: 0.55, g: 0.40, b: 1.00, intensity: 1.40),
  # UnitMangonel (siege - stronger pink-purple, higher intensity)
  TileColor(r: 0.85, g: 0.40, b: 1.00, intensity: 1.40),
  # UnitTrebuchet (siege - deep purple, highest intensity)
  TileColor(r: 0.70, g: 0.25, b: 1.00, intensity: 1.45),
  # UnitGoblin
  TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.18),
  # UnitBoat
  TileColor(r: 1.00, g: 0.40, b: 0.80, intensity: 1.18),
  # Castle unique units
  # UnitSamurai
  TileColor(r: 0.95, g: 0.40, b: 0.25, intensity: 1.22),
  # UnitLongbowman
  TileColor(r: 0.70, g: 0.90, b: 0.25, intensity: 1.20),
  # UnitCataphract
  TileColor(r: 0.85, g: 0.70, b: 0.30, intensity: 1.22),
  # UnitWoadRaider
  TileColor(r: 0.30, g: 0.60, b: 0.85, intensity: 1.20),
  # UnitTeutonicKnight
  TileColor(r: 0.60, g: 0.65, b: 0.70, intensity: 1.25),
  # UnitHuskarl
  TileColor(r: 0.55, g: 0.40, b: 0.80, intensity: 1.20),
  # UnitMameluke
  TileColor(r: 0.90, g: 0.80, b: 0.50, intensity: 1.20),
  # UnitJanissary
  TileColor(r: 0.90, g: 0.30, b: 0.35, intensity: 1.22),
]

# Action tint codes for per-unit bonus damage
# Maps attacker unit class to the appropriate observation code
const BonusTintCodeByClass: array[AgentUnitClass, uint8] = [
  # UnitVillager - no counter bonus
  ActionTintAttackBonus,
  # UnitManAtArms - infantry counter (beats cavalry)
  ActionTintBonusInfantry,
  # UnitArcher - archer counter (beats infantry)
  ActionTintBonusArcher,
  # UnitScout - scout counter (beats archers)
  ActionTintBonusScout,
  # UnitKnight - knight counter (beats archers)
  ActionTintBonusKnight,
  # UnitMonk - no counter bonus
  ActionTintAttackBonus,
  # UnitBatteringRam - battering ram siege bonus (beats structures)
  ActionTintBonusBatteringRam,
  # UnitMangonel - mangonel siege bonus (beats structures)
  ActionTintBonusMangonel,
  # UnitTrebuchet - trebuchet siege bonus (beats structures)
  ActionTintBonusTrebuchet,
  # UnitGoblin - no counter bonus
  ActionTintAttackBonus,
  # UnitBoat - no counter bonus
  ActionTintAttackBonus,
  # Castle unique units - generic bonus tint
  ActionTintAttackBonus,  # UnitSamurai
  ActionTintAttackBonus,  # UnitLongbowman
  ActionTintAttackBonus,  # UnitCataphract
  ActionTintAttackBonus,  # UnitWoadRaider
  ActionTintAttackBonus,  # UnitTeutonicKnight
  ActionTintAttackBonus,  # UnitHuskarl
  ActionTintAttackBonus,  # UnitMameluke
  ActionTintAttackBonus,  # UnitJanissary
]

const AttackableStructures* = {Wall, Door, Outpost, GuardTower, Castle, TownCenter}

proc applyStructureDamage*(env: Environment, target: Thing, amount: int,
                           attacker: Thing = nil): bool =
  ## Apply damage to a structure (Wall, Tower, Castle, etc).
  ## University techs affect structure combat:
  ## - Masonry: +1/+1 building armor (reduces damage by 1)
  ## - Architecture: +1/+1 building armor (stacks with Masonry, reduces by 1 more)
  ## - Siege Engineers: +20% building damage for siege units
  var damage = max(1, amount)
  if not attacker.isNil and attacker.unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet}:
    let bonusMultiplier = SiegeStructureMultiplier - 1
    let bonus = damage * bonusMultiplier
    if bonus > 0:
      env.applyActionTint(target.pos, BonusDamageTintByClass[attacker.unitClass], 2, BonusTintCodeByClass[attacker.unitClass])
      damage += bonus
    # Siege Engineers: +20% building damage for siege units (applied to total damage)
    let attackerTeam = getTeamId(attacker)
    if attackerTeam >= 0 and env.hasUniversityTech(attackerTeam, TechSiegeEngineers):
      damage = int(float32(damage) * 1.2 + 0.5)

  # Apply building armor from Masonry and Architecture (defender's team)
  if target.teamId >= 0:
    var armorReduction = 0
    # Masonry: +1 building armor
    if env.hasUniversityTech(target.teamId, TechMasonry):
      armorReduction += 1
    # Architecture: +1 building armor (stacks with Masonry)
    if env.hasUniversityTech(target.teamId, TechArchitecture):
      armorReduction += 1
    damage = max(1, damage - armorReduction)

  target.hp = max(0, target.hp - damage)
  if target.hp > 0:
    return false
  if target.kind == Wall:
    if isValidPos(target.pos):
      env.updateObservations(ThingAgentLayer, target.pos, 0)
  # Eject garrisoned units when building is destroyed
  if target.kind in {TownCenter, Castle} and target.garrisonedUnits.len > 0:
    # Find empty tiles around the building to eject units
    let buildingPos = target.pos
    var emptyTiles: seq[IVec2] = @[]
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if dx == 0 and dy == 0:
          continue
        let pos = buildingPos + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        if not env.isEmpty(pos):
          continue
        if env.terrain[pos.x][pos.y] == Water:
          continue
        emptyTiles.add(pos)
    var tileIdx = 0
    for unit in target.garrisonedUnits:
      if tileIdx >= emptyTiles.len:
        # No space - unit dies
        env.terminated[unit.agentId] = 1.0
        unit.hp = 0
        unit.pos = ivec2(-1, -1)
      else:
        let pos = emptyTiles[tileIdx]
        unit.pos = pos
        env.grid[pos.x][pos.y] = unit
        env.updateObservations(AgentLayer, pos, getTeamId(unit) + 1)
        env.updateObservations(AgentOrientationLayer, pos, unit.orientation.int)
        inc tileIdx
    target.garrisonedUnits.setLen(0)
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
  for key, count in victim.inventory.pairs:
    dropInv[key] = count
  let corpse = Thing(kind: (if dropInv.len > 0: Corpse else: Skeleton), pos: deathPos)
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
    let lanternSlots = min(lanternCount, candidates.len)
    for i in 0 ..< lanternSlots:
      let lantern = Thing(
        kind: Lantern,
        pos: candidates[i],
        teamId: getTeamId(victim),
        lanternHealthy: true
      )
      env.add(lantern)
    let relicSlots = min(relicCount, candidates.len - lanternSlots)
    for i in 0 ..< relicSlots:
      let relic = Thing(kind: Relic, pos: candidates[lanternSlots + i])
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

  # Apply Blacksmith attack upgrade bonus from attacker
  if not attacker.isNil:
    let attackerTeamId = getTeamId(attacker)
    if attackerTeamId >= 0 and attackerTeamId < MapRoomObjectsTeams:
      let attackBonus = env.getBlacksmithAttackBonus(attackerTeamId, attacker.unitClass)
      remaining += attackBonus

  let bonus = if attacker.isNil: 0 else: BonusDamageByClass[attacker.unitClass][target.unitClass]
  if bonus > 0:
    env.applyActionTint(target.pos, BonusDamageTintByClass[attacker.unitClass], 2, BonusTintCodeByClass[attacker.unitClass])
    remaining = max(1, remaining + bonus)
  let teamId = getTeamId(target)
  if teamId >= 0:
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
        remaining = max(1, (remaining + 1) div 2)
        break

  # Apply Blacksmith armor upgrade bonus for defender
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    let armorBonus = env.getBlacksmithArmorBonus(teamId, target.unitClass)
    remaining = max(0, remaining - armorBonus)

  if target.inventoryArmor > 0:
    let absorbed = min(remaining, target.inventoryArmor)
    target.inventoryArmor = max(0, target.inventoryArmor - absorbed)
    remaining -= absorbed

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
