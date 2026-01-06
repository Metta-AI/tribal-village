# This file is included by src/policies.nim
include "rules"
include "roles"
proc decideAction*(controller: Controller, env: Environment, agentId: int): uint8 =
  let agent = env.agents[agentId]

  # Skip inactive agents
  if not isAgentAlive(env, agent):
    return encodeAction(0'u8, 0'u8)

  # Initialize agent role if needed (2 gatherers, 2 builders, 2 fighters)
  if agentId notin controller.agents:
    let role =
      case agentId mod MapAgentsPerVillage
      of 0, 1: Gatherer
      of 2, 3: Builder
      of 4, 5: Fighter
      else:
        sample(controller.rng, [Gatherer, Builder, Fighter])

    controller.agents[agentId] = AgentState(
      role: role,
      spiralStepsInArc: 0,
      spiralArcsCompleted: 0,
      spiralClockwise: (agentId mod 2) == 0,
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

  # Small dithering chance to break deadlocks (lower for gatherers to stay focused)
  let ditherChance = if state.role == Gatherer: 0.10 else: 0.20
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
  # Anchor spiral search around home altar when possible (common base-centric search)
  if agent.homeAltar.x >= 0:
    state.basePosition = agent.homeAltar
  else:
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
  of Gatherer: return decideGatherer(controller, env, agent, agentId, state)
  of Builder: return decideBuilder(controller, env, agent, agentId, state)
  of Fighter: return decideFighter(controller, env, agent, agentId, state)

# Compatibility function for updateController
proc updateController*(controller: Controller) =
  # No complex state to update - keep it simple
  discard
