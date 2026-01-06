proc clearTintModifications(env: Environment) =
  ## Clear only active tile modifications for performance
  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
      env.tintMods[tileX][tileY] = TintModification(r: 0, g: 0, b: 0)
      env.computedTintColors[tileX][tileY] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
      env.activeTiles.flags[tileX][tileY] = false

  # Clear the active list for next frame
  env.activeTiles.positions.setLen(0)

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
      safeTintAdd(env.tumorTintMods[tileX][tileY].r, -15 * intensityDelta * falloff)
      safeTintAdd(env.tumorTintMods[tileX][tileY].g, -8 * intensityDelta * falloff)
      safeTintAdd(env.tumorTintMods[tileX][tileY].b, 20 * intensityDelta * falloff)

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Clear previous frame's modifications
  if env.currentStep mod 5 != 0 and env.currentStep > 0:
    return
  env.clearTintModifications()

  # Helper: add team tint in a radius with simple Manhattan falloff
  proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
    let minX = max(0, baseX - radius)
    let maxX = min(MapWidth - 1, baseX + radius)
    let minY = max(0, baseY - radius)
    let maxY = min(MapHeight - 1, baseY + radius)
    let colorR = color.r - 0.7
    let colorG = color.g - 0.65
    let colorB = color.b - 0.6
    for tileX in minX .. maxX:
      let dx = tileX - baseX
      for tileY in minY .. maxY:
        let dy = tileY - baseY
        let dist = abs(dx) + abs(dy)
        let falloff = max(1, radius * 2 + 1 - dist)
        markActiveTile(env.activeTiles, tileX, tileY)
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
      if tribeId < agentVillageColors.len:
        addTintArea(baseX, baseY, agentVillageColors[tribeId], radius = 2, scale = 90)

    of Lantern:
      if thing.lanternHealthy and thing.teamId >= 0 and thing.teamId < teamColors.len:
        addTintArea(baseX, baseY, teamColors[thing.teamId], radius = 2, scale = 60)

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

    let base = env.baseTintColors[tileX][tileY]
    let deltaR = rTint.float32 / 10000.0
    let deltaG = gTint.float32 / 10000.0
    let deltaB = bTint.float32 / 10000.0
    let clampedR = min(max(base.r + deltaR, 0.3), 1.2)
    let clampedG = min(max(base.g + deltaG, 0.3), 1.2)
    let clampedB = min(max(base.b + deltaB, 0.3), 1.2)
    env.computedTintColors[tileX][tileY] = TileColor(
      r: clampedR - base.r,
      g: clampedG - base.g,
      b: clampedB - base.b,
      intensity: 0
    )

  for pos in env.activeTiles.positions:
    applyTintAt(pos.x.int, pos.y.int)

  for pos in env.tumorActiveTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if env.activeTiles.flags[tileX][tileY]:
      continue
    applyTintAt(tileX, tileY)
