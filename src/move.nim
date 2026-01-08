proc moveAction(env: Environment, id: int, agent: Thing, argument: int) =
  let moveOrientation = Orientation(argument)
  let delta = getOrientationDelta(moveOrientation)

  var step1 = agent.pos
  step1.x += int32(delta.x)
  step1.y += int32(delta.y)

  # Prevent moving onto blocked terrain (bridges remain walkable).
  if isBlockedTerrain(env.terrain[step1.x][step1.y]):
    inc env.stats[id].actionInvalid
    return
  if not env.canAgentPassDoor(agent, step1):
    inc env.stats[id].actionInvalid
    return

  let newOrientation = moveOrientation
  # Allow walking through planted lanterns by relocating the lantern, preferring push direction (up to 2 tiles ahead)
  proc canEnter(pos: IVec2): bool =
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
    if ahead2.x >= 0 and ahead2.x < MapWidth and ahead2.y >= 0 and ahead2.y < MapHeight and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and not isBlockedTerrain(env.terrain[ahead2.x][ahead2.y]) and spacingOk(ahead2):
      env.grid[blocker.pos.x][blocker.pos.y] = nil
      blocker.pos = ahead2
      env.grid[blocker.pos.x][blocker.pos.y] = blocker
      relocated = true
    elif ahead1.x >= 0 and ahead1.x < MapWidth and ahead1.y >= 0 and ahead1.y < MapHeight and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and not isBlockedTerrain(env.terrain[ahead1.x][ahead1.y]) and spacingOk(ahead1):
      env.grid[blocker.pos.x][blocker.pos.y] = nil
      blocker.pos = ahead1
      env.grid[blocker.pos.x][blocker.pos.y] = blocker
      relocated = true
    # Fallback to any adjacent empty tile around the lantern
    if not relocated:
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          if dx == 0 and dy == 0: continue
          let alt = ivec2(pos.x + dx, pos.y + dy)
          if alt.x < 0 or alt.y < 0 or alt.x >= MapWidth or alt.y >= MapHeight: continue
          if env.isEmpty(alt) and not env.hasDoor(alt) and not isBlockedTerrain(env.terrain[alt.x][alt.y]) and spacingOk(alt):
            env.grid[blocker.pos.x][blocker.pos.y] = nil
            blocker.pos = alt
            env.grid[blocker.pos.x][blocker.pos.y] = blocker
            relocated = true
            break
        if relocated: break
    return relocated

  var finalPos = step1
  if not canEnter(step1):
    let blocker = env.getThing(step1)
    if not isNil(blocker) and blocker.kind in {Tree} and not isThingFrozen(blocker, env):
      if env.harvestTree(agent, blocker):
        inc env.stats[id].actionUse
        return
    inc env.stats[id].actionInvalid
    return

  # Roads accelerate movement in the direction of entry.
  if env.terrain[step1.x][step1.y] == Road:
    let step2 = ivec2(agent.pos.x + delta.x.int32 * 2, agent.pos.y + delta.y.int32 * 2)
    if isValidPos(step2) and not isBlockedTerrain(env.terrain[step2.x][step2.y]) and env.canAgentPassDoor(agent, step2):
      if canEnter(step2):
        finalPos = step2

  env.grid[agent.pos.x][agent.pos.y] = nil
  # Clear old position and set new position
  env.updateObservations(AgentLayer, agent.pos, 0)  # Clear old
  agent.pos = finalPos
  agent.orientation = newOrientation
  env.grid[agent.pos.x][agent.pos.y] = agent

  # Update observations for new position only
  env.updateObservations(AgentLayer, agent.pos, getTeamId(agent.agentId) + 1)
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  inc env.stats[id].actionMove

proc orientAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Change orientation without moving.
  if argument < 0 or argument > 7:
    inc env.stats[id].actionInvalid
    return
  let newOrientation = Orientation(argument)
  if agent.orientation != newOrientation:
    agent.orientation = newOrientation
    env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  inc env.stats[id].actionOrient

proc swapAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Swap
  if argument > 7:
    inc env.stats[id].actionInvalid
    return
  let dir = Orientation(argument)
  agent.orientation = dir
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  let targetPos = agent.pos + orientationToVec(dir)
  let target = env.getThing(targetPos)
  if isNil(target) or target.kind != Agent or isThingFrozen(target, env):
    inc env.stats[id].actionInvalid
    return
  var temp = agent.pos
  agent.pos = target.pos
  target.pos = temp
  inc env.stats[id].actionSwap
