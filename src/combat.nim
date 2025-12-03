## Helper routines for action-based combat visuals (included into environment.nim)

proc applyActionTint(env: Environment, pos: IVec2, tintColor: TileColor, duration: int8) =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return
  env.actionTintColor[pos.x][pos.y] = tintColor
  env.actionTintCountdown[pos.x][pos.y] = duration
  if not env.actionTintFlags[pos.x][pos.y]:
    env.actionTintFlags[pos.x][pos.y] = true
    env.actionTintPositions.add(pos)

proc applyShieldBand(env: Environment, agent: Thing, orientation: Orientation) =
  ## 3-wide band directly in front of the agent
  let d = getOrientationDelta(orientation)
  let perp = if d.x != 0: ivec2(0, 1) else: ivec2(1, 0)
  let forward = agent.pos + ivec2(d.x, d.y)
  let tint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.1) # golden amber
  for offset in -1 .. 1:
    let p = forward + ivec2(perp.x * offset, perp.y * offset)
    env.applyActionTint(p, tint, 2)

proc applySpearStrike(env: Environment, agent: Thing, orientation: Orientation) =
  ## Spear hits 3 tiles straight and 3 tiles on each forward diagonal
  let d = getOrientationDelta(orientation)
  let left = ivec2(-d.y, d.x)
  let right = ivec2(d.y, -d.x)
  let tint = TileColor(r: 0.9, g: 0.15, b: 0.15, intensity: 1.15) # red streak
  for step in 1 .. 3:
    env.applyActionTint(agent.pos + ivec2(d.x * step, d.y * step), tint, 2)
    env.applyActionTint(agent.pos + ivec2(d.x * step + left.x * step, d.y * step + left.y * step), tint, 2)
    env.applyActionTint(agent.pos + ivec2(d.x * step + right.x * step, d.y * step + right.y * step), tint, 2)

proc applyHealBurst(env: Environment, agent: Thing) =
  ## Heal in a 3x3 area around agent (inclusive)
  let tint = TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.1) # green glow
  for dx in -1 .. 1:
    for dy in -1 .. 1:
      env.applyActionTint(agent.pos + ivec2(dx, dy), tint, 2)
