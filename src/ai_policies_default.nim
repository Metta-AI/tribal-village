# This file is included by src/ai_policies.nim
proc decideAction*(controller: Controller, env: Environment, agentId: int): uint8 =
  let agent = env.agents[agentId]

  # Skip frozen agents
  if agent.frozen > 0:
    return encodeAction(0'u8, 0'u8)

  # Initialize agent role if needed (per-house pattern with one guaranteed Hearter)
  if agentId notin controller.agents:
    let role =
      if agentId mod MapAgentsPerHouse == 0:
        Hearter
      else:
        sample(controller.rng, [Hearter, Armorer, Hunter, Baker, Lighter, Farmer])

    controller.agents[agentId] = AgentState(
      role: role,
      spiralStepsInArc: 0,
      spiralArcsCompleted: 0,
      basePosition: agent.pos,
      lastSearchPosition: agent.pos,
      lastPosition: agent.pos,
      recentPositions: @[],
      stuckCounter: 0,
      escapeMode: false,
      escapeStepsRemaining: 0,
      escapeDirection: ivec2(0, -1)
    )

  var state = controller.agents[agentId]

  # --- Simple bail-out and dithering to avoid getting stuck/oscillation ---
  # Update recent positions history (size 4)
  state.recentPositions.add(agent.pos)
  if state.recentPositions.len > 4:
    state.recentPositions.delete(0)

  # Detect stuck: same position or simple 2-cycle oscillation
  if state.recentPositions.len >= 2 and agent.pos == state.lastPosition:
    inc state.stuckCounter
  elif state.recentPositions.len >= 4:
    let p0 = state.recentPositions[^1]
    let p1 = state.recentPositions[^2]
    let p2 = state.recentPositions[^3]
    let p3 = state.recentPositions[^4]
    if (p0 == p2 and p1 == p3) or (p0 == p1):
      inc state.stuckCounter
    else:
      state.stuckCounter = 0
  else:
    state.stuckCounter = 0

  # Enter escape mode if stuck
  if not state.escapeMode and state.stuckCounter >= 3:
    state.escapeMode = true
    state.escapeStepsRemaining = 6
    state.recentPositions.setLen(0)
    # Choose an escape direction: prefer any empty cardinal, shuffled
    var dirs = @[ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]
    for i in countdown(dirs.len - 1, 1):
      let j = randIntInclusive(controller.rng, 0, i)
      let tmp = dirs[i]
      dirs[i] = dirs[j]
      dirs[j] = tmp
    var chosen = ivec2(0, -1)
    for d in dirs:
      if isPassable(env, agent, agent.pos + d):
        chosen = d
        break
    state.escapeDirection = chosen

  # If in escape mode, try to move in escape direction for a few steps
  if state.escapeMode and state.escapeStepsRemaining > 0:
    let tryDirs = @[state.escapeDirection,
                    ivec2(state.escapeDirection.y, -state.escapeDirection.x),  # perpendicular 1
                    ivec2(-state.escapeDirection.y, state.escapeDirection.x),  # perpendicular 2
                    ivec2(-state.escapeDirection.x, -state.escapeDirection.y)] # opposite
    for d in tryDirs:
      let np = agent.pos + d
      if isPassable(env, agent, np):
        dec state.escapeStepsRemaining
        if state.escapeStepsRemaining <= 0:
          state.escapeMode = false
          state.stuckCounter = 0
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))
    # If all blocked, drop out of escape for this tick
    state.escapeMode = false
    state.stuckCounter = 0

  # Small dithering chance to break deadlocks (higher for non-assembler roles)
  let ditherChance = if state.role == Hearter: 0.10 else: 0.20
  if randFloat(controller.rng) < ditherChance:
    var candidates = @[ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
                       ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)]
    for i in countdown(candidates.len - 1, 1):
      let j = randIntInclusive(controller.rng, 0, i)
      let tmp = candidates[i]
      candidates[i] = candidates[j]
      candidates[j] = tmp
    for d in candidates:
      if isPassable(env, agent, agent.pos + d):
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))

  # From here on, ensure lastPosition is updated this tick regardless of branch
  state.lastPosition = agent.pos
  # Anchor spiral search around current agent position each tick
  state.basePosition = agent.pos

  # Emergency self-heal: eat bread if below half HP (applies to all roles)
  if agent.inventoryBread > 0 and agent.hp * 2 < agent.maxHp:
    let healDirs = @[ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),  # cardinals first
                     ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)] # diagonals
    for d in healDirs:
      let target = agent.pos + d
      if not env.hasDoor(target) and isValidEmptyTile(env, agent, target):
        return saveStateAndReturn(
          controller, agentId, state,
          encodeAction(3'u8, neighborDirIndex(agent.pos, target).uint8))

  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  # Role-based decision making
  case state.role:

  of Lighter:
    # Priority 1: Plant lanterns outward in rings from home assembler
    if agent.inventoryLantern > 0:
      # Determine home center (agent.homeassembler); if unset, use agent.pos
      let center = if agent.homeassembler.x >= 0: agent.homeassembler else: agent.pos

      # Compute current preferred ring radius: smallest R where no plantable tile found yet; start at 3
      var planted = false
      let maxR = 12  # don't search too far per step
      for radius in 3 .. maxR:
        # scan the ring (Chebyshev distance == radius) around center
        var bestDir = -1
        for i in 0 .. 7:
          let dir = orientationToVec(Orientation(i))
          let target = agent.pos + dir
          let dist = max(abs(target.x - center.x), abs(target.y - center.y))
          if dist != radius: continue
          if target.x < 0 or target.x >= MapWidth or target.y < 0 or target.y >= MapHeight:
            continue
          if not env.isEmpty(target):
            continue
          if env.hasDoor(target):
            continue
          if env.terrain[target.x][target.y] == Water:
            continue
          var spaced = true
          for t in env.things:
            if t.kind == PlantedLantern and chebyshevDist(target, t.pos) < 3'i32:
              spaced = false
              break
          if spaced:
            bestDir = i
            break
        if bestDir >= 0:
          planted = true
          return saveStateAndReturn(controller, agentId, state, encodeAction(6'u8, bestDir.uint8))

      # If no ring slot found, step outward to expand search radius next tick
      let awayFromCenter = getMoveAway(env, agent, agent.pos, center, controller.rng)
      return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayFromCenter.uint8))

    # Priority 2: If adjacent to an existing lantern without one to plant, push it further away
    elif isAdjacentToLantern(env, agent.pos):
      let near = findNearestLantern(env, agent.pos)
      if near.found and near.dist == 1'i32:
        # Move into the lantern tile to push it (env will relocate; we bias pushing away in moveAction)
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, neighborDirIndex(agent.pos, near.pos).uint8))
      # If diagonally close, step to set up a push next
      let dx = near.pos.x - agent.pos.x
      let dy = near.pos.y - agent.pos.y
      let step = agent.pos + ivec2((if dx != 0: dx div abs(dx) else: 0'i32), (if dy != 0: dy div abs(dy) else: 0'i32))
      return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, neighborDirIndex(agent.pos, step).uint8))

    # Priority 3: Craft lantern if we have wheat
    if agent.inventoryWheat > 0:
      let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, WeavingLoom)
      if did: return act

    # Priority 3: Collect wheat using spiral search
    else:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
      if did: return act

  of Armorer:
    # Priority 1: If we have armor, deliver it to teammates who need it
    if agent.inventoryArmor > 0:
      let teammate = findNearestTeammateNeeding(env, agent, NeedArmor)
      if teammate != nil:
        let dx = abs(teammate.pos.x - agent.pos.x)
        let dy = abs(teammate.pos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          # Give armor via PUT to teammate
          return saveStateAndReturn(controller, agentId, state, encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
        else:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

    # Priority 2: Craft armor if we have wood
    if agent.inventoryWood > 0:
      let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Armory)
      if did: return act

    # Priority 3: Collect wood using spiral search
    else:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
      if did: return act

  of Hunter:
    # Priority 1: Hunt clippies if we have spear using spiral search
    if agent.inventorySpear > 0:
      let tumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
      if tumor != nil:
        let orientIdx = spearAttackDir(agent.pos, tumor.pos)
        if orientIdx >= 0:
          return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, orientIdx.uint8))
        else:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, tumor.pos, controller.rng).uint8))
      else:
        # No clippies found, continue spiral search for hunting
        return controller.moveNextSearch(env, agent, agentId, state)

    # Priority 2: If no spear and a nearby tumor (<=3), retreat away
    let nearbyTumor = env.findNearestThingSpiral(state, Tumor, controller.rng)
    if nearbyTumor != nil and chebyshevDist(agent.pos, nearbyTumor.pos) <= 3:
      let awayDir = getMoveAway(env, agent, agent.pos, nearbyTumor.pos, controller.rng)
      return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, awayDir.uint8))

    # Priority 3: Craft spear if we have wood
    if agent.inventoryWood > 0:
      let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, Forge)
      if did: return act

    # Priority 4: Collect wood using spiral search
    else:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
      if did: return act

  of Farmer:
    let targetFertile = 10
    let fertileCount = countFertileEmpty(env, agent.pos, 8)

    # Step 1: Create fertile ground until target reached
    if fertileCount < targetFertile:
      let wateringPos = findNearestEmpty(env, agent.pos, false, 8)
      if wateringPos.x >= 0:
        if agent.inventoryWater == 0:
          let waterPos = env.findNearestTerrainSpiral(state, Water, controller.rng)
          if waterPos.x >= 0:
            let dx = abs(waterPos.x - agent.pos.x)
            let dy = abs(waterPos.y - agent.pos.y)
            if max(dx, dy) == 1'i32:
              return saveStateAndReturn(controller, agentId, state, encodeAction(3'u8, neighborDirIndex(agent.pos, waterPos).uint8))
            else:
              return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, waterPos, controller.rng).uint8))
        else:
          let dx = abs(wateringPos.x - agent.pos.x)
          let dy = abs(wateringPos.y - agent.pos.y)
          if max(dx, dy) == 1'i32:
            return saveStateAndReturn(controller, agentId, state, encodeAction(3'u8, neighborDirIndex(agent.pos, wateringPos).uint8))
          else:
            return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, wateringPos, controller.rng).uint8))

      return controller.moveNextSearch(env, agent, agentId, state)

    # Step 2: Plant on fertile tiles if holding resources
    block planting:
      let (didPlant, act) = tryPlantOnFertile(controller, env, agent, agentId, state)
      if didPlant:
        return act

    # Step 3: Gather resources to plant (wood then wheat)
    if agent.inventoryWood == 0:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Tree)
      if did: return act

    if agent.inventoryWheat == 0:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
      if did: return act

    # Step 4: If stocked but couldn't plant (no fertile nearby), roam to expand search
    return controller.moveNextSearch(env, agent, agentId, state)

  of Baker:
    # Priority 1: If carrying food, deliver to teammates needing it
    if agent.inventoryBread > 0:
      let teammate = findNearestTeammateNeeding(env, agent, NeedBread)
      if teammate != nil:
        let dx = abs(teammate.pos.x - agent.pos.x)
        let dy = abs(teammate.pos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state, encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
        else:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

    # Priority 2: Craft bread if we have wheat
    if agent.inventoryWheat > 0:
      let (did, act) = controller.findAndUseBuilding(env, agent, agentId, state, ClayOven)
      if did: return act

    # Priority 3: Collect wheat using spiral search
    else:
      let (did, act) = controller.findAndHarvest(env, agent, agentId, state, Wheat)
      if did: return act

  of Hearter:
    # Handle ore → battery → assembler workflow
    if agent.inventoryBattery > 0:
      # Find assembler and deposit battery
      for thing in env.things:
        if thing.kind == assembler and thing.pos == agent.homeassembler:
          let dx = abs(thing.pos.x - agent.pos.x)
          let dy = abs(thing.pos.y - agent.pos.y)
          if max(dx, dy) == 1'i32:
            return saveStateAndReturn(controller, agentId, state, encodeAction(3'u8, neighborDirIndex(agent.pos, thing.pos).uint8))
          else:
            return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, thing.pos, controller.rng).uint8))

    elif agent.inventoryOre > 0:
      # Find converter and make battery using spiral search
      let converterThing = env.findNearestThingSpiral(state, Converter, controller.rng)
      if converterThing != nil:
        # Converter uses GET to consume ore and produce battery
        let dx = abs(converterThing.pos.x - agent.pos.x)
        let dy = abs(converterThing.pos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state, encodeAction(3'u8, neighborDirIndex(agent.pos, converterThing.pos).uint8))
        else:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, converterThing.pos, controller.rng).uint8))
      else:
        # No converter found, continue spiral search
        let nextSearchPos = getNextSpiralPoint(state, controller.rng)
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))

    else:
      # Find mine and collect ore using spiral search
      let mine = env.findNearestThingSpiral(state, Mine, controller.rng)
      if mine != nil:
        let dx = abs(mine.pos.x - agent.pos.x)
        let dy = abs(mine.pos.y - agent.pos.y)
        if max(dx, dy) == 1'i32:
          return saveStateAndReturn(controller, agentId, state, encodeAction(3'u8, neighborDirIndex(agent.pos, mine.pos).uint8))
        else:
          return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, mine.pos, controller.rng).uint8))
      else:
        # No mine found, continue spiral search
        let nextSearchPos = getNextSpiralPoint(state, controller.rng)
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))

  # Save last position for next tick and return a default random move
  state.lastPosition = agent.pos
  return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, randIntInclusive(controller.rng, 0, 7).uint8))

# Compatibility function for updateController
proc updateController*(controller: Controller) =
  # No complex state to update - keep it simple
  discard
