const BonusDamageByClass*: array[AgentUnitClass, array[AgentUnitClass, int]] = block:
  var table: array[AgentUnitClass, array[AgentUnitClass, int]]
  for (attacker, target, value) in [
    # Infantry > cavalry (rock-paper-scissors core)
    (UnitManAtArms, UnitScout, 1),
    (UnitManAtArms, UnitKnight, 1),
    (UnitManAtArms, UnitLightCavalry, 1),
    (UnitManAtArms, UnitHussar, 1),
    # Archer > infantry
    (UnitArcher, UnitManAtArms, 1),
    (UnitArcher, UnitLongSwordsman, 1),
    (UnitArcher, UnitChampion, 1),
    # Cavalry > archer
    (UnitScout, UnitArcher, 1),
    (UnitScout, UnitCrossbowman, 1),
    (UnitScout, UnitArbalester, 1),
    (UnitKnight, UnitArcher, 1),
    (UnitKnight, UnitCrossbowman, 1),
    (UnitKnight, UnitArbalester, 1),

    # Upgrade tiers inherit counter relationships from base units
    # Long Swordsman/Champion (infantry upgrades) > cavalry
    (UnitLongSwordsman, UnitScout, 1),
    (UnitLongSwordsman, UnitKnight, 1),
    (UnitLongSwordsman, UnitLightCavalry, 1),
    (UnitLongSwordsman, UnitHussar, 1),
    (UnitChampion, UnitScout, 2),  # Champion gets stronger counter bonus
    (UnitChampion, UnitKnight, 2),
    (UnitChampion, UnitLightCavalry, 2),
    (UnitChampion, UnitHussar, 2),

    # Crossbowman/Arbalester (archer upgrades) > infantry
    (UnitCrossbowman, UnitManAtArms, 1),
    (UnitCrossbowman, UnitLongSwordsman, 1),
    (UnitCrossbowman, UnitChampion, 1),
    (UnitArbalester, UnitManAtArms, 2),  # Arbalester gets stronger counter bonus
    (UnitArbalester, UnitLongSwordsman, 2),
    (UnitArbalester, UnitChampion, 2),

    # Light Cavalry/Hussar (cavalry upgrades) > archer
    (UnitLightCavalry, UnitArcher, 1),
    (UnitLightCavalry, UnitCrossbowman, 1),
    (UnitLightCavalry, UnitArbalester, 1),
    (UnitHussar, UnitArcher, 2),  # Hussar gets stronger counter bonus
    (UnitHussar, UnitCrossbowman, 2),
    (UnitHussar, UnitArbalester, 2),

    # Castle unique units - specialized counters
    # Samurai (fast infantry) > other infantry
    (UnitSamurai, UnitManAtArms, 1),
    (UnitSamurai, UnitLongSwordsman, 1),
    # Cataphract (heavy cavalry) > infantry
    (UnitCataphract, UnitManAtArms, 1),
    (UnitCataphract, UnitLongSwordsman, 1),
    # Huskarl (anti-archer) > archers
    (UnitHuskarl, UnitArcher, 2),
    (UnitHuskarl, UnitCrossbowman, 2),
    (UnitHuskarl, UnitArbalester, 2),
    (UnitHuskarl, UnitLongbowman, 2),

    # Fire Ship (anti-ship) > water units
    (UnitFireShip, UnitBoat, 2),
    (UnitFireShip, UnitTradeCog, 2),
    (UnitFireShip, UnitGalley, 2),
    (UnitFireShip, UnitFireShip, 1),  # Less effective vs other fire ships

    # Scorpion (anti-infantry) > infantry
    (UnitScorpion, UnitManAtArms, 2),
    (UnitScorpion, UnitLongSwordsman, 2),
    (UnitScorpion, UnitChampion, 2),
    (UnitScorpion, UnitSamurai, 2),
    (UnitScorpion, UnitWoadRaider, 2),
    (UnitScorpion, UnitTeutonicKnight, 2),
    (UnitScorpion, UnitHuskarl, 2)
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
  # UnitTradeCog
  TileColor(r: 1.00, g: 0.85, b: 0.30, intensity: 1.10),
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
  # UnitKing
  TileColor(r: 0.95, g: 0.80, b: 0.20, intensity: 1.25),
  # Unit upgrade tiers (same tint family as base unit)
  # UnitLongSwordsman (infantry - orange)
  TileColor(r: 1.00, g: 0.65, b: 0.20, intensity: 1.25),
  # UnitChampion (infantry - orange, stronger)
  TileColor(r: 1.00, g: 0.65, b: 0.20, intensity: 1.30),
  # UnitLightCavalry (cavalry - green)
  TileColor(r: 0.30, g: 1.00, b: 0.35, intensity: 1.22),
  # UnitHussar (cavalry - green, stronger)
  TileColor(r: 0.30, g: 1.00, b: 0.35, intensity: 1.28),
  # UnitCrossbowman (archer - yellow)
  TileColor(r: 1.00, g: 0.90, b: 0.25, intensity: 1.25),
  # UnitArbalester (archer - yellow, stronger)
  TileColor(r: 1.00, g: 0.90, b: 0.25, intensity: 1.30),
  # Naval combat units
  # UnitGalley (naval - blue)
  TileColor(r: 0.30, g: 0.50, b: 0.95, intensity: 1.25),
  # UnitFireShip (naval fire - orange-red)
  TileColor(r: 1.00, g: 0.50, b: 0.20, intensity: 1.35),
  # UnitScorpion (siege - cyan-purple)
  TileColor(r: 0.60, g: 0.50, b: 0.90, intensity: 1.35),
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
  # UnitTradeCog - no counter bonus
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
  ActionTintAttackBonus,  # UnitKing
  # Unit upgrade tiers (same counter as base unit)
  ActionTintBonusInfantry,  # UnitLongSwordsman
  ActionTintBonusInfantry,  # UnitChampion
  ActionTintBonusScout,     # UnitLightCavalry
  ActionTintBonusScout,     # UnitHussar
  ActionTintBonusArcher,    # UnitCrossbowman
  ActionTintBonusArcher,    # UnitArbalester
  # Naval combat units
  ActionTintAttackBonus,    # UnitGalley - ranged naval
  ActionTintAttackBonus,    # UnitFireShip - anti-ship
  # Additional siege unit
  ActionTintAttackBonus,    # UnitScorpion - anti-infantry siege
]

# Death animation tint: dark red flash at kill location
const DeathTint = TileColor(r: 0.80, g: 0.15, b: 0.15, intensity: 1.20)

const AttackableStructures* = {Wall, Door, Outpost, GuardTower, Castle, TownCenter, Monastery}

proc applyStructureDamage*(env: Environment, target: Thing, amount: int,
                           attacker: Thing = nil): bool =
  ## Apply damage to a structure (Wall, Tower, Castle, etc).
  ## University techs affect structure combat:
  ## - Masonry: +1/+1 building armor (reduces damage by 1)
  ## - Architecture: +1/+1 building armor (stacks with Masonry, reduces by 1 more)
  ## - Siege Engineers: +20% building damage for siege units
  var damage = max(1, amount)
  if not attacker.isNil and attacker.unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet}:
    env.applyActionTint(target.pos, BonusDamageTintByClass[attacker.unitClass], 2, BonusTintCodeByClass[attacker.unitClass])
    damage *= SiegeStructureMultiplier
    # Siege Engineers: +20% building damage for siege units
    let attackerTeam = getTeamId(attacker)
    if attackerTeam >= 0 and env.hasUniversityTech(attackerTeam, TechSiegeEngineers):
      damage = (damage * 6 + 2) div 5  # +20% with rounding, no float

  # Apply building armor from Masonry and Architecture (defender's team)
  if target.teamId >= 0:
    let armorReduction = ord(env.hasUniversityTech(target.teamId, TechMasonry)) +
                         ord(env.hasUniversityTech(target.teamId, TechArchitecture))
    if armorReduction > 0:
      damage = max(1, damage - armorReduction)

  target.hp = max(0, target.hp - damage)
  # Spawn floating damage number for structure damage feedback
  let isSiege = not attacker.isNil and attacker.unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet}
  env.spawnDamageNumber(target.pos, damage, if isSiege: DmgNumCritical else: DmgNumDamage)
  when defined(combatAudit):
    if not attacker.isNil:
      let aTeam = getTeamId(attacker)
      recordSiegeDamage(env.currentStep, aTeam, $target.kind,
                        target.teamId, damage, $attacker.unitClass,
                        target.hp <= 0)
  if target.hp > 0:
    return false

  when defined(eventLog):
    logBuildingDestroyed(target.teamId, $target.kind,
                         "(" & $target.pos.x & "," & $target.pos.y & ")", env.currentStep)

  if target.kind == Wall:
    if isValidPos(target.pos):
      env.updateObservations(ThingAgentLayer, target.pos, 0)
  # Eject garrisoned units when building is destroyed
  if target.kind in {TownCenter, Castle, GuardTower, House} and target.garrisonedUnits.len > 0:
    var emptyTiles: seq[IVec2] = @[]
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if dx == 0 and dy == 0: continue
        let pos = target.pos + ivec2(dx.int32, dy.int32)
        if isValidPos(pos) and env.isEmpty(pos) and env.terrain[pos.x][pos.y] != Water:
          emptyTiles.add(pos)
    var tileIdx = 0
    for unit in target.garrisonedUnits:
      if tileIdx >= emptyTiles.len:
        env.terminated[unit.agentId] = 1.0
        unit.hp = 0
        unit.pos = ivec2(-1, -1)
      else:
        unit.pos = emptyTiles[tileIdx]
        env.grid[unit.pos.x][unit.pos.y] = unit
        env.updateObservations(AgentLayer, unit.pos, getTeamId(unit) + 1)
        env.updateObservations(AgentOrientationLayer, unit.pos, unit.orientation.int)
        inc tileIdx
    target.garrisonedUnits.setLen(0)
  # Drop garrisoned relics when a Monastery is destroyed
  if target.kind == Monastery and target.garrisonedRelics > 0:
    var bgCandidates: seq[IVec2] = @[]
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if dx == 0 and dy == 0: continue
        let pos = target.pos + ivec2(dx.int32, dy.int32)
        if isValidPos(pos) and env.terrain[pos.x][pos.y] != Water and
            isNil(env.backgroundGrid[pos.x][pos.y]):
          bgCandidates.add(pos)
    for i in 0 ..< min(target.garrisonedRelics, bgCandidates.len):
      let relic = Thing(kind: Relic, pos: bgCandidates[i])
      relic.inventory = emptyInventory()
      env.add(relic)
    target.garrisonedRelics = 0
  removeThing(env, target)
  true

proc killAgent(env: Environment, victim: Thing) =
  ## Remove an agent from the board and mark for respawn
  let deathPos = victim.pos
  env.grid[deathPos.x][deathPos.y] = nil
  env.updateObservations(AgentLayer, victim.pos, 0)
  env.updateObservations(AgentOrientationLayer, victim.pos, 0)

  # Remove from aura unit collections (swap-and-pop for O(1))
  if victim.unitClass in {UnitManAtArms, UnitKnight}:
    for i in 0 ..< env.tankUnits.len:
      if env.tankUnits[i] == victim:
        env.tankUnits[i] = env.tankUnits[^1]
        env.tankUnits.setLen(env.tankUnits.len - 1)
        break
  elif victim.unitClass == UnitMonk:
    for i in 0 ..< env.monkUnits.len:
      if env.monkUnits[i] == victim:
        env.monkUnits[i] = env.monkUnits[^1]
        env.monkUnits.setLen(env.monkUnits.len - 1)
        break

  when defined(eventLog):
    logDeath(getTeamId(victim), $victim.unitClass,
             "(" & $deathPos.x & "," & $deathPos.y & ")", env.currentStep)

  env.terminated[victim.agentId] = 1.0
  victim.hp = 0
  env.rewards[victim.agentId] += env.config.deathPenalty
  let lanternCount = getInv(victim, ItemLantern)
  let relicCount = getInv(victim, ItemRelic)
  if lanternCount > 0: setInv(victim, ItemLantern, 0)
  if relicCount > 0: setInv(victim, ItemRelic, 0)
  let dropInv = victim.inventory
  let corpse = Thing(kind: (if dropInv.len > 0: Corpse else: Skeleton), pos: deathPos)
  corpse.inventory = dropInv
  env.add(corpse)

  # Apply death animation tint at kill location
  env.applyActionTint(deathPos, DeathTint, DeathTintDuration, ActionTintDeath)

  if lanternCount > 0 or relicCount > 0:
    var candidates: seq[IVec2] = @[]
    for dy in -1 .. 1:
      for dx in -1 .. 1:
        if dx == 0 and dy == 0: continue
        let cand = deathPos + ivec2(dx.int32, dy.int32)
        if isValidPos(cand) and env.isEmpty(cand) and not env.hasDoor(cand) and
            not isBlockedTerrain(env.terrain[cand.x][cand.y]) and not isTileFrozen(cand, env):
          candidates.add(cand)
    let lanternSlots = min(lanternCount, candidates.len)
    for i in 0 ..< lanternSlots:
      let lantern = acquireThing(env, Lantern)
      lantern.pos = candidates[i]
      lantern.teamId = getTeamId(victim)
      lantern.lanternHealthy = true
      env.add(lantern)
    let relicSlots = min(relicCount, candidates.len - lanternSlots)
    for i in 0 ..< relicSlots:
      let relic = Thing(kind: Relic, pos: candidates[lanternSlots + i])
      relic.inventory = emptyInventory()
      env.add(relic)

  victim.inventory = emptyInventory()
  for key in ObservedItemKeys:
    env.updateAgentInventoryObs(victim, key)
  victim.pos = ivec2(-1, -1)

# Apply damage to an agent; respects armor and marks terminated when HP <= 0.
# Returns true if the agent died this call.
proc applyAgentDamage(env: Environment, target: Thing, amount: int, attacker: Thing = nil): bool =
  # Track when this unit was attacked (for defensive stance retaliation)
  target.lastAttackedStep = env.currentStep

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
    # Iterate tankUnits directly (no allocation, avoids collecting all allies then filtering)
    for tank in env.tankUnits:
      if getTeamId(tank) != teamId: continue
      if not isAgentAlive(env, tank): continue
      if isThingFrozen(tank, env): continue
      let radius = if tank.unitClass == UnitKnight: 2 else: 1
      if max(abs(tank.pos.x - target.pos.x), abs(tank.pos.y - target.pos.y)) <= radius:
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
    # Spawn floating damage number for combat feedback
    let dmgKind = if bonus > 0: DmgNumCritical else: DmgNumDamage
    env.spawnDamageNumber(target.pos, remaining, dmgKind)

  when defined(combatAudit):
    if remaining > 0 and not attacker.isNil:
      let aTeam = getTeamId(attacker)
      let tTeam = getTeamId(target)
      let dmgType = if attacker.unitClass in {UnitArcher, UnitLongbowman, UnitJanissary,
          UnitCrossbowman, UnitArbalester}: "ranged"
        elif attacker.unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet}: "siege"
        else: "melee"
      recordDamage(env.currentStep, aTeam, tTeam, attacker.agentId, target.agentId,
                   remaining, $attacker.unitClass, $target.unitClass, dmgType)

  when defined(eventLog):
    if remaining > 0 and not attacker.isNil:
      logCombatHit(getTeamId(attacker), getTeamId(target),
                   $attacker.unitClass, $target.unitClass, remaining, env.currentStep)

  if target.hp <= 0:
    when defined(combatAudit):
      if not attacker.isNil:
        recordKill(env.currentStep, getTeamId(attacker), getTeamId(target),
                   attacker.agentId, target.agentId,
                   $attacker.unitClass, $target.unitClass)
    env.killAgent(target)
    return true
  false

# Heal an agent up to its max HP. Returns the amount actually healed.
# Optional healer param for audit tracking.
proc applyAgentHeal(env: Environment, target: Thing, amount: int,
                    healer: Thing = nil): int =
  let before = target.hp
  target.hp = min(target.maxHp, target.hp + amount)
  result = target.hp - before
  # Spawn floating heal number for feedback
  if result > 0:
    env.spawnDamageNumber(target.pos, result, DmgNumHeal)
  when defined(combatAudit):
    if result > 0 and not healer.isNil:
      recordHeal(env.currentStep, getTeamId(healer), getTeamId(target),
                 healer.agentId, target.agentId, result,
                 $healer.unitClass, $target.unitClass)

# Centralized zero-HP handling so agents instantly freeze/die when drained
proc enforceZeroHpDeaths(env: Environment) =
  for agent in env.agents:
    if env.terminated[agent.agentId] == 0.0 and agent.hp <= 0:
      env.killAgent(agent)
