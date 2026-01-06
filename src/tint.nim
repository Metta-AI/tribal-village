const
  TrailDecay = 0.985'f32
  TintStrengthScale = 8000.0'f32
  TumorTintScale = 60.0'f32

proc decayTintModifications(env: Environment) =
  ## Decay active tile modifications so agents leave fading trails.
  var writeIdx = 0
  for readIdx in 0 ..< env.activeTiles.positions.len:
    let pos = env.activeTiles.positions[readIdx]
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      continue
    let current = env.tintMods[tileX][tileY]
    let r = int(round(current.r.float32 * TrailDecay))
    let g = int(round(current.g.float32 * TrailDecay))
    let b = int(round(current.b.float32 * TrailDecay))
    if abs(r) < MinTintEpsilon and abs(g) < MinTintEpsilon and abs(b) < MinTintEpsilon:
      env.tintMods[tileX][tileY] = TintModification(r: 0, g: 0, b: 0)
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      env.activeTiles.flags[tileX][tileY] = false
      continue
    env.tintMods[tileX][tileY] = TintModification(r: r.int16, g: g.int16, b: b.int16)
    env.activeTiles.positions[writeIdx] = pos
    inc writeIdx
  env.activeTiles.positions.setLen(writeIdx)

template markActiveTile(active: var ActiveTiles, tileX, tileY: int) =
  if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
    if not active.flags[tileX][tileY]:
      active.flags[tileX][tileY] = true
      active.positions.add(ivec2(tileX, tileY))

proc updateTumorInfluence*(env: Environment, pos: IVec2, intensityDelta: int) =
  if intensityDelta == 0:
    return
  let baseX = pos.x.int
  let baseY = pos.y.int
  if baseX < 0 or baseX >= MapWidth or baseY < 0 or baseY >= MapHeight:
    return
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
      let strength = TumorTintScale * falloff.float32 * intensityDelta.float32
      safeTintAdd(env.tumorTintMods[tileX][tileY].r, int(ClippyTint.r * strength))
      safeTintAdd(env.tumorTintMods[tileX][tileY].g, int(ClippyTint.g * strength))
      safeTintAdd(env.tumorTintMods[tileX][tileY].b, int(ClippyTint.b * strength))

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Clear previous frame's modifications
  env.decayTintModifications()

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
        let colorR = color.r
        let colorG = color.g
        let colorB = color.b
        let strength = (scale * 5).float32 * falloff.float32
        safeTintAdd(env.tintMods[tileX][tileY].r, int(colorR * strength))
        safeTintAdd(env.tintMods[tileX][tileY].g, int(colorG * strength))
        safeTintAdd(env.tintMods[tileX][tileY].b, int(colorB * strength))

  # Process all entities and mark their affected positions as active
  for thing in env.things:
    let pos = thing.pos
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    let baseX = pos.x.int
    let baseY = pos.y.int

    case thing.kind
    of Agent:
      let tribeId = thing.agentId
      if tribeId < env.agentColors.len:
        addTintArea(baseX, baseY, env.agentColors[tribeId], radius = 2, scale = 90)

    of Lantern:
      if thing.lanternHealthy and thing.teamId >= 0 and thing.teamId < env.teamColors.len:
        addTintArea(baseX, baseY, env.teamColors[thing.teamId], radius = 2, scale = 60)

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
    let rTint = int(dynTint.r) + int(tumorTint.r)
    let gTint = int(dynTint.g) + int(tumorTint.g)
    let bTint = int(dynTint.b) + int(tumorTint.b)

    if abs(rTint) < MinTintEpsilon and abs(gTint) < MinTintEpsilon and abs(bTint) < MinTintEpsilon:
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      return

    if env.terrain[tileX][tileY] == Water:
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      return

    let rawR = max(0.0'f32, rTint.float32 / TintStrengthScale)
    let rawG = max(0.0'f32, gTint.float32 / TintStrengthScale)
    let rawB = max(0.0'f32, bTint.float32 / TintStrengthScale)
    let maxC = max(rawR, max(rawG, rawB))
    let alpha = min(1.0'f32, maxC)
    let norm = if maxC > 0.0'f32: maxC else: 1.0'f32
    let clampedR = min(1.2'f32, rawR / norm)
    let clampedG = min(1.2'f32, rawG / norm)
    let clampedB = min(1.2'f32, rawB / norm)
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
