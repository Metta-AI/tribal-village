const
  # Integer decay: multiply by N and divide by D to avoid round() calls.
  # TrailDecay 0.9985 ≈ 9985/10000, TumorDecay 0.995 ≈ 995/1000
  TrailDecayNum = 9985'i32
  TrailDecayDen = 10000'i32
  TumorDecayNum = 995'i32
  TumorDecayDen = 1000'i32
  InvTintStrengthScale = 1.0'f32 / 80000.0'f32  # Pre-computed reciprocal of TintStrengthScale
  TumorIncrementBase = 30.0'f32

template markActiveTile(active: var ActiveTiles, tileX, tileY: int) =
  if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
    if not active.flags[tileX][tileY]:
      active.flags[tileX][tileY] = true
      active.positions.add(ivec2(tileX, tileY))

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Adaptive epsilon: cull weaker trails when active tile count is high
  let tileCount = env.activeTiles.positions.len
  let epsilon =
    if tileCount > 3000: MinTintEpsilon * 20  # Aggressive cleanup
    elif tileCount > 2000: MinTintEpsilon * 10
    elif tileCount > 1000: MinTintEpsilon * 4
    else: MinTintEpsilon

  # Decay existing tint trails using integer arithmetic (avoids expensive round() calls)
  # Widen to int64 for multiply to avoid int32 overflow (MaxTintAccum * 9985 > int32.max)
  var writeIdx = 0
  for readIdx in 0 ..< tileCount:
    let pos = env.activeTiles.positions[readIdx]
    if not isValidPos(pos):
      continue
    let tileX = pos.x.int
    let tileY = pos.y.int
    let current = env.tintMods[tileX][tileY]
    let strength = env.tintStrength[tileX][tileY]
    let decayedR = int32((current.r.int64 * TrailDecayNum) div TrailDecayDen)
    let g = int32((current.g.int64 * TrailDecayNum) div TrailDecayDen)
    let b = int32((current.b.int64 * TrailDecayNum) div TrailDecayDen)
    let decayedStrength = int32((strength.int64 * TrailDecayNum) div TrailDecayDen)
    if abs(decayedStrength) < epsilon:
      env.tintMods[tileX][tileY] = TintModification(r: 0'i32, g: 0'i32, b: 0'i32)
      env.tintStrength[tileX][tileY] = 0
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      env.activeTiles.flags[tileX][tileY] = false
      continue
    env.tintMods[tileX][tileY] = TintModification(r: decayedR, g: g, b: b)
    env.tintStrength[tileX][tileY] = decayedStrength
    env.activeTiles.positions[writeIdx] = pos
    inc writeIdx
  env.activeTiles.positions.setLen(writeIdx)

  # Adaptive epsilon for tumor tiles
  let tumorTileCount = env.tumorActiveTiles.positions.len
  let tumorEpsilon =
    if tumorTileCount > 3000: MinTintEpsilon * 20
    elif tumorTileCount > 2000: MinTintEpsilon * 10
    elif tumorTileCount > 1000: MinTintEpsilon * 4
    else: MinTintEpsilon

  writeIdx = 0
  for readIdx in 0 ..< tumorTileCount:
    let pos = env.tumorActiveTiles.positions[readIdx]
    if not isValidPos(pos):
      continue
    let tileX = pos.x.int
    let tileY = pos.y.int
    let current = env.tumorTintMods[tileX][tileY]
    let strength = env.tumorStrength[tileX][tileY]
    let decayedR = int32((current.r.int64 * TumorDecayNum) div TumorDecayDen)
    let g = int32((current.g.int64 * TumorDecayNum) div TumorDecayDen)
    let b = int32((current.b.int64 * TumorDecayNum) div TumorDecayDen)
    let decayedStrength = int32((strength.int64 * TumorDecayNum) div TumorDecayDen)
    if abs(decayedStrength) < tumorEpsilon:
      env.tumorTintMods[tileX][tileY] = TintModification(r: 0'i32, g: 0'i32, b: 0'i32)
      env.tumorStrength[tileX][tileY] = 0
      env.tumorActiveTiles.flags[tileX][tileY] = false
      continue
    env.tumorTintMods[tileX][tileY] = TintModification(r: decayedR, g: g, b: b)
    env.tumorStrength[tileX][tileY] = decayedStrength
    env.tumorActiveTiles.positions[writeIdx] = pos
    inc writeIdx
  env.tumorActiveTiles.positions.setLen(writeIdx)

  # Helper: add team tint in a radius with simple Manhattan falloff
  # Uses direct addition (values are always positive, overflow to MaxTintAccum is safe)
  proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
    let minX = max(0, baseX - radius)
    let maxX = min(MapWidth - 1, baseX + radius)
    let minY = max(0, baseY - radius)
    let maxY = min(MapHeight - 1, baseY + radius)
    let baseStrength = (scale * 5).int32
    for tileX in minX .. maxX:
      let dx = tileX - baseX
      for tileY in minY .. maxY:
        if env.tintLocked[tileX][tileY]:
          continue
        let dy = tileY - baseY
        let dist = abs(dx) + abs(dy)
        let falloff = max(1, radius * 2 + 1 - dist).int32
        markActiveTile(env.activeTiles, tileX, tileY)
        let strength = baseStrength * falloff
        env.tintStrength[tileX][tileY] = min(MaxTintAccum, env.tintStrength[tileX][tileY] + strength)
        env.tintMods[tileX][tileY].r = min(MaxTintAccum, env.tintMods[tileX][tileY].r + int32(color.r * strength.float32))
        env.tintMods[tileX][tileY].g = min(MaxTintAccum, env.tintMods[tileX][tileY].g + int32(color.g * strength.float32))
        env.tintMods[tileX][tileY].b = min(MaxTintAccum, env.tintMods[tileX][tileY].b + int32(color.b * strength.float32))

  # Process only tint-relevant entity kinds (Agent, Lantern, Tumor) using
  # thingsByKind instead of iterating all env.things (skips ~7000 irrelevant things)
  # Optimization: only add tint for entities that moved since last step
  for thing in env.thingsByKind[Agent]:
    let pos = thing.pos
    if not isValidPos(pos):
      continue
    let agentId = thing.agentId
    if agentId < 0 or agentId >= MapAgents:
      continue
    # Skip tint update if agent hasn't moved (delta optimization).
    let lastPos = env.lastAgentPos[agentId]
    if lastPos == pos and isValidPos(lastPos):
      continue
    # Update tracking and add tint for moved agents.
    env.lastAgentPos[agentId] = pos
    if agentId < env.agentColors.len:
      let baseX = pos.x.int
      let baseY = pos.y.int
      addTintArea(baseX, baseY, env.agentColors[agentId], radius = 2, scale = 90)

  for thing in env.thingsByKind[Lantern]:
    if not thing.lanternHealthy:
      continue
    let pos = thing.pos
    if not isValidPos(pos):
      continue
    # Skip tint update if lantern hasn't moved (delta optimization).
    if thing.lastTintPos == pos and isValidPos(thing.lastTintPos):
      continue
    thing.lastTintPos = pos
    if thing.teamId >= 0 and thing.teamId < env.teamColors.len:
      let baseX = pos.x.int
      let baseY = pos.y.int
      addTintArea(baseX, baseY, env.teamColors[thing.teamId], radius = 2, scale = 60)

  for thing in env.thingsByKind[Tumor]:
    let pos = thing.pos
    if not isValidPos(pos):
      continue
    # Skip tint update if tumor hasn't moved (delta optimization).
    if thing.lastTintPos == pos and isValidPos(thing.lastTintPos):
      continue
    thing.lastTintPos = pos
    let baseX = pos.x.int
    let baseY = pos.y.int
    let minX = max(0, baseX - 2)
    let maxX = min(MapWidth - 1, baseX + 2)
    let minY = max(0, baseY - 2)
    let maxY = min(MapHeight - 1, baseY + 2)
    for tileX in minX .. maxX:
      let dx = tileX - baseX
      for tileY in minY .. maxY:
        if env.tintLocked[tileX][tileY]:
          continue
        let dy = tileY - baseY
        let manDist = abs(dx) + abs(dy)
        let falloff = max(1, 5 - manDist)
        markActiveTile(env.tumorActiveTiles, tileX, tileY)
        let strength = TumorIncrementBase * falloff.float32
        safeTintAdd(env.tumorStrength[tileX][tileY], int(strength))
        safeTintAdd(env.tumorTintMods[tileX][tileY].r, int(ClippyTint.r * strength))
        safeTintAdd(env.tumorTintMods[tileX][tileY].g, int(ClippyTint.g * strength))
        safeTintAdd(env.tumorTintMods[tileX][tileY].b, int(ClippyTint.b * strength))

proc computeTileColor(env: Environment, tileX, tileY: int): TileColor =
  ## Compute the tint color for a single tile based on combined tint modifications
  let zeroTint = TileColor(r: 0, g: 0, b: 0, intensity: 0)
  if env.tintLocked[tileX][tileY]:
    return zeroTint

  let dynTint = env.tintMods[tileX][tileY]
  let tumorTint = env.tumorTintMods[tileX][tileY]
  let rTint = dynTint.r + tumorTint.r
  let gTint = dynTint.g + tumorTint.g
  let bTint = dynTint.b + tumorTint.b
  let strength = env.tintStrength[tileX][tileY] + env.tumorStrength[tileX][tileY]

  if abs(strength) < MinTintEpsilon:
    return zeroTint

  if env.terrain[tileX][tileY] == Water:
    return zeroTint

  # Use pre-computed reciprocal for TintStrengthScale; multiply instead of divide
  let alpha = min(1.0'f32, strength.float32 * InvTintStrengthScale)
  let invStrength = if strength != 0: 1.0'f32 / strength.float32 else: 0.0'f32
  let clampedR = min(1.2'f32, max(0.0'f32, rTint.float32 * invStrength))
  let clampedG = min(1.2'f32, max(0.0'f32, gTint.float32 * invStrength))
  let clampedB = min(1.2'f32, max(0.0'f32, bTint.float32 * invStrength))
  TileColor(r: clampedR, g: clampedG, b: clampedB, intensity: alpha)

proc cmpByX(a, b: IVec2): int = cmp(a.x, b.x)

proc applyTintModifications(env: Environment) =
  ## Apply tint modifications to entity positions and their surrounding areas
  # Sort by X coordinate for cache-friendly access to array[MapWidth][MapHeight] layout
  env.activeTiles.positions.sort(cmpByX)

  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      continue
    env.computedTintColors[tileX][tileY] = computeTileColor(env, tileX, tileY)

  for pos in env.tumorActiveTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if env.activeTiles.flags[tileX][tileY]:
      continue
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      continue
    env.computedTintColors[tileX][tileY] = computeTileColor(env, tileX, tileY)
