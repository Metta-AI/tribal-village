# This file is included by src/step.nim
const UnitAttackTints: array[AgentUnitClass, TileColor] = [
  # UnitVillager
  TileColor(r: 0.95, g: 0.25, b: 0.20, intensity: 1.10),
  # UnitManAtArms
  TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.10),
  # UnitArcher
  TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.10),
  # UnitScout
  TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.10),
  # UnitKnight
  TileColor(r: 0.20, g: 0.90, b: 0.85, intensity: 1.12),
  # UnitMonk
  TileColor(r: 0.25, g: 0.55, b: 0.95, intensity: 1.12),
  # UnitBatteringRam
  TileColor(r: 0.45, g: 0.35, b: 0.90, intensity: 1.12),
  # UnitMangonel
  TileColor(r: 0.75, g: 0.35, b: 0.95, intensity: 1.18),
  # UnitBoat
  TileColor(r: 0.95, g: 0.35, b: 0.75, intensity: 1.12),
]

const UnitAttackObservationCodes: array[AgentUnitClass, uint8] = [
  ActionTintAttackVillager,
  ActionTintAttackManAtArms,
  ActionTintAttackArcher,
  ActionTintAttackScout,
  ActionTintAttackKnight,
  ActionTintAttackMonk,
  ActionTintAttackBatteringRam,
  ActionTintAttackMangonel,
  ActionTintAttackBoat,
]

const UnitAttackTintDurations: array[AgentUnitClass, int8] = [
  1'i8, # UnitVillager
  2'i8, # UnitManAtArms
  2'i8, # UnitArcher
  1'i8, # UnitScout
  3'i8, # UnitKnight
  2'i8, # UnitMonk
  3'i8, # UnitBatteringRam
  3'i8, # UnitMangonel
  2'i8, # UnitBoat
]

proc applyUnitAttackTint(env: Environment, unit: AgentUnitClass, pos: IVec2) {.inline.} =
  env.applyActionTint(pos, UnitAttackTints[unit], UnitAttackTintDurations[unit], UnitAttackObservationCodes[unit])

proc applyActions(env: Environment, actions: ptr array[MapAgents, uint8]) =
  for id, actionValue in actions[]:
    let agent = env.agents[id]
    if not isAgentAlive(env, agent):
      continue

    let verb = actionValue.int div ActionArgumentCount
    let argument = actionValue.int mod ActionArgumentCount

    case verb:
    of 0:
      inc env.stats[id].actionNoop
    of 1:
      block moveAction:
        let moveOrientation = Orientation(argument)
        let delta = getOrientationDelta(moveOrientation)

        var step1 = agent.pos
        step1.x += int32(delta.x)
        step1.y += int32(delta.y)

        if not env.canTraverseElevation(agent.pos, step1):
          inc env.stats[id].actionInvalid
          break moveAction

        # Prevent moving onto blocked terrain (bridges remain walkable).
        if env.isWaterBlockedForAgent(agent, step1):
          inc env.stats[id].actionInvalid
          break moveAction
        if not env.canAgentPassDoor(agent, step1):
          inc env.stats[id].actionInvalid
          break moveAction

        # Allow walking through planted lanterns by relocating the lantern, preferring push direction (up to 2 tiles ahead)
        proc canEnterFrom(fromPos, pos: IVec2): bool =
          if not isValidPos(pos):
            return false
          if not env.canTraverseElevation(fromPos, pos):
            return false
          var canMove = env.isEmpty(pos)
          if canMove:
            return true
          let blocker = env.getThing(pos)
          if blocker.kind != Lantern:
            return false

          var relocated = false
          # Helper to ensure lantern spacing (Chebyshev >= 3 from other lanterns)
          template spacingOk(nextPos: IVec2): bool =
            var ok = true
            for t in env.thingsByKind[Lantern]:
              if t != blocker:
                let dist = max(abs(t.pos.x - nextPos.x), abs(t.pos.y - nextPos.y))
                if dist < 3'i32:
                  ok = false
                  break
            ok
          # Preferred push positions in move direction
          let ahead1 = ivec2(pos.x + delta.x, pos.y + delta.y)
          let ahead2 = ivec2(pos.x + delta.x * 2, pos.y + delta.y * 2)
          if isValidPos(ahead2) and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and
              not env.isWaterBlockedForAgent(agent, ahead2) and spacingOk(ahead2):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = ahead2
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            relocated = true
          elif isValidPos(ahead1) and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and
              not env.isWaterBlockedForAgent(agent, ahead1) and spacingOk(ahead1):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = ahead1
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            relocated = true
          # Fallback to any adjacent empty tile around the lantern
          if not relocated:
            for dy in -1 .. 1:
              for dx in -1 .. 1:
                if dx == 0 and dy == 0:
                  continue
                let alt = ivec2(pos.x + dx, pos.y + dy)
                if not isValidPos(alt):
                  continue
                if env.isEmpty(alt) and not env.hasDoor(alt) and
                    not env.isWaterBlockedForAgent(agent, alt) and spacingOk(alt):
                  env.grid[blocker.pos.x][blocker.pos.y] = nil
                  blocker.pos = alt
                  env.grid[blocker.pos.x][blocker.pos.y] = blocker
                  relocated = true
                  break
              if relocated:
                break
          return relocated

        let isCavalry = agent.unitClass in {UnitScout, UnitKnight}
        let step2 = ivec2(agent.pos.x + delta.x.int32 * 2, agent.pos.y + delta.y.int32 * 2)

        var finalPos = step1
        if not canEnterFrom(agent.pos, step1):
          let blocker = env.getThing(step1)
          if not isNil(blocker):
            if blocker.kind == Agent and not isThingFrozen(blocker, env) and
                getTeamId(blocker) == getTeamId(agent):
              let agentOld = agent.pos
              let blockerOld = blocker.pos
              agent.pos = blockerOld
              blocker.pos = agentOld
              env.grid[agentOld.x][agentOld.y] = blocker
              env.grid[blockerOld.x][blockerOld.y] = agent
              agent.orientation = moveOrientation
              env.updateObservations(AgentLayer, agentOld, getTeamId(blocker) + 1)
              env.updateObservations(AgentLayer, blockerOld, getTeamId(agent) + 1)
              env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
              env.updateObservations(AgentOrientationLayer, blocker.pos, blocker.orientation.int)
              inc env.stats[id].actionMove
              break moveAction
            if blocker.kind in {Tree} and not isThingFrozen(blocker, env):
              if env.harvestTree(agent, blocker):
                inc env.stats[id].actionUse
                break moveAction
          inc env.stats[id].actionInvalid
          break moveAction

        if isCavalry:
          if isValidPos(step2) and
              not env.isWaterBlockedForAgent(agent, step2) and env.canAgentPassDoor(agent, step2):
            if canEnterFrom(step1, step2):
              finalPos = step2
        else:
          # Roads accelerate movement in the direction of entry.
          if env.terrain[step1.x][step1.y] == Road:
            if isValidPos(step2) and
                not env.isWaterBlockedForAgent(agent, step2) and env.canAgentPassDoor(agent, step2):
              if canEnterFrom(step1, step2):
                finalPos = step2

        env.grid[agent.pos.x][agent.pos.y] = nil
        # Clear old position and set new position
        env.updateObservations(AgentLayer, agent.pos, 0)  # Clear old
        agent.pos = finalPos
        agent.orientation = moveOrientation
        env.grid[agent.pos.x][agent.pos.y] = agent

        let dockHere = env.hasDockAt(agent.pos)
        if agent.unitClass == UnitBoat:
          if dockHere or env.terrain[agent.pos.x][agent.pos.y] != Water:
            disembarkAgent(agent)
        elif dockHere:
          embarkAgent(agent)

        # Update observations for new position only
        env.updateObservations(AgentLayer, agent.pos, getTeamId(agent) + 1)
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        inc env.stats[id].actionMove
    of 2:
      block attackAction:
        ## Attack an entity in the given direction. Spears extend range to 2 tiles.
        if argument > 7:
          inc env.stats[id].actionInvalid
          break attackAction
        let attackOrientation = Orientation(argument)
        agent.orientation = attackOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = getOrientationDelta(attackOrientation)
        let attackerTeam = getTeamId(agent)
        let damageAmount = max(1, agent.attackDamage)
        let rangedRange = case agent.unitClass
          of UnitArcher: ArcherBaseRange
          else: 0
        let hasSpear = agent.inventorySpear > 0 and rangedRange == 0
        let maxRange = if hasSpear: 2 else: 1

        proc tryHitAt(pos: IVec2): bool =
          if not isValidPos(pos):
            return false
          let door = env.getOverlayThing(pos)
          if not isNil(door) and door.kind == Door and door.teamId != attackerTeam:
            discard env.applyStructureDamage(door, damageAmount, agent)
            return true
          let structure = env.getThing(pos)
          if not isNil(structure) and isAttackableStructure(structure.kind):
            if structure.teamId != attackerTeam:
              discard env.applyStructureDamage(structure, damageAmount, agent)
              return true
          var target = env.getThing(pos)
          if isNil(target):
            target = env.getOverlayThing(pos)
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
            if getTeamId(target) == attackerTeam:
              return false
            discard env.applyAgentDamage(target, damageAmount, agent)
            return true
          of Altar:
            if target.teamId == attackerTeam:
              return false
            target.hearts = max(0, target.hearts - 1)
            env.updateObservations(altarHeartsLayer, target.pos, target.hearts)
            if target.hearts == 0:
              let oldTeam = target.teamId
              target.teamId = attackerTeam
              if attackerTeam >= 0 and attackerTeam < env.teamColors.len:
                env.altarColors[target.pos] = env.teamColors[attackerTeam]
              if oldTeam >= 0:
                for door in env.thingsByKind[Door]:
                  if door.teamId == oldTeam:
                    door.teamId = attackerTeam
            return true
          of Cow:
            if not env.giveItem(agent, ItemMeat):
              return false
            removeThing(env, target)
            if ResourceNodeInitial > 1:
              let corpse = Thing(kind: Corpse, pos: pos)
              corpse.inventory = emptyInventory()
              setInv(corpse, ItemMeat, ResourceNodeInitial - 1)
              env.add(corpse)
            return true
          of Tree:
            return env.harvestTree(agent, target)
          else:
            return false

        if agent.unitClass == UnitMonk:
          let healPos = agent.pos + ivec2(delta.x, delta.y)
          let target = env.getThing(healPos)
          if not isNil(target) and target.kind == Agent:
            if getTeamId(target) == attackerTeam:
              discard env.applyAgentHeal(target, 1)
              env.applyActionTint(healPos, TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1), 2, ActionTintHealMonk)
              inc env.stats[id].actionAttack
            else:
              let newTeam = attackerTeam
              if newTeam < 0 or newTeam >= MapRoomObjectsHouses:
                inc env.stats[id].actionInvalid
                break attackAction
              var popCap = 0
              for thing in env.things:
                if thing.teamId == newTeam and isBuildingKind(thing.kind):
                  let add = buildingPopCap(thing.kind)
                  if add > 0:
                    popCap += add
              var popCount = 0
              for other in env.agents:
                if isAgentAlive(env, other) and getTeamId(other) == newTeam:
                  inc popCount
              if popCap <= 0 or popCount >= popCap:
                inc env.stats[id].actionInvalid
                break attackAction
              var newHome = ivec2(-1, -1)
              if agent.homeAltar.x >= 0:
                let altarThing = env.getThing(agent.homeAltar)
                if not isNil(altarThing) and altarThing.kind == Altar and
                    altarThing.teamId == newTeam:
                  newHome = agent.homeAltar
              if newHome.x < 0:
                var bestDist = int.high
                for altar in env.thingsByKind[Altar]:
                  if altar.teamId != newTeam:
                    continue
                  let dist = abs(altar.pos.x - target.pos.x) + abs(altar.pos.y - target.pos.y)
                  if dist < bestDist:
                    bestDist = dist
                    newHome = altar.pos
              target.homeAltar = newHome
              let defaultTeam = getTeamId(target.agentId)
              if newTeam == defaultTeam:
                target.teamIdOverride = -1
              else:
                target.teamIdOverride = newTeam
              if newTeam < env.teamColors.len:
                env.agentColors[target.agentId] = env.teamColors[newTeam]
              env.updateObservations(AgentLayer, target.pos, newTeam + 1)
              env.applyUnitAttackTint(agent.unitClass, healPos)
              inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass == UnitMangonel:
          var hit = false
          let left = ivec2(-delta.y, delta.x)
          let right = ivec2(delta.y, -delta.x)
          let offsets = [ivec2(0, 0), left, right, left * 2, right * 2]
          for step in 1 .. MangonelAoELength:
            let forward = agent.pos + ivec2(delta.x * step, delta.y * step)
            for offset in offsets:
              let attackPos = forward + offset
              env.applyUnitAttackTint(agent.unitClass, attackPos)
              if tryHitAt(attackPos):
                hit = true
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if rangedRange > 0:
          var attackHit = false
          for distance in 1 .. rangedRange:
            let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
            env.applyUnitAttackTint(agent.unitClass, attackPos)
            if tryHitAt(attackPos):
              attackHit = true
              break
          if attackHit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        # Armor overlay (defensive flash)
        if agent.inventoryArmor > 0:
          let tint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.1)
          if abs(delta.x) == 1 and abs(delta.y) == 1:
            let diagPos = agent.pos + ivec2(delta.x, delta.y)
            let xPos = agent.pos + ivec2(delta.x, 0)
            let yPos = agent.pos + ivec2(0, delta.y)
            env.applyActionTint(diagPos, tint, 2, ActionTintShield)
            env.applyActionTint(xPos, tint, 2, ActionTintShield)
            env.applyActionTint(yPos, tint, 2, ActionTintShield)
          else:
            let perp = if delta.x != 0: ivec2(0, 1) else: ivec2(1, 0)
            let forward = agent.pos + ivec2(delta.x, delta.y)
            for offset in -1 .. 1:
              let p = forward + ivec2(perp.x * offset, perp.y * offset)
              env.applyActionTint(p, tint, 2, ActionTintShield)
          env.shieldCountdown[agent.agentId] = 2

        # Spear: area strike (3 forward + diagonals)
        if hasSpear:
          var hit = false
          let left = ivec2(-delta.y, delta.x)
          let right = ivec2(delta.y, -delta.x)
          for step in 1 .. 3:
            let forward = agent.pos + ivec2(delta.x * step, delta.y * step)
            env.applyUnitAttackTint(agent.unitClass, forward)
            if tryHitAt(forward):
              hit = true
            # Keep spear width contiguous (no skipping): lateral offset is fixed 1 tile.
            env.applyUnitAttackTint(agent.unitClass, forward + left)
            if tryHitAt(forward + left):
              hit = true
            env.applyUnitAttackTint(agent.unitClass, forward + right)
            if tryHitAt(forward + right):
              hit = true

          if hit:
            agent.inventorySpear = max(0, agent.inventorySpear - 1)
            env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass == UnitScout:
          var hit = false
          for distance in 1 .. 2:
            let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
            env.applyUnitAttackTint(agent.unitClass, attackPos)
            if tryHitAt(attackPos):
              hit = true
              break
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass == UnitBatteringRam:
          var hit = false
          for distance in 1 .. 2:
            let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
            env.applyUnitAttackTint(agent.unitClass, attackPos)
            if tryHitAt(attackPos):
              hit = true
              break
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        if agent.unitClass == UnitBoat:
          var hit = false
          let left = ivec2(-delta.y, delta.x)
          let right = ivec2(delta.y, -delta.x)
          let forward = agent.pos + ivec2(delta.x, delta.y)
          for pos in [forward, forward + left, forward + right]:
            env.applyUnitAttackTint(agent.unitClass, pos)
            if tryHitAt(pos):
              hit = true
          if hit:
            inc env.stats[id].actionAttack
          else:
            inc env.stats[id].actionInvalid
          break attackAction

        var attackHit = false

        for distance in 1 .. maxRange:
          let attackPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
          env.applyUnitAttackTint(agent.unitClass, attackPos)
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
    of 3:
      block useAction:
        ## Use terrain or building with a single action in a direction.
        if argument > 7:
          inc env.stats[id].actionInvalid
          break useAction
        let useOrientation = Orientation(argument)
        agent.orientation = useOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = getOrientationDelta(useOrientation)
        var targetPos = agent.pos
        targetPos.x += int32(delta.x)
        targetPos.y += int32(delta.y)

        if not isValidPos(targetPos):
          inc env.stats[id].actionInvalid
          break useAction

        # Frozen tiles are non-interactable (terrain or things sitting on them)
        if isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break useAction

        var thing = env.getThing(targetPos)
        if isNil(thing):
          thing = env.getOverlayThing(targetPos)
        template setInvAndObs(key: ItemKey, value: int) =
          setInv(agent, key, value)
          env.updateAgentInventoryObs(agent, key)

        template decInv(key: ItemKey) =
          setInvAndObs(key, getInv(agent, key) - 1)

        template incInv(key: ItemKey) =
          setInvAndObs(key, getInv(agent, key) + 1)

        if isNil(thing):
          # Terrain use only when no Thing occupies the tile.
          var used = false
          case env.terrain[targetPos.x][targetPos.y]:
          of Water:
            if env.giveItem(agent, ItemWater):
              agent.reward += env.config.waterReward
              used = true
          of Empty, Grass, Dune, Sand, Snow, Road:
            if env.hasDoor(targetPos):
              used = false
            elif agent.inventoryRelic > 0:
              let canDrop = env.isEmpty(targetPos) and not env.hasDoor(targetPos) and
                not isTileFrozen(targetPos, env) and env.terrain[targetPos.x][targetPos.y] != Water
              if canDrop:
                let relic = Thing(kind: Relic, pos: targetPos)
                relic.inventory = emptyInventory()
                setInv(relic, ItemGold, 0)
                env.add(relic)
                agent.inventoryRelic = agent.inventoryRelic - 1
                env.updateAgentInventoryObs(agent, ItemRelic)
                used = true
            elif agent.inventoryBread > 0:
              decInv(ItemBread)
              let tint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1)
              for dx in -1 .. 1:
                for dy in -1 .. 1:
                  let p = agent.pos + ivec2(dx, dy)
                  env.applyActionTint(p, tint, 2, ActionTintHealBread)
                  let occ = env.getThing(p)
                  if not occ.isNil and occ.kind == Agent:
                    let healAmt = min(BreadHealAmount, occ.maxHp - occ.hp)
                    if healAmt > 0:
                      discard env.applyAgentHeal(occ, healAmt)
              used = true
            else:
              if agent.inventoryWater > 0:
                decInv(ItemWater)
                env.terrain[targetPos.x][targetPos.y] = Fertile
                env.resetTileColor(targetPos)
                env.updateObservations(TintLayer, targetPos, 0)
                used = true
          else:
            used = false

          if used:
            inc env.stats[id].actionUse
          else:
            inc env.stats[id].actionInvalid
          break useAction
        # Building use
        # Prevent interacting with frozen objects/buildings
        if isThingFrozen(thing, env):
          inc env.stats[id].actionInvalid
          break useAction

        var used = false
        template takeFromThing(key: ItemKey, rewardAmount: float32 = 0.0) =
          let stored = getInv(thing, key)
          if stored <= 0:
            removeThing(env, thing)
            used = true
          elif env.giveItem(agent, key):
            let remaining = stored - 1
            if rewardAmount != 0:
              agent.reward += rewardAmount
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, key, remaining)
            used = true
        case thing.kind:
        of Relic:
          let stored = getInv(thing, ItemGold)
          if stored > 0:
            if env.giveItem(agent, ItemGold):
              setInv(thing, ItemGold, stored - 1)
            else:
              used = false
              break useAction
          if agent.inventoryRelic < MapObjectAgentMaxInventory:
            agent.inventoryRelic = agent.inventoryRelic + 1
            env.updateAgentInventoryObs(agent, ItemRelic)
            removeThing(env, thing)
            used = true
          else:
            used = stored > 0
        of Lantern:
          if agent.inventoryLantern < MapObjectAgentMaxInventory:
            agent.inventoryLantern = agent.inventoryLantern + 1
            env.updateAgentInventoryObs(agent, ItemLantern)
            removeThing(env, thing)
            used = true
        of Wheat:
          used = env.harvestWheat(agent, thing)
        of Stubble:
          if env.grantItem(agent, ItemWheat):
            agent.reward += env.config.wheatReward
            let remaining = getInv(thing, ItemWheat) - 1
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, ItemWheat, remaining)
            used = true
        of Stone:
          takeFromThing(ItemStone)
        of Gold:
          takeFromThing(ItemGold)
        of Bush, Cactus:
          takeFromThing(ItemPlant)
        of Stalagmite:
          takeFromThing(ItemStone)
        of Fish:
          takeFromThing(ItemFish)
        of Stump:
          if env.grantItem(agent, ItemWood):
            agent.reward += env.config.woodReward
            let remaining = getInv(thing, ItemWood) - 1
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, ItemWood, remaining)
            used = true
        of Tree:
          used = env.harvestTree(agent, thing)
        of Corpse:
          var lootKey = ItemNone
          var lootCount = 0
          for key, count in thing.inventory.pairs:
            if count > 0:
              lootKey = key
              lootCount = count
              break
          if lootKey != ItemNone:
            if env.giveItem(agent, lootKey):
              let remaining = lootCount - 1
              if remaining <= 0:
                thing.inventory.del(lootKey)
              else:
                setInv(thing, lootKey, remaining)
              var hasItems = false
              for _, count in thing.inventory.pairs:
                if count > 0:
                  hasItems = true
                  break
              if not hasItems:
                removeThing(env, thing)
                if lootKey != ItemMeat:
                  let skeleton = Thing(kind: Skeleton, pos: thing.pos)
                  skeleton.inventory = emptyInventory()
                  env.add(skeleton)
              used = true
        of Magma:  # Magma smelting
          if thing.cooldown == 0 and getInv(agent, ItemGold) > 0 and agent.inventoryBar < MapObjectAgentMaxInventory:
            setInv(agent, ItemGold, getInv(agent, ItemGold) - 1)
            agent.inventoryBar = agent.inventoryBar + 1
            env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, ItemGold))
            env.updateObservations(AgentInventoryBarLayer, agent.pos, agent.inventoryBar)
            thing.cooldown = 0
            if agent.inventoryBar == 1:
              agent.reward += env.config.barReward
            used = true
        of WeavingLoom:
          if thing.cooldown == 0 and agent.inventoryLantern == 0 and
              (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
            if agent.inventoryWood > 0:
              decInv(ItemWood)
            else:
              decInv(ItemWheat)
            setInvAndObs(ItemLantern, 1)
            thing.cooldown = 0
            agent.reward += env.config.clothReward
            used = true
          elif thing.cooldown == 0:
            if env.tryCraftAtStation(agent, StationLoom, thing):
              used = true
        of ClayOven:
          if thing.cooldown == 0:
            if env.tryCraftAtStation(agent, StationOven, thing):
              used = true
            elif agent.inventoryWheat > 0:
              decInv(ItemWheat)
              incInv(ItemBread)
              thing.cooldown = 0
              # No observation layer for bread; optional for UI later
              agent.reward += env.config.foodReward
              used = true
        of Skeleton:
          let stored = getInv(thing, ItemFish)
          if stored > 0 and env.giveItem(agent, ItemFish):
            let remaining = stored - 1
            if remaining <= 0:
              removeThing(env, thing)
            else:
              setInv(thing, ItemFish, remaining)
            used = true
        else:
          if isBuildingKind(thing.kind):
            let useKind = buildingUseKind(thing.kind)
            case useKind
            of UseAltar:
              if thing.cooldown == 0 and agent.inventoryBar >= 1:
                decInv(ItemBar)
                thing.hearts = thing.hearts + 1
                thing.cooldown = MapObjectAltarCooldown
                env.updateObservations(altarHeartsLayer, thing.pos, thing.hearts)
                agent.reward += env.config.heartReward
                used = true
            of UseClayOven:
              if thing.cooldown == 0:
                if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                  used = true
                elif agent.inventoryWheat > 0:
                  decInv(ItemWheat)
                  incInv(ItemBread)
                  thing.cooldown = 0
                  agent.reward += env.config.foodReward
                  used = true
            of UseWeavingLoom:
              if thing.cooldown == 0 and agent.inventoryLantern == 0 and
                  (agent.inventoryWheat > 0 or agent.inventoryWood > 0):
                if agent.inventoryWood > 0:
                  decInv(ItemWood)
                else:
                  decInv(ItemWheat)
                setInvAndObs(ItemLantern, 1)
                thing.cooldown = 0
                agent.reward += env.config.clothReward
                used = true
              elif thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
                if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                  used = true
            of UseBlacksmith:
              if thing.cooldown == 0:
                if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                  used = true
              if not used and thing.teamId == getTeamId(agent):
                if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                  used = true
            of UseMarket:
              if thing.cooldown == 0:
                let teamId = getTeamId(agent)
                if thing.teamId == teamId:
                  var traded = false
                  var carried: seq[tuple[key: ItemKey, count: int]] = @[]
                  for key, count in agent.inventory.pairs:
                    if count <= 0:
                      continue
                    if not isStockpileResourceKey(key):
                      continue
                    carried.add((key: key, count: count))
                  for entry in carried:
                    let key = entry.key
                    let count = entry.count
                    let res = stockpileResourceForItem(key)
                    if res == ResourceWater:
                      continue
                    if res == ResourceGold:
                      let gained = (count * DefaultMarketBuyFoodNumerator) div DefaultMarketBuyFoodDenominator
                      if gained <= 0:
                        continue
                      env.addToStockpile(teamId, ResourceFood, gained)
                      setInv(agent, key, 0)
                      env.updateAgentInventoryObs(agent, key)
                      traded = true
                    else:
                      let gained = (count * DefaultMarketSellNumerator) div DefaultMarketSellDenominator
                      if gained > 0:
                        env.addToStockpile(teamId, ResourceGold, gained)
                        setInv(agent, key, count mod DefaultMarketSellDenominator)
                        env.updateAgentInventoryObs(agent, key)
                        traded = true
                  if traded:
                    thing.cooldown = DefaultMarketCooldown
                    used = true
            of UseDropoff:
              if thing.teamId == getTeamId(agent):
                if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
                  used = true
            of UseDropoffAndStorage:
              if thing.teamId == getTeamId(agent):
                if env.useDropoffBuilding(agent, buildingDropoffResources(thing.kind)):
                  used = true
                if not used and env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                  used = true
            of UseStorage:
              if env.useStorageBuilding(agent, thing, buildingStorageItems(thing.kind)):
                used = true
            of UseTrain:
              if thing.cooldown == 0 and buildingHasTrain(thing.kind):
                if env.tryTrainUnit(agent, thing, buildingTrainUnit(thing.kind),
                    buildingTrainCosts(thing.kind), buildingTrainCooldown(thing.kind)):
                  used = true
            of UseTrainAndCraft:
              if thing.cooldown == 0:
                if buildingHasCraftStation(thing.kind) and env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                  used = true
                elif buildingHasTrain(thing.kind):
                  if env.tryTrainUnit(agent, thing, buildingTrainUnit(thing.kind),
                      buildingTrainCosts(thing.kind), buildingTrainCooldown(thing.kind)):
                    used = true
            of UseCraft:
              if thing.cooldown == 0 and buildingHasCraftStation(thing.kind):
                if env.tryCraftAtStation(agent, buildingCraftStation(thing.kind), thing):
                  used = true
            of UseNone:
              discard

        if not used:
          if tryPickupThing(env, agent, thing):
            used = true

        if used:
          inc env.stats[id].actionUse
        else:
          inc env.stats[id].actionInvalid
    of 4:
      block swapAction:
        ## Swap
        if argument > 7:
          inc env.stats[id].actionInvalid
          break swapAction
        let dir = Orientation(argument)
        agent.orientation = dir
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let targetPos = agent.pos + orientationToVec(dir)
        let target = env.getThing(targetPos)
        if isNil(target) or target.kind != Agent or isThingFrozen(target, env):
          inc env.stats[id].actionInvalid
          break swapAction
        let agentOld = agent.pos
        let targetOld = target.pos
        agent.pos = targetOld
        target.pos = agentOld
        env.grid[agentOld.x][agentOld.y] = target
        env.grid[targetOld.x][targetOld.y] = agent
        env.updateObservations(AgentLayer, agentOld, getTeamId(target) + 1)
        env.updateObservations(AgentLayer, targetOld, getTeamId(agent) + 1)
        env.updateObservations(AgentOrientationLayer, agentOld, target.orientation.int)
        env.updateObservations(AgentOrientationLayer, targetOld, agent.orientation.int)
        inc env.stats[id].actionSwap
    of 5:
      block putAction:
        ## Give items to adjacent teammate in the given direction.
        if argument > 7:
          inc env.stats[id].actionInvalid
          break putAction
        let dir = Orientation(argument)
        agent.orientation = dir
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = getOrientationDelta(dir)
        let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)
        if not isValidPos(targetPos):
          inc env.stats[id].actionInvalid
          break putAction
        let target = env.getThing(targetPos)
        if isNil(target):
          inc env.stats[id].actionInvalid
          break putAction
        if target.kind != Agent or isThingFrozen(target, env):
          inc env.stats[id].actionInvalid
          break putAction
        var transferred = false
        # Give armor if we have any and target has none
        if agent.inventoryArmor > 0 and target.inventoryArmor == 0:
          target.inventoryArmor = agent.inventoryArmor
          agent.inventoryArmor = 0
          transferred = true
        # Otherwise give food if possible (no obs layer yet)
        elif agent.inventoryBread > 0:
          let capacity = stockpileCapacityLeft(target)
          let giveAmt = min(agent.inventoryBread, capacity)
          if giveAmt > 0:
            agent.inventoryBread = agent.inventoryBread - giveAmt
            target.inventoryBread = target.inventoryBread + giveAmt
            transferred = true
        else:
          let stockpileCapacityLeftTarget = stockpileCapacityLeft(target)
          var bestKey = ItemNone
          var bestCount = 0
          for key, count in agent.inventory.pairs:
            if count <= 0:
              continue
            let capacity =
              if isStockpileResourceKey(key):
                stockpileCapacityLeftTarget
              else:
                MapObjectAgentMaxInventory - getInv(target, key)
            if capacity <= 0:
              continue
            if count > bestCount:
              bestKey = key
              bestCount = count
          if bestKey != ItemNone and bestCount > 0:
            let capacity =
              if isStockpileResourceKey(bestKey):
                stockpileCapacityLeftTarget
              else:
                max(0, MapObjectAgentMaxInventory - getInv(target, bestKey))
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
    of 6:
      block plantAction:
        ## Plant lantern in the given direction.
        if argument > 7:
          inc env.stats[id].actionInvalid
          break plantAction
        let plantOrientation = Orientation(argument)
        agent.orientation = plantOrientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = getOrientationDelta(plantOrientation)
        var targetPos = agent.pos
        targetPos.x += int32(delta.x)
        targetPos.y += int32(delta.y)

        # Check if position is empty and not water
        if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break plantAction

        if agent.inventoryLantern > 0:
          # Calculate team ID directly from the planting agent's ID
          let teamId = getTeamId(agent)

          # Plant the lantern
          let lantern = Thing(
            kind: Lantern,
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
        else:
          inc env.stats[id].actionInvalid
    of 7:
      block plantResourceAction:
        ## Plant wheat (args 0-3) or tree (args 4-7) onto an adjacent fertile tile.
        let plantingTree =
          if argument <= 7:
            argument >= 4
          else:
            (argument mod 2) == 1
        let dirIndex =
          if argument <= 7:
            (if plantingTree: argument - 4 else: argument)
          else:
            (if argument mod 2 == 1: (argument div 2) mod 4 else: argument mod 4)
        if dirIndex < 0 or dirIndex > 7:
          inc env.stats[id].actionInvalid
          break plantResourceAction
        let orientation = Orientation(dirIndex)
        agent.orientation = orientation
        env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        let delta = getOrientationDelta(orientation)
        let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)

        # Occupancy checks
        if not env.isEmpty(targetPos) or not isNil(env.getOverlayThing(targetPos)) or env.hasDoor(targetPos) or
            isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
          inc env.stats[id].actionInvalid
          break plantResourceAction
        if env.terrain[targetPos.x][targetPos.y] != Fertile:
          inc env.stats[id].actionInvalid
          break plantResourceAction

        if plantingTree:
          if agent.inventoryWood <= 0:
            inc env.stats[id].actionInvalid
            break plantResourceAction
          agent.inventoryWood = max(0, agent.inventoryWood - 1)
          env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
          let tree = Thing(kind: Tree, pos: targetPos)
          tree.inventory = emptyInventory()
          setInv(tree, ItemWood, ResourceNodeInitial)
          env.add(tree)
        else:
          if agent.inventoryWheat <= 0:
            inc env.stats[id].actionInvalid
            break plantResourceAction
          agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
          env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
          let crop = Thing(kind: Wheat, pos: targetPos)
          crop.inventory = emptyInventory()
          setInv(crop, ItemWheat, ResourceNodeInitial)
          env.add(crop)

        env.terrain[targetPos.x][targetPos.y] = Empty
        env.resetTileColor(targetPos)

        # Consuming fertility (terrain replaced above)
        inc env.stats[id].actionPlantResource
    of 8:
      block buildFromChoices:
        let key = BuildChoices[argument]
        var buildKind: ThingKind
        let isDock = parseThingKey(key, buildKind) and buildKind == Dock

        var offsets: seq[IVec2] = @[]
        for offset in [
          orientationToVec(agent.orientation),
          ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
          ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1)
        ]:
          if (offset.x == 0'i32 and offset.y == 0'i32) or offset in offsets:
            continue
          offsets.add(offset)

        var targetPos = ivec2(-1, -1)
        for offset in offsets:
          let pos = agent.pos + offset
          if (if isDock: env.canPlaceDock(pos) else: env.canPlace(pos)):
            targetPos = pos
            break
        if targetPos.x < 0:
          inc env.stats[id].actionInvalid
          break buildFromChoices

        let teamId = getTeamId(agent)
        let costs = buildCostsForKey(key)
        if costs.len == 0:
          inc env.stats[id].actionInvalid
          break buildFromChoices
        let payment = choosePayment(env, agent, costs)
        if payment == PayNone:
          inc env.stats[id].actionInvalid
          break buildFromChoices

        if placeThingFromKey(env, agent, key, targetPos):
          discard spendCosts(env, agent, payment, costs)
          var kind: ThingKind
          if parseThingKey(key, kind):
            if kind in {Mill, LumberCamp, MiningCamp}:
              var anchor = ivec2(-1, -1)
              var bestDist = int.high
              for thing in env.things:
                if thing.teamId != teamId:
                  continue
                if thing.kind notin {TownCenter, Altar}:
                  continue
                let dist = abs(thing.pos.x - targetPos.x) + abs(thing.pos.y - targetPos.y)
                if dist < bestDist:
                  bestDist = dist
                  anchor = thing.pos
              if anchor.x < 0:
                anchor = targetPos
              var pos = targetPos
              while pos.x != anchor.x:
                pos.x += (if anchor.x < pos.x: -1'i32 elif anchor.x > pos.x: 1'i32 else: 0'i32)
                if env.canPlace(pos, checkFrozen = false):
                  env.terrain[pos.x][pos.y] = Road
                  env.resetTileColor(pos)
              while pos.y != anchor.y:
                pos.y += (if anchor.y < pos.y: -1'i32 elif anchor.y > pos.y: 1'i32 else: 0'i32)
                if env.canPlace(pos, checkFrozen = false):
                  env.terrain[pos.x][pos.y] = Road
                  env.resetTileColor(pos)
          inc env.stats[id].actionBuild
        else:
          inc env.stats[id].actionInvalid
    of 9:
      block orientAction:
        ## Change orientation without moving.
        if argument < 0 or argument > 7:
          inc env.stats[id].actionInvalid
          break orientAction
        let newOrientation = Orientation(argument)
        if agent.orientation != newOrientation:
          agent.orientation = newOrientation
          env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
        inc env.stats[id].actionOrient
    else:
      inc env.stats[id].actionInvalid
