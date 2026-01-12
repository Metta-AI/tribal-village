const
  TrailDecay = 0.9985'f32
  TumorDecay = 0.995'f32
  TintStrengthScale = 80000.0'f32
  TumorIncrementBase = 30.0'f32

template markActiveTile(active: var ActiveTiles, tileX, tileY: int) =
  if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
    if not active.flags[tileX][tileY]:
      active.flags[tileX][tileY] = true
      active.positions.add(ivec2(tileX, tileY))

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Clear previous frame's modifications
  var writeIdx = 0
  for readIdx in 0 ..< env.activeTiles.positions.len:
    let pos = env.activeTiles.positions[readIdx]
    if not isValidPos(pos):
      continue
    let tileX = pos.x.int
    let tileY = pos.y.int
    let current = env.tintMods[tileX][tileY]
    let strength = env.tintStrength[tileX][tileY]
    let r = int(round(current.r.float32 * TrailDecay))
    let g = int(round(current.g.float32 * TrailDecay))
    let b = int(round(current.b.float32 * TrailDecay))
    let s = int(round(strength.float32 * TrailDecay))
    if abs(s) < MinTintEpsilon:
      env.tintMods[tileX][tileY] = TintModification(r: 0'i32, g: 0'i32, b: 0'i32)
      env.tintStrength[tileX][tileY] = 0
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      env.activeTiles.flags[tileX][tileY] = false
      continue
    env.tintMods[tileX][tileY] = TintModification(r: r.int32, g: g.int32, b: b.int32)
    env.tintStrength[tileX][tileY] = s.int32
    env.activeTiles.positions[writeIdx] = pos
    inc writeIdx
  env.activeTiles.positions.setLen(writeIdx)

  writeIdx = 0
  for readIdx in 0 ..< env.tumorActiveTiles.positions.len:
    let pos = env.tumorActiveTiles.positions[readIdx]
    if not isValidPos(pos):
      continue
    let tileX = pos.x.int
    let tileY = pos.y.int
    let current = env.tumorTintMods[tileX][tileY]
    let strength = env.tumorStrength[tileX][tileY]
    let r = int(round(current.r.float32 * TumorDecay))
    let g = int(round(current.g.float32 * TumorDecay))
    let b = int(round(current.b.float32 * TumorDecay))
    let s = int(round(strength.float32 * TumorDecay))
    if abs(s) < MinTintEpsilon:
      env.tumorTintMods[tileX][tileY] = TintModification(r: 0'i32, g: 0'i32, b: 0'i32)
      env.tumorStrength[tileX][tileY] = 0
      env.tumorActiveTiles.flags[tileX][tileY] = false
      continue
    env.tumorTintMods[tileX][tileY] = TintModification(r: r.int32, g: g.int32, b: b.int32)
    env.tumorStrength[tileX][tileY] = s.int32
    env.tumorActiveTiles.positions[writeIdx] = pos
    inc writeIdx
  env.tumorActiveTiles.positions.setLen(writeIdx)

  # Helper: add team tint in a radius with simple Manhattan falloff
  proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
    let minX = max(0, baseX - radius)
    let maxX = min(MapWidth - 1, baseX + radius)
    let minY = max(0, baseY - radius)
    let maxY = min(MapHeight - 1, baseY + radius)
    for tileX in minX .. maxX:
      let dx = tileX - baseX
      for tileY in minY .. maxY:
        let dy = tileY - baseY
        let dist = abs(dx) + abs(dy)
        let falloff = max(1, radius * 2 + 1 - dist)
        markActiveTile(env.activeTiles, tileX, tileY)
        let strength = (scale * 5).float32 * falloff.float32
        safeTintAdd(env.tintStrength[tileX][tileY], int(strength))
        safeTintAdd(env.tintMods[tileX][tileY].r, int(color.r * strength))
        safeTintAdd(env.tintMods[tileX][tileY].g, int(color.g * strength))
        safeTintAdd(env.tintMods[tileX][tileY].b, int(color.b * strength))

  # Process all entities and mark their affected positions as active
  for thing in env.things:
    let pos = thing.pos
    if not isValidPos(pos):
      continue
    let baseX = pos.x.int
    let baseY = pos.y.int

    case thing.kind
    of Agent:
      let tribeId = thing.agentId
      if tribeId < env.agentColors.len:
        addTintArea(baseX, baseY, env.agentColors[tribeId], radius = 2, scale = 90)

    of Lantern:
      if thing.lanternHealthy:
        addTintArea(baseX, baseY, env.teamColors[thing.teamId], radius = 2, scale = 60)
    of Tumor:
      let minX = max(0, baseX - 2)
      let maxX = min(MapWidth - 1, baseX + 2)
      let minY = max(0, baseY - 2)
      let maxY = min(MapHeight - 1, baseY + 2)
      for tileX in minX .. maxX:
        let dx = tileX - baseX
        for tileY in minY .. maxY:
          let dy = tileY - baseY
          let manDist = abs(dx) + abs(dy)
          let falloff = max(1, 5 - manDist)
          markActiveTile(env.tumorActiveTiles, tileX, tileY)
          let strength = TumorIncrementBase * falloff.float32
          safeTintAdd(env.tumorStrength[tileX][tileY], int(strength))
          safeTintAdd(env.tumorTintMods[tileX][tileY].r, int(ClippyTint.r * strength))
          safeTintAdd(env.tumorTintMods[tileX][tileY].g, int(ClippyTint.g * strength))
          safeTintAdd(env.tumorTintMods[tileX][tileY].b, int(ClippyTint.b * strength))

    else:
      discard

proc applyTintModifications(env: Environment) =
  ## Apply tint modifications to entity positions and their surrounding areas

  # Apply modifications only to tiles touched this frame
  proc applyTintAt(tileX, tileY: int) =
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      return

    let dynTint = env.tintMods[tileX][tileY]
    let tumorTint = env.tumorTintMods[tileX][tileY]
    let rTint = dynTint.r + tumorTint.r
    let gTint = dynTint.g + tumorTint.g
    let bTint = dynTint.b + tumorTint.b
    let strength = env.tintStrength[tileX][tileY] + env.tumorStrength[tileX][tileY]

    if abs(strength) < MinTintEpsilon:
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      return

    if env.terrain[tileX][tileY] == Water:
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      return

    let alpha = min(1.0'f32, strength.float32 / TintStrengthScale)
    let invStrength = if strength != 0: 1.0'f32 / strength.float32 else: 0.0'f32
    let clampedR = min(1.2'f32, max(0.0'f32, rTint.float32 * invStrength))
    let clampedG = min(1.2'f32, max(0.0'f32, gTint.float32 * invStrength))
    let clampedB = min(1.2'f32, max(0.0'f32, bTint.float32 * invStrength))
    env.computedTintColors[tileX][tileY] = TileColor(
      r: clampedR,
      g: clampedG,
      b: clampedB,
      intensity: alpha
    )

  for pos in env.activeTiles.positions:
    applyTintAt(pos.x.int, pos.y.int)

  for pos in env.tumorActiveTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if env.activeTiles.flags[tileX][tileY]:
      continue
    applyTintAt(tileX, tileY)
