# This file is included by src/ai_policies.nim
include "ai_common_rules"
include "ai_role_includes"
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
        sample(controller.rng, [Hearter, Armorer, Hunter, Baker, Lighter, Farmer,
          Builder, Miner, Smelter, Guard, Medic, Scout, Carpenter, Mason, Brewer])

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
      escapeDirection: ivec2(0, -1),
      builderHasTower: false
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
  of Hearter: return decideHearter(controller, env, agent, agentId, state)
  of Armorer: return decideArmorer(controller, env, agent, agentId, state)
  of Hunter: return decideHunter(controller, env, agent, agentId, state)
  of Baker: return decideBaker(controller, env, agent, agentId, state)
  of Lighter: return decideLighter(controller, env, agent, agentId, state)
  of Farmer: return decideFarmer(controller, env, agent, agentId, state)
  of Builder: return decideBuilder(controller, env, agent, agentId, state)
  of Miner: return decideMiner(controller, env, agent, agentId, state)
  of Smelter: return decideSmelter(controller, env, agent, agentId, state)
  of Guard: return decideGuard(controller, env, agent, agentId, state)
  of Medic: return decideMedic(controller, env, agent, agentId, state)
  of Scout: return decideScout(controller, env, agent, agentId, state)
  of Carpenter: return decideCarpenter(controller, env, agent, agentId, state)
  of Mason: return decideMason(controller, env, agent, agentId, state)
  of Brewer: return decideBrewer(controller, env, agent, agentId, state)

  # Fallback random move
  state.lastPosition = agent.pos
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, randIntInclusive(controller.rng, 0, 7).uint8))

# Compatibility function for updateController
proc updateController*(controller: Controller) =
  # No complex state to update - keep it simple
  discard
